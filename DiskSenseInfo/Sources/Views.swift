import SwiftUI
import Charts

// Disambiguate the property wrapper from the SDK 27 State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Health {
    var color: Color { switch self { case .normal: return .green; case .caution: return .orange; case .danger: return .red; case .unknown: return .secondary } }
    var symbol: String { switch self { case .normal: return "checkmark.shield.fill"; case .caution: return "exclamationmark.triangle.fill"; case .danger: return "xmark.octagon.fill"; case .unknown: return "questionmark.circle" } }
}
func bytes(_ n: Double?) -> String { guard let n = n, n.isFinite else { return "—" }; return ByteCountFormatter.string(fromByteCount: Int64(min(n, Double(Int64.max - 1024))), countStyle: .decimal) }
struct Panel<Content: View>: View {
    var title: String; @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline); content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary)) }
}
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<Int> var tab = 0
    init(initialTab: Int = 0) { _tab = ViewState(wrappedValue: initialTab) }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Image(nsImage: NSImage(contentsOf: model.resourcesURL.appendingPathComponent("AppIcon.icns")) ?? NSImage()).resizable().frame(width: 38, height: 38); VStack(alignment: .leading) { Text("DiskSenseInfo").font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.8); Text(model.tr("磁碟健康監控", "Drive health monitor")).font(.caption).foregroundStyle(.secondary) } }.padding(20)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.disks) { d in
                            Button { model.selectedID = d.id } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: d.internalDisk ? "internaldrive" : "externaldrive").font(.title2).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(d.model).font(.headline).lineLimit(2).foregroundStyle(.primary)
                                        Text("\(d.kind) · \(bytes(d.capacity))").font(.caption).foregroundStyle(.secondary)
                                        Label(d.online ? model.healthName(d.health) : model.tr("離線", "Offline"), systemImage: d.online ? d.health.symbol : "eject").font(.caption).foregroundStyle(d.health.color)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(d.id == model.selectedID ? Color.teal.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(d.id == model.selectedID ? model.tr("已選取", "Selected") : "")
                        }
                    }.padding(.horizontal, 12)
                }
                .onMoveCommand { direction in
                    guard let index = model.disks.firstIndex(where: { $0.id == model.selectedID }) else { return }
                    if direction == .down && index + 1 < model.disks.count { model.selectedID = model.disks[index + 1].id }
                    if direction == .up && index > 0 { model.selectedID = model.disks[index - 1].id }
                }
                Link(destination: URL(string: "https://buymeacoffee.com/kkrlife")!) {
                    HStack(spacing: 9) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text(model.tr("請我喝杯咖啡", "Buy me a coffee")).font(.callout.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.yellow.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .help(model.tr("支持開發者 · 在瀏覽器開啟 Buy Me a Coffee", "Support the developer · Open Buy Me a Coffee in your browser"))
                .accessibilityLabel(model.tr("斗內：請我喝杯咖啡", "Donate: Buy me a coffee"))
                .padding(.horizontal, 14).padding(.top, 8)
                Text(model.tr("僅讀取資訊 · 資料保存在本機", "Read-only · Stored locally")).font(.caption2).foregroundStyle(.secondary).padding(16)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 270)
        } detail: {
            if let d = model.selected {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text(d.model).font(.largeTitle.bold()); Text("\(d.bus) · \(d.kind) · \(d.device)").foregroundStyle(.secondary) }
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                        Label(d.online ? model.healthName(d.health) : model.tr("離線", "Offline"), systemImage: d.health.symbol).font(.headline).foregroundStyle(d.health.color).padding(12).background(d.health.color.opacity(0.1), in: Capsule())
                    }
                    HStack {
                        Picker("", selection: $tab) { Text(model.tr("總覽", "Overview")).tag(0); Text("SMART").tag(1); Text(model.tr("歷史", "History")).tag(2); Text(model.tr("診斷紀錄", "Diagnostics")).tag(3) }.pickerStyle(.segmented).frame(maxWidth: 480)
                        Spacer()
                        if let date = d.sampledAt { Text(date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    Group { switch tab { case 1: SmartView(disk: d); case 2: HistoryView(disk: d); case 3: DiagnosticsView(disk: d); default: OverviewView(disk: d) } }.id(d.id)
                }.padding(28).background(Color(nsColor: .windowBackgroundColor))
            } else {
                VStack(spacing: 18) { Image(systemName: "internaldrive").font(.system(size: 52)).foregroundStyle(.teal); Text(model.tr("探索實體磁碟", "Discovering physical drives")).font(.title); if model.busy { ProgressView() } else { Text(model.tr("未找到可讀取的實體磁碟。", "No readable physical disks found.")) } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .onChange(of: model.selectedID) { id in model.settings.selectedID = id }
        .toolbar {
            ToolbarItem { Button { model.refresh(force: true) } label: { Label(model.tr("更新", "Refresh"), systemImage: "arrow.clockwise") }.disabled(model.busy).keyboardShortcut("r", modifiers: .command).help(model.tr("手動讀取可能喚醒外接硬碟", "A manual read may wake external drives")) }
            ToolbarItem { Menu { Button("JSON") { model.export("json") }; Button("CSV") { model.export("csv") }; Button(model.tr("文字報告", "Text report")) { model.export("txt") } } label: { Label(model.tr("匯出", "Export"), systemImage: "square.and.arrow.up") } }
        }
        .alert(model.tr("DiskSenseInfo 訊息", "DiskSenseInfo message"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(model.tr("確定", "OK")) { model.error = nil } } message: { Text(model.error ?? "") }
    }
}
struct SMARTAccessNotice: View {
    @EnvironmentObject var model: AppModel; var disk: Disk
    var title: String {
        switch disk.access {
        case .usbUnavailable: return model.tr("目前 macOS 讀取方式無法取得 USB 裝置的 SMART", "SMART unavailable through the current macOS USB access path")
        case .permissionDenied: return model.tr("SMART 存取遭權限限制", "SMART access denied by permissions")
        case .readFailed: return model.tr("本次 SMART 讀取失敗", "This SMART read failed")
        case .notRead: return model.tr("尚未取得 SMART 資料", "SMART has not been read yet")
        case .offline: return model.tr("磁碟已離線", "Drive is offline")
        case .unavailable: return model.tr("目前未能取得 SMART 資料", "SMART data is currently unavailable")
        case .available: return ""
        }
    }
    var detail: String {
        switch disk.access {
        case .usbUnavailable: return model.tr("系統已偵測到磁碟，但目前外接盒、macOS 驅動與採集後端之間的診斷指令轉送路徑不可用，因此溫度、耗損、通電與讀寫統計無法取得。這不表示 SSD 本身沒有 SMART 或已故障；同一外接盒在 Windows 可能可讀。USB 速度與容量可獨立顯示。", "The system detects the disk, but the diagnostic command path through the enclosure, macOS driver and collection backend is unavailable. Temperature, wear and usage counters cannot be read. This does not mean the SSD lacks SMART or has failed; the same enclosure may work on Windows. USB speed and capacity are independent.")
        case .permissionDenied: return model.tr("系統拒絕診斷資料存取，不能據此判斷裝置是否支援 SMART。請查看診斷紀錄中的原始錯誤。", "The system denied diagnostic access; device SMART capability cannot be inferred. See Diagnostics for the original error.")
        case .notRead: return model.tr("可能因省電策略尚未查詢。按工具列更新即可嘗試讀取；手動查詢可能喚醒磁碟。", "Collection may be deferred by power-saving settings. Use Refresh to attempt a read; a manual query may wake the disk.")
        case .offline: return model.tr("以下為最後取得的資料。重新連接後會重新探索磁碟，離線狀態不代表 SMART 不支援。", "Values below are historical. Reconnection triggers rediscovery; offline status does not mean SMART is unsupported.")
        default: return model.tr("目前無法判斷健康狀態，請查看診斷紀錄了解逾時、裝置、驅動或連線原因。缺少資料不會被判定為磁碟故障。", "Health cannot currently be assessed. See Diagnostics for timeout, device, driver or connection errors. Missing data is not treated as drive failure.")
        }
    }
    var body: some View {
        if disk.access != .available {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "info.circle.fill").font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
struct OverviewView: View {
    @EnvironmentObject var model: AppModel; var disk: Disk; @ViewState<Bool> var showUnmounted = false
    func stat(_ title: String, _ value: String, _ icon: String) -> some View { VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14)) }
    func val(_ key: String, _ unit: String) -> String { disk.value(key).map { String(format: "%.0f", $0) + unit } ?? model.tr(disk.access == .available ? "裝置未回報" : "SMART 未取得", disk.access == .available ? "Not reported" : "SMART unavailable") }
    func row(_ title: String, _ value: String?) -> some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value?.isEmpty == false ? value! : model.tr("裝置未回報", "Not reported by device")).textSelection(.enabled).multilineTextAlignment(.trailing) }.font(.callout) }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SMARTAccessNotice(disk: disk)
                HStack(spacing: 12) { stat(model.tr("溫度", "Temperature"), val("temperature", "°C"), "thermometer.medium"); stat(model.tr("耗損比例", "Endurance used"), val("percentage_used", "%"), "gauge.medium"); stat(model.tr("通電時間", "Power on"), val("power_on_hours", " h"), "clock"); stat(model.tr("容量", "Capacity"), bytes(disk.capacity), "externaldrive") }
                Panel(title: model.tr("健康判定依據", "Health assessment")) {
                    ForEach(disk.reasons, id: \.self) { reason in Label(model.message(reason), systemImage: disk.health.symbol).foregroundStyle(disk.health.color).textSelection(.enabled) }
                    if !disk.online { Text(model.tr("磁碟已離線，以下是最後取得的資料。", "Drive is offline; values are from its last sample.")).font(.caption) }
                    Text(model.tr("SMART 僅反映裝置可提供的診斷資料，缺少欄位不會推算為完整健康。", "SMART reflects available device diagnostics; missing fields are never inferred as full health.")).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 18) {
                    Panel(title: model.tr("裝置資訊", "Device information")) {
                        row(model.tr("序號", "Serial"), model.settings.hideIdentifiers ? "••••••••" : disk.serial)
                        row(model.tr("韌體", "Firmware"), disk.firmware); row(model.tr(disk.bus == "USB" ? "外接盒回報廠商" : disk.reportedManufacturer == nil && disk.controllerVendor != nil ? "廠商（PCI 識別）" : "製造商", disk.bus == "USB" ? "Enclosure-reported vendor" : disk.reportedManufacturer == nil && disk.controllerVendor != nil ? "Vendor (PCI identity)" : "Manufacturer"), disk.reportedManufacturer ?? disk.controllerVendor); row(model.tr("協定版本", "Protocol version"), disk.protocolVersion); row(model.tr(disk.bus == "USB" ? "USB 速率（系統回報）" : "連線速率／通道", disk.bus == "USB" ? "USB rate (system-reported)" : "Link rate / lanes"), disk.bus == "Apple Fabric" ? model.tr("Apple Fabric 整合介面；無一般 PCIe 速率／通道資料", "Apple Fabric integrated interface; no conventional PCIe rate / lane data") : disk.speed); row(model.tr("轉速", "Rotation rate"), disk.kind.contains("SSD") ? model.tr("不適用（SSD 無旋轉機構）", "Not applicable (SSD)") : disk.rotation); row("SMART", disk.access == .available ? model.tr("已取得", "Available") : disk.access == .notRead ? model.tr("尚未查詢", "Not read yet") : disk.access == .offline ? model.tr("離線", "Offline") : model.tr("目前讀取方式無法取得", "Unavailable through current access path"))
                    }
                    Panel(title: model.tr("使用統計", "Usage statistics")) { row(model.tr("總讀取量", "Host reads"), disk.value("read_bytes").map { bytes($0) } ?? val("read_bytes", "")); row(model.tr("總寫入量", "Host writes"), disk.value("write_bytes").map { bytes($0) } ?? val("write_bytes", "")); row(model.tr("通電次數", "Power cycles"), val("power_cycles", "")); row(model.tr("非正常關機", "Unsafe shutdowns"), val("unsafe_shutdowns", "")); row(model.tr("媒體錯誤", "Media errors"), val("media_errors", "")) }
                }
                Panel(title: model.tr("分割區與卷宗", "Partitions & volumes")) {
                    Toggle(model.tr("顯示未掛載卷宗與分割區", "Show unmounted volumes and partitions"), isOn: $showUnmounted).font(.caption)
                    ForEach(disk.volumes.filter { showUnmounted || !$0.mount.isEmpty }) { v in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(model.settings.hideIdentifiers ? v.id : v.name).font(.headline); Spacer(); Text(v.filesystem).font(.caption).foregroundStyle(.secondary) }
                            if let free = v.free { Text(model.tr("可用 ", "Free ") + bytes(free) + " / " + bytes(v.total)).font(.caption); ProgressView(value: min(1,max(0,1 - free / max(1,v.total)))).tint(.teal) }
                            if v.shared { Text(model.tr("APFS 共享容器空間；不可將各卷宗容量相加。", "APFS shared container space; do not sum volume capacities.")).font(.caption2).foregroundStyle(.secondary) }
                            if !model.settings.hideIdentifiers && !v.mount.isEmpty { Text(v.mount).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.padding(.vertical, 5)
                    }
                }
            }.padding(.bottom, 20)
        }
    }
}
struct SmartView: View {
    @EnvironmentObject var model: AppModel; var disk: Disk; @ViewState<Bool> var hex = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(model.tr("裝置原始診斷屬性", "Device diagnostic attributes")).font(.headline); Spacer(); Toggle(model.tr("十六進位原始值", "Hex raw values"), isOn: $hex).toggleStyle(.switch).controlSize(.small) }
            if disk.metrics.isEmpty { SMARTAccessNotice(disk: disk) }
            Table(disk.metrics) {
                TableColumn("ID") { Text($0.id).font(.caption.monospaced()).help($0.id) }.width(min: 90, ideal: 140)
                TableColumn(model.tr("屬性", "Attribute"), value: \.name).width(min: 180, ideal: 240)
                TableColumn(model.tr("目前", "Current")) { Text($0.current.map(String.init) ?? "—") }.width(55)
                TableColumn(model.tr("最差", "Worst")) { Text($0.worst.map(String.init) ?? "—") }.width(55)
                TableColumn(model.tr("門檻", "Threshold")) { Text($0.threshold.map(String.init) ?? "—") }.width(65)
                TableColumn(model.tr("原始值", "Raw value")) { Text($0.formatted(hex: hex)).font(.system(.body, design: .monospaced)).textSelection(.enabled) }.width(min: 110, ideal: 180)
                TableColumn(model.tr("狀態", "Status")) { Text($0.failed ? model.tr("曾失敗", "Failed") : "—").foregroundStyle($0.failed ? .red : .secondary) }.width(70)
            }
            Text(model.tr("十六進位僅適用於可完整表示的無單位整數；超大計數保留原始十進位字串。", "Hex applies to unitless UInt64 values; larger counters retain their original decimal strings.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct HistoryView: View {
    @EnvironmentObject var model: AppModel; var disk: Disk
    @ViewState<Int> var hours = 24; @ViewState<String> var metric = "temperature"
    var filtered: [Sample] { model.samples.filter { $0.diskID == disk.id && $0.date >= Date().addingTimeInterval(-Double(hours) * 3600) }.sorted { $0.date < $1.date } }
    func value(_ s: Sample) -> Double? { switch metric { case "percentage_used": return s.wear; case "write_bytes": return s.writeBytes.map { $0 / 1_000_000_000_000 }; case "read_bytes": return s.readBytes.map { $0 / 1_000_000_000_000 }; case "media_errors": return s.errors; default: return s.temperature } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Picker(model.tr("期間", "Range"), selection: $hours) { Text(model.tr("1 小時", "1 hour")).tag(1); Text(model.tr("1 天", "1 day")).tag(24); Text(model.tr("1 週", "1 week")).tag(168); Text(model.tr("1 月", "1 month")).tag(720) }.pickerStyle(.segmented)
                Picker(model.tr("指標", "Metric"), selection: $metric) { Text(model.tr("溫度 °C", "Temperature °C")).tag("temperature"); Text(model.tr("耗損 %", "Wear %")).tag("percentage_used"); Text(model.tr("讀取 TB", "Reads TB")).tag("read_bytes"); Text(model.tr("寫入 TB", "Writes TB")).tag("write_bytes"); Text(model.tr("媒體錯誤", "Media errors")).tag("media_errors") }.frame(width: 220)
            }
            Panel(title: model.tr("趨勢紀錄", "History trend")) {
                if filtered.contains(where: { value($0) != nil }) {
                    Chart(filtered) { s in if let v = value(s) { LineMark(x: .value("Time", s.date), y: .value("Value", v)).foregroundStyle(.teal); PointMark(x: .value("Time", s.date), y: .value("Value", v)).foregroundStyle(.teal) } }.frame(height: 300).chartXScale(domain: Date().addingTimeInterval(-Double(hours) * 3600)...Date())
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day().hour(), anchor: .top) } }
                    .chartXAxisLabel(model.tr("採樣時間", "Sample time")).chartYAxisLabel(metric)
                } else { Text(model.tr("此期間尚無此項資料；不會產生模擬曲線。", "No samples for this metric in this period.")).foregroundStyle(.secondary).frame(height: 240) }
            }
            Text("\(filtered.count) " + model.tr("筆採樣 · 保存在此 Mac", "samples · Stored on this Mac")).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel; var disk: Disk; @ViewState<Bool> var showRaw = false; @ViewState<Bool> var confirmTest = false; @ViewState<String> var testType = "short"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: model.tr("採集紀錄與限制", "Collection diagnostics & limitations")) { ForEach(Array(disk.diagnostics.enumerated()), id: \.offset) { _, line in Text(line).textSelection(.enabled).font(.callout) } }
                Panel(title: model.tr("裝置能力", "Device capabilities")) { if disk.features.isEmpty { Text(model.tr("裝置未回報", "Not reported by device")) }; ForEach(disk.features, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) } }
                Panel(title: model.tr("錯誤／自我測試紀錄", "Error / self-test logs")) {
                    Text(logs).font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.tr("AAM/APM 修改未提供。NVMe 後端僅支援讀取；ATA 自我測試需裝置明確支援。", "AAM/APM controls are unavailable. The NVMe backend is read-only; ATA self-tests require explicit device support.")).font(.caption).foregroundStyle(.secondary)
                }
                if DeviceOperationPolicy.allowsSelfTest(disk) {
                    Panel(title: model.tr("ATA 自我測試", "ATA self-test")) {
                        Text(model.tr("測試可能降低磁碟效能並喚醒磁碟。每次執行都需要確認。", "Tests may reduce drive performance and wake the drive. Confirmation is required for each operation.")).font(.caption)
                        HStack {
                            Button(model.tr("短測試…", "Short test…")) { testType = "short"; confirmTest = true }
                            Button(model.tr("長測試…", "Extended test…")) { testType = "long"; confirmTest = true }
                            Button(model.tr("中止測試…", "Abort test…")) { testType = "abort"; confirmTest = true }
                        }.disabled(model.busy || !disk.online)
                    }
                }
                Toggle(model.tr("顯示完整原始資料（可能包含序號與卷宗名稱）", "Show full raw payload (may contain identifiers)"), isOn: $showRaw)
                if showRaw { Text(disk.smartRaw + "\n" + disk.raw).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(.bottom, 20)
        }.confirmationDialog(model.tr("確認送出 ATA 自我測試指令？可能影響磁碟效能。", "Send ATA self-test command? Drive performance may be affected."), isPresented: $confirmTest) {
            Button(model.tr("確認執行", "Confirm operation")) { model.runSelfTest(disk, type: testType) }
        }
    }
    var logs: String { guard let data = disk.smartRaw.data(using: .utf8), let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return model.tr("無法取得", "Unavailable") }; let keys = ["nvme_error_information_log", "nvme_self_test_log", "ata_smart_error_log", "ata_smart_self_test_log", "ata_smart_selective_self_test_log"]; var result: [String: Any] = [:]; for key in keys { if let v = d[key] { result[key] = v } }; return result.isEmpty ? model.tr("裝置或驅動程式未提供紀錄，詳見採集紀錄。", "No logs returned by device/driver. See collection diagnostics.") : prettyJSON(result) }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel; @ViewState<Bool> var confirmClear = false
    var body: some View {
        Form {
            Section(model.tr("一般", "General")) {
                Picker(model.tr("語言", "Language"), selection: $model.settings.language) { Text("繁體中文").tag("zh"); Text("English").tag("en") }
                Toggle(model.tr("登入時啟動", "Launch at login"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Toggle(model.tr("選單列顯示溫度", "Show temperature in menu bar"), isOn: $model.settings.menuTemperature)
                Toggle(model.tr("隱藏識別資料／匯出時去識別化", "Hide identifiers / redact exports"), isOn: $model.settings.hideIdentifiers)
            }
            Section(model.tr("採集與省電", "Collection & power saving")) {
                Picker(model.tr("內建磁碟更新", "Internal interval"), selection: $model.settings.interval) { Text("1 min").tag(60.0); Text("5 min").tag(300.0); Text("15 min").tag(900.0); Text("1 h").tag(3600.0) }
                Picker(model.tr("外接磁碟更新", "External interval"), selection: $model.settings.externalInterval) { Text("5 min").tag(300.0); Text("30 min").tag(1800.0); Text("1 h").tag(3600.0) }
                Toggle(model.tr("略過外接 HDD／未知類型的自動 SMART 輪詢", "Skip automatic SMART polling for external HDD / unknown type"), isOn: $model.settings.skipExternalHDD)
                Text(model.tr("自動查詢採用 standby 保護；橋接器可能不支援。手動更新可能喚醒磁碟。", "Automatic reads request standby protection; bridges may not support it. Manual refresh may wake drives.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(model.tr("提醒", "Alerts")) {
                Toggle(model.tr("健康與溫度通知", "Health & temperature notifications"), isOn: Binding(get: { model.settings.notifications }, set: { if $0 { model.enableNotifications() } else { model.settings.notifications = false } }))
                if !model.notificationStatus.isEmpty { Text(model.notificationStatus).font(.caption) }
                Stepper(model.tr("溫度門檻", "Temperature threshold") + ": \(Int(model.settings.temperatureLimit))°C", value: $model.settings.temperatureLimit, in: 30...100, step: 1)
                Stepper(model.tr("耗損門檻", "Wear threshold") + ": \(Int(model.settings.wearLimit))%", value: $model.settings.wearLimit, in: 1...100, step: 1)
                Stepper(model.tr("錯誤計數／增量門檻", "Error count / increase threshold") + ": \(Int(model.settings.errorLimit))", value: $model.settings.errorLimit, in: 1...1000, step: 1)
                Picker(model.tr("通知冷卻時間", "Notification cooldown"), selection: $model.settings.cooldown) { Text("15 min").tag(900.0); Text("1 h").tag(3600.0); Text("24 h").tag(86400.0) }
            }
            Section(model.tr("資料", "Data")) {
                Stepper(model.tr("保留天數", "Retention days") + ": \(model.settings.retentionDays)", value: $model.settings.retentionDays, in: 1...365)
                Button(model.tr("清除歷史紀錄…", "Clear history…"), role: .destructive) { confirmClear = true }
                Text(model.tr("磁碟資料不會上傳。原始資料僅在診斷畫面明確展開後顯示。", "Disk data is never uploaded. Raw identifiers appear only when explicitly expanded in Diagnostics.")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 600, height: 740)
        .confirmationDialog(model.tr("清除所有歷史紀錄？", "Clear all history?"), isPresented: $confirmClear) { Button(model.tr("清除", "Clear"), role: .destructive) { model.clearHistory() } }
    }
}
