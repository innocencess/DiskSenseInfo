import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement
import DiskArbitration

@MainActor final class AppModel: ObservableObject {
    @Published var disks: [Disk] = []
    @Published var selectedID: String?
    @Published var busy = false
    @Published var error: String?
    @Published var samples: [Sample] = []
    @Published var settings: MonitorSettings { didSet { persistSettings() } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var notificationStatus = ""
    var pendingRescan = false; var timer: Timer?; var sleeping = false; var job: Task<Void, Never>?; var observers: [NSObjectProtocol] = []; var session: DASession?; var topologyJob: Task<Void, Never>?
    let store: HistoryStore
    let resourcesURL: URL
    var gate: AlertGate
    var directory: URL { store.directory }
    var selected: Disk? { disks.first { $0.id == selectedID } ?? disks.first }
    var executable: String { resourcesURL.appendingPathComponent("smartctl").path }
    init(dataDirectory: URL? = nil, resources: URL? = nil, monitor: Bool = true) {
        resourcesURL = resources ?? Bundle.main.resourceURL!
        let dir = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DiskPulse")
        store = HistoryStore(directory: dir)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")), let s = try? JSONDecoder().decode(MonitorSettings.self, from: data) { settings = s } else { settings = MonitorSettings() }
        gate = (try? Data(contentsOf: dir.appendingPathComponent("alerts.json"))).flatMap { try? JSONDecoder().decode(AlertGate.self, from: $0) } ?? AlertGate()
        selectedID = settings.selectedID
        do { samples = try store.load() } catch { try? FileManager.default.moveItem(at: store.historyURL, to: dir.appendingPathComponent("history-recovery-" + UUID().uuidString + ".json")); self.error = "History could not be read: \(error.localizedDescription). Original file moved to a recovery copy." }
        if monitor { start() }
    }
    func tr(_ zh: String, _ en: String) -> String { settings.language == "zh" ? zh : en }
    func message(_ s: String) -> String {
        guard settings.language == "zh" else { return s }
        let replacements = [
            "Device SMART overall assessment passed; this is not a guarantee against failure": "裝置 SMART 整體評估通過；仍無法保證不會故障",
            "No reliable overall SMART assessment available": "無法取得可靠的 SMART 整體評估",
            "Device reports SMART failure": "裝置回報 SMART 故障",
            "Available spare below device threshold": "可用備援空間低於裝置門檻",
            "USB SMART unavailable through current macOS access path": "目前 macOS 讀取方式無法取得此 USB 裝置的 SMART 資料",
            "Device reconnected; waiting for a new SMART read": "磁碟已重新連接；等待重新讀取 SMART",
            "Current SMART read failed": "本次 SMART 讀取失敗",
            "Device offline; displayed values are historical": "磁碟離線；顯示最後取得的資料",
            "Endurance used ≥ ": "耗損比例 ≥ ",
            "Media / data integrity errors ≥ ": "媒體／資料完整性錯誤 ≥ ",
            "Temperature ≥ ": "溫度 ≥ ",
            "NVMe Critical Warning = ": "NVMe 重要警告 = ",
            ": normalized value at/below threshold or failure recorded": "：正規化值已達門檻或有失敗紀錄",
            ": raw count ≥ ": "：原始計數 ≥ "
        ]
        var result = s; for (from,to) in replacements { result = result.replacingOccurrences(of: from, with: to) }; return result
    }
    func healthName(_ h: Health) -> String { switch h { case .normal: return tr("正常", "Normal"); case .caution: return tr("注意", "Caution"); case .danger: return tr("危險", "Danger"); case .unknown: return tr("未知", "Unknown") } }
    func persistSettings() {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("settings.json"), options: .atomic) } catch { self.error = error.localizedDescription }
    }
    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleeping = true; self?.job?.cancel() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleeping = false; self?.refresh(force: false, rescan: true) } })
        session = DASessionCreate(kCFAllocatorDefault)
        if let s = session {
            let context = Unmanaged.passUnretained(self).toOpaque()
            DARegisterDiskAppearedCallback(s, nil, { _, context in guard let context = context else { return }; let model = Unmanaged<AppModel>.fromOpaque(context).takeUnretainedValue(); Task { @MainActor in model.topologyChanged() } }, context)
            DARegisterDiskDisappearedCallback(s, nil, { _, context in guard let context = context else { return }; let model = Unmanaged<AppModel>.fromOpaque(context).takeUnretainedValue(); Task { @MainActor in model.topologyChanged() } }, context)
            DASessionSetDispatchQueue(s, .main)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh(force: false) } }
        refresh(force: true)
    }
    func topologyChanged() {
        topologyJob?.cancel()
        topologyJob = Task { try? await Task.sleep(nanoseconds: 800_000_000); guard !Task.isCancelled else { return }; refresh(force: false, rescan: true) }
    }
    func refresh(force: Bool, rescan: Bool = false) {
        guard !sleeping else { return }; if busy { pendingRescan = pendingRescan || rescan; return }
        let now = Date()
        let due = disks.contains { PollingPolicy.shouldSample($0, settings: settings, now: now, force: false, sleeping: sleeping) }
        guard force || rescan || disks.isEmpty || due else { return }
        busy = true
        let old = disks; let config = settings; let ctl = executable; let db = resourcesURL.appendingPathComponent("drivedb.h").path
        job = Task {
            defer { busy = false; if pendingRescan { pendingRescan = false; refresh(force: false, rescan: true) } }
            do {
                let result = try await DiskDiscovery.discover()
                try Task.checkCancellation()
                var next: [Disk] = []
                for detected in result {
                    try Task.checkCancellation()
                    let previous = old.first { $0.id == detected.id || $0.discoveryID == detected.id }
                    let age = previous?.sampledAt.map { now.timeIntervalSince($0) } ?? Double.infinity
                    let skip = !force && !detected.internalDisk && config.skipExternalHDD && (detected.kind == "HDD" || detected.kind == "Unknown")
                    var d: Disk
                    if !force && (skip || age < (detected.internalDisk ? config.interval : config.externalInterval)), let previous = previous, previous.online {
                        d = SMARTAccessPolicy.restored(previous, discovered: detected)
                    } else if skip {
                        d = detected; d.diagnostics.append("Automatic SMART polling skipped by external HDD / unknown device power-saving policy. Use Refresh for an explicit read.")
                    } else {
                        d = await DiskCollector(smartctlPath: ctl, databasePath: db).collect(detected, settings: config, automatic: !force)
                        try Task.checkCancellation()
                        if d.identityReliable, !d.metrics.isEmpty { samples.append(Sample(d)) }
                        await notify(d, previous: previous)
                    }
                    next.append(d)
                }
                next = DiskTopology.merge(previous: old, current: next)
                let oldSelectionDevice = old.first { $0.id == selectedID }?.device
                disks = next
                if !next.contains(where: { $0.id == selectedID }), let same = next.first(where: { $0.device == oldSelectionDevice && $0.online }) { selectedID = same.id }
                if selectedID == nil { selectedID = next.first?.id }
                settings.selectedID = selectedID
                samples.removeAll { $0.date < now.addingTimeInterval(-Double(settings.retentionDays) * 86400) }
                try await Task.detached { [store, samples, config] in try store.save(samples, days: config.retentionDays) }.value
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    func notify(_ d: Disk, previous: Disk?) async {
        guard settings.notifications, d.online else { return }
        var events = d.health.rank > 0 ? d.reasons : []
        if let previous = previous {
            for key in ["media_errors","num_err_log_entries","ata_5","ata_197","ata_198","ata_199"] { if let before = previous.value(key), let after = d.value(key), after - before >= settings.errorLimit { events.append("\(key) increased by \(after - before)") } }
        }
        guard !events.isEmpty else { return }
        let signature = events.joined(separator: "|")
        var proposedGate = gate
        guard proposedGate.permit(id: d.id, signature: signature, now: Date(), cooldown: settings.cooldown) else { return }
        let content = UNMutableNotificationContent(); content.title = "DiskSenseInfo · " + d.model; content.body = events.joined(separator: "\n"); content.sound = .default
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)); gate = proposedGate; try JSONEncoder().encode(gate).write(to: directory.appendingPathComponent("alerts.json"), options: .atomic) } catch { self.error = "Notification: \(error.localizedDescription)" }
    }
    func enableNotifications() {
        Task { do { let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound]); settings.notifications = allowed; notificationStatus = allowed ? tr("通知已啟用", "Notifications enabled") : tr("請在系統設定允許通知", "Allow notifications in System Settings") } catch { self.error = error.localizedDescription } }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled; if enabled && !loginEnabled { error = tr("請在系統設定允許登入項目。", "Approve the login item in System Settings.") } } catch { self.error = error.localizedDescription }
    }
    func runSelfTest(_ d: Disk, type: String) {
        guard !busy, DeviceOperationPolicy.allowsSelfTest(d), DeviceOperationPolicy.validTest(type) else { error = tr("此裝置／後端不支援此操作。", "Device/backend does not support this operation."); return }
        busy = true
        job = Task {
            do {
                let available = try await DiskDiscovery.discover()
                guard available.contains(where: { $0.id == d.id || $0.id == d.discoveryID }) else { throw NSError(domain: "DiskSenseInfo", code: 9, userInfo: [NSLocalizedDescriptionKey: "Drive identity changed or drive disconnected; operation cancelled."]) }
                let current = available.first { $0.id == d.id || $0.id == d.discoveryID }!
                let result = try await CommandRunner.run(executable,["-j", "-t", type, "/dev/" + current.device], timeout: 20)
                let parsed = try SmartParser.parse(result.data)
                error = tr("操作結果：", "Operation result: ") + (parsed.messages.isEmpty ? String(data: result.data, encoding: .utf8) ?? "No response" : parsed.messages.joined(separator: "\n"))
            } catch { self.error = error.localizedDescription }
            busy = false; refresh(force: true)
        }
    }
    func clearHistory() { samples = []; do { try store.save([], days: settings.retentionDays) } catch { self.error = error.localizedDescription } }
    func export(_ format: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "DiskSenseInfo-report." + format; panel.title = tr("匯出診斷報告", "Export diagnostic report")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Exporter.report(disks, samples: samples, redact: settings.hideIdentifiers, format: format).write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
    }
}
