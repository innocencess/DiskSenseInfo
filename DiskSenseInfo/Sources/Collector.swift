import Foundation
import IOKit

struct CommandResult { var data: Data; var error: String; var status: Int32 }
struct CommandRunner {
    static func run(_ path: String, _ args: [String], timeout: Double = 15) async throws -> CommandResult {
        try Task.checkCancellation()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DiskSenseInfo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("out"); let err = dir.appendingPathComponent("err")
        FileManager.default.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600]); FileManager.default.createFile(atPath: err.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let oh = try FileHandle(forWritingTo: out); let eh = try FileHandle(forWritingTo: err)
        defer { try? oh.close(); try? eh.close() }
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args; p.standardOutput = oh; p.standardError = eh
        var env = ProcessInfo.processInfo.environment; env["LC_ALL"] = "C"; p.environment = env
        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while p.isRunning {
                try Task.checkCancellation()
                if Date() > deadline { throw NSError(domain: "DiskSenseInfo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Command timed out: \(URL(fileURLWithPath: path).lastPathComponent)"]) }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } catch { p.terminate(); for _ in 0..<10 { if !p.isRunning { break }; try? await Task.sleep(nanoseconds: 10_000_000) }; if p.isRunning { kill(p.processIdentifier, SIGKILL) }; throw error }
        return CommandResult(data: try Data(contentsOf: out), error: String(data: (try? Data(contentsOf: err)) ?? Data(), encoding: .utf8) ?? "", status: p.terminationStatus)
    }
    static func plist(_ args: [String]) async throws -> [String: Any] {
        let result = try await run("/usr/sbin/diskutil", args)
        guard result.status == 0, let d = try PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any] else { throw NSError(domain: "DiskSenseInfo", code: 3, userInfo: [NSLocalizedDescriptionKey: "diskutil failed: \(result.error)"]) }; return d
    }
}
struct RegistryInfo {
    var serial: String?; var vendor: String?; var firmware: String?; var model: String?; var speed: String?; var path: String?; var usbLocation: UInt64?; var usbVendor: UInt64?; var usbProduct: UInt64?
    static func read(_ bsd: String) -> RegistryInfo {
        var result = RegistryInfo()
        guard let match = IOBSDNameMatching(kIOMainPortDefault, 0, bsd) else { return result }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, match)
        for _ in 0..<20 {
            guard entry != 0 else { break }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS, let d = props?.takeRetainedValue() as? [String: Any] {
                if result.usbLocation == nil, let vendor = number(d["idVendor"]), let product = number(d["idProduct"]), let location = number(d["locationID"]) {
                    result.usbVendor = UInt64(vendor); result.usbProduct = UInt64(product); result.usbLocation = UInt64(location)
                }
                let characteristics = d["Device Characteristics"] as? [String: Any] ?? [:]
                result.serial = result.serial ?? (characteristics["Serial Number"] as? String) ?? (d["Serial Number"] as? String)
                result.vendor = result.vendor ?? (characteristics["Vendor Name"] as? String)
                result.model = result.model ?? (characteristics["Product Name"] as? String)
                result.firmware = result.firmware ?? (characteristics["Product Revision Level"] as? String)
                if let p = d["Protocol Characteristics"] as? [String: Any] { result.speed = result.speed ?? textValue(p["Physical Interconnect Speed"]) }
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry); entry = status == KERN_SUCCESS ? parent : 0
        }
        if entry != 0 { IOObjectRelease(entry) }
        return result
    }
}
struct DiskDiscovery {
    static func ownedVolumes(device: String, nodes: [[String: Any]]) -> [[String: Any]] {
        var volumes: [[String: Any]] = []
        for node in nodes {
            if node["DeviceIdentifier"] as? String == device { volumes += node["Partitions"] as? [[String: Any]] ?? [] }
            let stores = node["APFSPhysicalStores"] as? [[String: Any]] ?? []
            if stores.contains(where: { ($0["DeviceIdentifier"] as? String)?.hasPrefix(device + "s") == true }) {
                volumes += (node["APFSVolumes"] as? [[String: Any]] ?? []).map { v in var v = v; v["SharedAPFS"] = true; return v }
            }
        }
        var seen: Set<String> = []
        return volumes.filter { guard let id = $0["DeviceIdentifier"] as? String else { return false }; return seen.insert(id).inserted }
    }
    static func discover() async throws -> [Disk] {
        let physical = try await CommandRunner.plist(["list", "-plist", "physical"])
        let all = try await CommandRunner.plist(["list", "-plist"])
        let nodes = all["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        var profiles: [NVMeProfile] = []
        var profileError: String?
        do {
            let result = try await CommandRunner.run("/usr/sbin/system_profiler", ["SPNVMeDataType", "-json"], timeout: 15)
            guard result.status == 0 else { throw NSError(domain: "DiskSenseInfo", code: 10, userInfo: [NSLocalizedDescriptionKey: result.error]) }
            profiles = try NVMeProfile.parse(result.data)
        } catch is CancellationError { throw CancellationError() } catch { profileError = "NVMe link information unavailable: " + error.localizedDescription }
        var usbProfiles: [USBProfile] = []
        for dataType in ["SPUSBHostDataType", "SPUSBDataType"] {
            do {
                let result = try await CommandRunner.run("/usr/sbin/system_profiler", [dataType, "-json"], timeout: 15)
                usbProfiles = try USBProfile.parse(result.data)
                if !usbProfiles.isEmpty { break }
            } catch is CancellationError { throw CancellationError() } catch { }
        }
        var disks: [Disk] = []
        for dev in physical["WholeDisks"] as? [String] ?? [] {
            try Task.checkCancellation()
            guard let info = try? await CommandRunner.plist(["info", "-plist", dev]) else { continue }
            guard info["WholeDisk"] as? Bool == true else { continue }
            let registry = RegistryInfo.read(dev)
            let model = info["MediaName"] as? String ?? registry.model ?? dev
            let volumeNodes = ownedVolumes(device: dev, nodes: nodes)
            let uuidKeys = volumeNodes.compactMap { ($0["DiskUUID"] as? String) ?? ($0["VolumeUUID"] as? String) }.sorted()
            let profile = profiles.first { $0.device == dev && $0.model == model && (registry.serial == nil || registry.serial == $0.serial) }
            let serial = (registry.serial ?? profile?.serial)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let reliable = (serial?.isEmpty == false) || !uuidKeys.isEmpty
            let identity = serial?.isEmpty == false ? "serial:" + model + ":" + serial! : !uuidKeys.isEmpty ? "uuid:" + uuidKeys.joined(separator: ":") : "session:" + model + ":" + (info["DeviceTreePath"] as? String ?? dev)
            let bus = info["BusProtocol"] as? String ?? "Unknown"
            let ssd = info["SolidState"] as? Bool
            let nvme = bus == "Apple Fabric" || (info["DeviceTreePath"] as? String ?? "").contains("NVMe")
            var d = Disk(id: digest(identity), device: dev, model: model, serial: serial, firmware: registry.firmware, manufacturer: registry.vendor, capacity: number(info["TotalSize"] ?? info["Size"]) ?? 0, bus: bus, kind: nvme ? "NVMe SSD" : ssd == true ? "SSD" : ssd == false ? "HDD" : "Unknown", internalDisk: info["Internal"] as? Bool ?? false, smartStatus: info["SMARTStatus"] as? String ?? "Not Supported", identityReliable: reliable)
            d.discoveryID = d.id; d.speed = profile?.linkSpeed ?? registry.speed; d.raw = prettyJSON(["diskutil": info]); d.diagnostics = ["Source: diskutil + IOKit; physical media only"]
            if bus == "USB", let usb = USBProfile.match(usbProfiles, location: registry.usbLocation, vendor: registry.usbVendor, product: registry.usbProduct) {
                d.speed = usb.speed
                d.diagnostics.append("USB link speed source: system_profiler; matched device VID/PID/location, not hub or SSD PCIe link. Reported link rate is not measured disk throughput.")
            }
            if let profileError = profileError { d.diagnostics.append(profileError) }
            if profile?.linkSpeed != nil { d.diagnostics.append("PCIe link rate/width source: system_profiler SPNVMeDataType; not storage benchmark throughput or end-to-end enclosure speed.") }
            if !reliable { d.diagnostics.append("No serial or persistent volume UUID; identity is session-only. History is disabled.") }
            for v in volumeNodes {
                guard let id = v["DeviceIdentifier"] as? String else { continue }
                let vi = (try? await CommandRunner.plist(["info", "-plist", id])) ?? v
                let mount = vi["MountPoint"] as? String ?? v["MountPoint"] as? String ?? ""
                let isFilesystemVolume = vi["FilesystemType"] != nil || !mount.isEmpty
                var free = isFilesystemVolume ? number(vi["APFSContainerFree"] ?? vi["VolumeFreeSpace"] ?? vi["FreeSpace"]) : nil
                if !mount.isEmpty, let attrs = try? FileManager.default.attributesOfFileSystem(forPath: mount) { free = number(attrs[.systemFreeSize]) ?? free }
                let total = number(vi["APFSContainerSize"] ?? vi["VolumeTotalSpace"] ?? vi["TotalSize"] ?? v["Size"]) ?? 0
                let used = number(v["CapacityInUse"] ?? vi["VolumeUsedSpace"]) ?? (free.map { max(0, total - $0) })
                d.volumes.append(Volume(id: id, name: v["VolumeName"] as? String ?? id, mount: mount, filesystem: vi["FilesystemName"] as? String ?? vi["Content"] as? String ?? "Unknown", total: total, used: used, free: free, shared: v["SharedAPFS"] as? Bool ?? false))
            }
            // Undocumented diskutil device-specific SMART fields are deliberately preserved only as raw data.
            disks.append(d)
        }
        return disks
    }
}
struct DiskCollector {
    var smartctlPath: String
    var databasePath: String?
    func collect(_ disk: Disk, settings: MonitorSettings, automatic: Bool) async -> Disk {
        var d = disk; d.sampledAt = Date()
        do {
            var args = ["-x", "-j"]
            if let db = databasePath { args += ["-B", db] }
            if automatic && !d.internalDisk { args += ["-n", "standby,3"] }
            args.append("/dev/" + d.device)
            let result = try await CommandRunner.run(smartctlPath, args, timeout: 20)
            let parsed = try SmartParser.parse(result.data)
            d.smartRaw = String(data: result.data, encoding: .utf8) ?? "{}"
            if d.bus != "USB", let reported = parsed.serial, let discovered = d.serial, reported != discovered { d.speed = nil; d.diagnostics.append("Discovery and SMART serials differ; discarded link information to avoid attributing a replaced device incorrectly.") }
            d.model = parsed.model ?? d.model; d.serial = parsed.serial ?? d.serial; d.firmware = parsed.firmware ?? d.firmware
            d.controllerVendor = parsed.controllerVendor; d.protocolVersion = parsed.protocolVersion
            d.metrics = parsed.metrics; d.features = parsed.features; if d.bus != "USB" { d.speed = parsed.speed ?? d.speed }; d.rotation = parsed.rotation
            d.diagnostics += parsed.messages
            if !result.error.isEmpty { d.diagnostics.append(result.error) }
            if parsed.protocolName == "NVMe" { d.kind = "NVMe SSD" } else if parsed.rotation == "SSD" { d.kind = "SSD" } else if parsed.rotation != nil { d.kind = "HDD" }
            if let serial = parsed.serial, !serial.isEmpty { d.id = digest("serial:" + d.model + ":" + serial); d.identityReliable = true }
            if parsed.passed == nil && d.metrics.isEmpty { d.diagnostics.append("SMART unavailable. The bridge/driver may not expose passthrough, permissions may be insufficient, or the drive may be asleep. No health percentage is inferred.") }
            // diskutil's overall status is a fallback, never its undocumented vendor-specific counters.
            let passed = parsed.passed ?? (d.smartStatus == "Verified" ? true : d.smartStatus == "Failing" ? false : nil)
            d.smartAccess = SMARTAccessPolicy.classify(bus: d.bus, hasData: !d.metrics.isEmpty || parsed.passed != nil, messages: parsed.messages + [result.error])
            HealthEngine.evaluate(&d, settings: settings, passed: passed)
            if d.access == .usbUnavailable && d.health == .unknown { d.reasons = ["USB SMART unavailable through current macOS access path"] }
        } catch {
            d.metrics = []; d.smartRaw = "{}"; d.smartAccess = .readFailed; d.health = .unknown; d.reasons = ["Current SMART read failed"]; d.diagnostics.append(error.localizedDescription)
        }
        return d
    }
}
struct HistoryStore {
    var directory: URL
    var historyURL: URL { directory.appendingPathComponent("history.json") }
    func load() throws -> [Sample] { guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }; return try JSONDecoder().decode([Sample].self, from: Data(contentsOf: historyURL)) }
    func save(_ samples: [Sample], days: Int, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let keep = samples.filter { $0.date >= now.addingTimeInterval(-Double(days) * 86400) }
        try JSONEncoder().encode(keep).write(to: historyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }
}
struct Exporter {
    static func report(_ disks: [Disk], samples: [Sample], redact: Bool, format: String) throws -> Data {
        let aliases = Dictionary(uniqueKeysWithValues: disks.enumerated().map { ($0.element.id,"Disk-\($0.offset + 1)") })
        if format == "csv" {
            func cell(_ s: String) -> String { let safe = ["=","+","-","@"].contains(String(s.prefix(1))) ? "'" + s : s; return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            var lines = ["disk,date,health,metric,raw,unit"]
            for s in samples where aliases[s.diskID] != nil { for m in s.metrics { lines.append([redact ? aliases[s.diskID]! : s.diskID, ISO8601DateFormatter().string(from: s.date),s.health.rawValue,m.name,m.raw,m.unit].map(cell).joined(separator: ",")) } }
            return Data(lines.joined(separator: "\n").utf8)
        }
        var sanitized = disks
        if redact {
            for i in sanitized.indices { sanitized[i].id = aliases[sanitized[i].id]!; sanitized[i].discoveryID = nil; sanitized[i].serial = nil; sanitized[i].device = "redacted"; sanitized[i].raw = "{\"redacted\":true}"; sanitized[i].smartRaw = "{\"redacted\":true}"; sanitized[i].diagnostics = ["Raw payload and diagnostic text omitted for privacy"]; for j in sanitized[i].volumes.indices { sanitized[i].volumes[j].id = "Volume-\(j + 1)"; sanitized[i].volumes[j].name = "Volume-\(j + 1)"; sanitized[i].volumes[j].mount = "redacted" } }
        }
        let history = samples.filter { aliases[$0.diskID] != nil }.map { s in var s = s; if redact { s.diskID = aliases[s.diskID]! }; return s }
        if format == "txt" { return Data(sanitized.map { d in "\(d.model) • \(d.health.rawValue)\n\(d.reasons.joined(separator: "\n"))\n" + d.metrics.map { "\($0.name): \($0.formatted(hex: false))" }.joined(separator: "\n") + "\nDiagnostics:\n" + d.diagnostics.joined(separator: "\n") }.joined(separator: "\n\n").utf8) }
        struct Report: Codable { var generated: Date; var redacted: Bool; var disks: [Disk]; var history: [Sample] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Report(generated: Date(), redacted: redact, disks: sanitized, history: history))
    }
}
