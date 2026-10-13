import Foundation
import CryptoKit

func textValue(_ value: Any?) -> String? {
    guard let value = value, !(value is NSNull) else { return nil }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
}
func number(_ value: Any?) -> Double? { textValue(value).flatMap(Double.init) }
func prettyJSON(_ d: Any) -> String { guard JSONSerialization.isValidJSONObject(d), let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) else { return "{}" }; return s }
func digest(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

struct Metric: Codable, Identifiable, Equatable {
    var id: String; var name: String; var raw: String; var unit: String = ""; var current: Int?; var worst: Int?; var threshold: Int?; var failed: Bool = false
    var numeric: Double? { guard let n = Double(raw), n.isFinite else { return nil }; return n }
    func formatted(hex: Bool) -> String { if hex, unit.isEmpty, let n = UInt64(raw) { return "0x" + String(n, radix: 16).uppercased() }; return raw + (unit.isEmpty ? "" : " " + unit) }
}
enum Health: String, Codable { case normal, caution, danger, unknown
    var rank: Int { switch self { case .unknown: return -1; case .normal: return 0; case .caution: return 1; case .danger: return 2 } }
}
struct Volume: Codable, Identifiable { var id: String; var name: String; var mount: String; var filesystem: String; var total: Double; var used: Double?; var free: Double?; var shared: Bool }
struct Disk: Codable, Identifiable {
    var id: String; var device: String; var model: String; var serial: String?; var firmware: String?; var manufacturer: String?; var capacity: Double; var bus: String; var kind: String; var internalDisk: Bool; var smartStatus: String; var identityReliable: Bool = true; var discoveryID: String?
    var volumes: [Volume] = []; var metrics: [Metric] = []; var health: Health = .unknown; var reasons: [String] = []; var diagnostics: [String] = []; var raw: String = "{}"; var smartRaw: String = "{}"; var sampledAt: Date?; var online: Bool = true; var features: [String] = []; var speed: String?; var rotation: String?; var controllerVendor: String?; var protocolVersion: String?; var smartAccess: SMARTAccess?
    var access: SMARTAccess { !online ? .offline : smartAccess ?? (metrics.isEmpty ? .notRead : .available) }
    var reportedManufacturer: String? { guard let name = manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }; return name }
    func value(_ id: String) -> Double? { metrics.first { $0.id == id }?.numeric }
}
struct MonitorSettings: Codable {
    var interval: Double = 300; var externalInterval: Double = 1800; var skipExternalHDD: Bool = true; var temperatureLimit: Double = 60; var wearLimit: Double = 90; var errorLimit: Double = 1; var cooldown: Double = 3600; var retentionDays: Int = 90; var notifications: Bool = false; var hideIdentifiers: Bool = true; var language: String = "zh"; var selectedID: String?; var menuTemperature: Bool = true
}
struct Sample: Codable, Identifiable {
    var id = UUID(); var diskID: String; var date: Date; var health: Health; var temperature: Double?; var wear: Double?; var readBytes: Double?; var writeBytes: Double?; var errors: Double?; var metrics: [Metric]
    init(_ d: Disk) { diskID = d.id; date = d.sampledAt ?? Date(); health = d.health; temperature = d.value("temperature"); wear = d.value("percentage_used"); readBytes = d.value("read_bytes"); writeBytes = d.value("write_bytes"); errors = d.value("media_errors"); metrics = d.metrics }
}
struct SmartResult { var metrics: [Metric] = []; var model: String?; var serial: String?; var firmware: String?; var passed: Bool?; var messages: [String] = []; var features: [String] = []; var rotation: String?; var speed: String?; var protocolName: String?; var controllerVendor: String?; var protocolVersion: String? }
struct SmartParser {
    static func parse(_ data: Data) throws -> SmartResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NSError(domain: "DiskSenseInfo", code: 1, userInfo: [NSLocalizedDescriptionKey: "SMART JSON root is not an object"]) }
        var r = SmartResult(); r.model = root["model_name"] as? String; r.serial = root["serial_number"] as? String; r.firmware = root["firmware_version"] as? String
        r.passed = (root["smart_status"] as? [String: Any])?["passed"] as? Bool
        r.protocolName = (root["device"] as? [String: Any])?["protocol"] as? String
        if let pci = root["nvme_pci_vendor"] as? [String: Any], let id = number(pci["id"]), id >= 0, id <= 65535, id.rounded() == id {
            // Verified factual identifiers from the pciutils PCI ID repository.
            let known = [0x106b: "Apple Inc.", 0xc0a9: "Micron/Crucial Technology"]
            let code = String(format: "0x%04X", Int(id))
            r.controllerVendor = known[Int(id)].map { $0 + " (" + code + ")" } ?? "PCI Vendor " + code
        }
        for (key,prefix) in [("nvme_version","NVMe"),("sata_version","SATA"),("ata_version","ATA")] {
            if let version = root[key] as? [String: Any], let string = version["string"] as? String, !string.isEmpty {
                r.protocolVersion = string.hasPrefix(prefix) ? string : prefix + " " + string; break
            }
        }
        let ctl = root["smartctl"] as? [String: Any] ?? [:]
        r.messages = (ctl["messages"] as? [[String: Any]] ?? []).compactMap { $0["string"] as? String }
        if let exit = number(ctl["exit_status"]), Int(exit) & 3 != 0 { r.messages.append("smartctl could not open/read the device (exit \(Int(exit))). Check permissions and bridge support.") }
        func add(_ id: String, _ name: String, _ value: Any?, _ unit: String = "") { if let raw = textValue(value) { r.metrics.append(Metric(id: id, name: name, raw: raw, unit: unit)) } }
        if let n = root["nvme_smart_health_information_log"] as? [String: Any] {
            let fields: [(String,String,String)] = [("critical_warning","Critical Warning",""),("temperature","Temperature","°C"),("available_spare","Available Spare","%"),("available_spare_threshold","Spare Threshold","%"),("percentage_used","Percentage Used","%"),("data_units_read","Data Units Read",""),("data_units_written","Data Units Written",""),("host_reads","Host Read Commands",""),("host_writes","Host Write Commands",""),("controller_busy_time","Controller Busy Time","min"),("power_cycles","Power Cycles",""),("power_on_hours","Power On Hours","h"),("unsafe_shutdowns","Unsafe Shutdowns",""),("media_errors","Media / Data Integrity Errors",""),("num_err_log_entries","Error Information Log Entries","")]
            for (id,name,unit) in fields { add(id,name,n[id + "_s"] ?? n[id],unit) }
            for (src,dst,name) in [("data_units_read","read_bytes","Host Reads"),("data_units_written","write_bytes","Host Writes")] { if let val = number(n[src + "_s"] ?? n[src]), val >= 0 { add(dst,name,String(format: "%.0f", val * 512000),"bytes") } }
            for (i,v) in (n["temperature_sensors"] as? [Any] ?? []).enumerated() { add("sensor_\(i)","Temperature Sensor \(i + 1)",v,"°C") }
        } else {
            add("temperature","Temperature",(root["temperature"] as? [String: Any])?["current"],"°C")
            add("power_on_hours","Power On Hours",(root["power_on_time"] as? [String: Any])?["hours"],"h")
            add("power_cycles","Power Cycles",root["power_cycle_count"])
        }
        if let table = (root["ata_smart_attributes"] as? [String: Any])?["table"] as? [[String: Any]] {
            for a in table {
                guard let id = number(a["id"]).map(Int.init), let raw = a["raw"] as? [String: Any], let value = textValue(raw["value"]) else { continue }
                let name = a["name"] as? String ?? "Attribute \(id)"
                r.metrics.append(Metric(id: "ata_\(id)", name: name, raw: value, current: number(a["value"]).map(Int.init), worst: number(a["worst"]).map(Int.init), threshold: number(a["thresh"]).map(Int.init), failed: (a["when_failed"] as? String).map { !$0.isEmpty && $0 != "-" } ?? false))
            }
        }
        if let pages = (root["ata_device_statistics"] as? [String: Any])?["pages"] as? [[String: Any]] {
            for page in pages { for entry in page["table"] as? [[String: Any]] ?? [] {
                guard let name = entry["name"] as? String else { continue }
                if let flags = entry["flags"] as? [String: Any], flags["valid"] as? Bool == false { continue }
                let raw = entry["value_s"] ?? entry["value"]
                let id = "stat_" + (textValue(page["number"]) ?? "0") + "_" + (textValue(entry["offset"]) ?? name)
                add(id,name,raw)
                if number(page["number"]) == 7, number(entry["offset"]) == 8 { add("percentage_used", "Percentage Used Endurance Indicator (ATA Device Statistics)", raw, "%") }
                if let sectors = number(raw), let sectorSize = number(root["logical_block_size"]), sectorSize > 0 {
                    if name == "Logical Sectors Written" { add("write_bytes","Host Writes",String(format: "%.0f",sectors * sectorSize),"bytes") }
                    if name == "Logical Sectors Read" { add("read_bytes","Host Reads",String(format: "%.0f",sectors * sectorSize),"bytes") }
                }
            } }
        }
        for key in ["nvme_version","ata_version","sata_version","smart_support","trim","ata_smart_data","nvme_optional_admin_commands","nvme_optional_nvm_commands"] { if let val = root[key] { r.features.append("\(key): \(prettyJSON(["value": val]))") } }
        r.rotation = textValue(root["rotation_rate"]).map { $0 == "0" ? "SSD" : $0 + " rpm" }
        if let speed = root["sata_phy_event_counters"] { r.features.append("SATA PHY: \(prettyJSON(speed))") }
        if let speed = root["interface_speed"] as? [String: Any] { r.speed = "current: " + ((speed["current"] as? [String: Any])?["string"] as? String ?? "unknown") + "; max: " + ((speed["max"] as? [String: Any])?["string"] as? String ?? "unknown") }
        return r
    }
}
struct HealthEngine {
    static func evaluate(_ disk: inout Disk, settings: MonitorSettings, passed: Bool?) {
        var h: Health = passed == true ? .normal : .unknown; var reasons: [String] = []
        func mark(_ severity: Health, _ why: String) { if severity.rank > h.rank { h = severity }; reasons.append(why) }
        if passed == false || disk.smartStatus == "Failing" { mark(.danger,"Device reports SMART failure") }
        if let v = disk.value("critical_warning"), v != 0 { mark(.danger,"NVMe Critical Warning = \(v)") }
        if let spare = disk.value("available_spare"), let threshold = disk.value("available_spare_threshold"), threshold > 0, threshold <= 100, spare < threshold { mark(.danger,"Available spare below device threshold") }
        if let v = disk.value("percentage_used"), v >= settings.wearLimit { mark(.caution,"Endurance used ≥ \(settings.wearLimit)%") }
        if let v = disk.value("media_errors"), v >= settings.errorLimit { mark(.caution,"Media / data integrity errors ≥ \(settings.errorLimit)") }
        if let v = disk.value("temperature"), v >= settings.temperatureLimit { mark(.caution,"Temperature ≥ \(settings.temperatureLimit)°C") }
        for m in disk.metrics where m.id.hasPrefix("ata_") {
            if m.failed || (m.threshold ?? 0 > 0 && (m.current ?? Int.max) <= (m.threshold ?? 0)) { mark(.danger,"\(m.name): normalized value at/below threshold or failure recorded") }
            if ["ata_5","ata_197","ata_198","ata_199"].contains(m.id), let n = m.numeric, n >= settings.errorLimit { mark(.caution,"\(m.name): raw count ≥ \(settings.errorLimit)") }
        }
        if reasons.isEmpty { reasons = h == .normal ? ["Device SMART overall assessment passed; this is not a guarantee against failure"] : ["No reliable overall SMART assessment available"] }
        disk.health = h; disk.reasons = reasons
    }
}
struct AlertGate: Codable {
    var sent: [String: Date] = [:]
    mutating func permit(id: String, signature: String, now: Date, cooldown: Double) -> Bool {
        let key = id + ":" + signature
        if let last = sent[key], now.timeIntervalSince(last) < cooldown { return false }
        sent[key] = now; return true
    }
}

struct DiskTopology {
    static func merge(previous: [Disk], current: [Disk]) -> [Disk] {
        var next = current
        for var old in previous where !current.contains(where: { $0.id == old.id || ($0.discoveryID != nil && $0.discoveryID == old.discoveryID) }) {
            old.online = false; old.health = .unknown; old.reasons = ["Device offline; displayed values are historical"]; next.append(old)
        }
        return next
    }
}
struct PollingPolicy {
    static func shouldSample(_ d: Disk, settings: MonitorSettings, now: Date, force: Bool, sleeping: Bool) -> Bool {
        guard !sleeping, d.online else { return false }
        if force { return true }
        if settings.skipExternalHDD && !d.internalDisk && (d.kind == "HDD" || d.kind == "Unknown") { return false }
        return d.sampledAt.map { now.timeIntervalSince($0) >= (d.internalDisk ? settings.interval : settings.externalInterval) } ?? true
    }
}
struct DeviceOperationPolicy {
    static func allowsSelfTest(_ d: Disk) -> Bool {
        guard d.online, !d.kind.contains("NVMe"), let data = d.smartRaw.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let dev = root["device"] as? [String: Any], dev["protocol"] as? String == "ATA", let smart = root["ata_smart_data"] as? [String: Any], let capabilities = smart["capabilities"] as? [String: Any] else { return false }
        return capabilities["self_tests_supported"] as? Bool == true
    }
    static func validTest(_ name: String) -> Bool { ["short", "long", "abort"].contains(name) }
}

struct NVMeProfile {
    var device: String; var model: String; var serial: String?; var linkSpeed: String?
    static func parse(_ data: Data) throws -> [NVMeProfile] {
        let root = try JSONSerialization.jsonObject(with: data)
        var results: [NVMeProfile] = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let device = dict["bsd_name"] as? String, let model = dict["device_model"] as? String {
                    let rate = dict["spnvme_linkspeed"] as? String
                    let width = dict["spnvme_linkwidth"] as? String
                    let speed = [rate,width].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    results.append(NVMeProfile(device: device, model: model, serial: dict["device_serial"] as? String, linkSpeed: speed.isEmpty ? nil : speed))
                }
                for (_,v) in dict { walk(v) }
            } else if let list = value as? [Any] { list.forEach(walk) }
        }
        walk(root); return results
    }
}

enum SMARTAccess: String, Codable { case available, usbUnavailable, permissionDenied, readFailed, notRead, unavailable, offline }
struct USBProfile {
    var location: UInt64; var vendor: UInt64; var product: UInt64; var speed: String
    static func hex(_ value: Any?) -> UInt64? {
        guard let string = textValue(value) else { return nil }
        let token = string.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first.map(String.init) ?? ""
        if token.lowercased().hasPrefix("0x") { return UInt64(token.dropFirst(2), radix: 16) }; return UInt64(token)
    }
    static func parse(_ data: Data) throws -> [USBProfile] {
        var result: [USBProfile] = []
        func walk(_ value: Any) {
            if let d = value as? [String: Any] {
                if let location = hex(d["USBKeyLocationID"] ?? d["location_id"]), let vendor = hex(d["USBDeviceKeyVendorID"] ?? d["vendor_id"]), let product = hex(d["USBDeviceKeyProductID"] ?? d["product_id"]), let speed = (d["USBDeviceKeyLinkSpeed"] ?? d["speed"]) as? String, !speed.isEmpty { result.append(USBProfile(location: location, vendor: vendor, product: product, speed: speed)) }
                for v in d.values { walk(v) }
            } else if let list = value as? [Any] { list.forEach(walk) }
        }
        walk(try JSONSerialization.jsonObject(with: data)); return result
    }
    static func match(_ profiles: [USBProfile], location: UInt64?, vendor: UInt64?, product: UInt64?) -> USBProfile? {
        guard let location = location, let vendor = vendor, let product = product else { return nil }
        let matches = profiles.filter { $0.location == location && $0.vendor == vendor && $0.product == product }
        guard matches.count == 1 else { return nil }; return matches.first
    }
}
struct SMARTAccessPolicy {
    static func classify(bus: String, hasData: Bool, messages: [String]) -> SMARTAccess {
        if hasData { return .available }
        let text = messages.joined(separator: " ").lowercased()
        if text.contains("permission denied") || text.contains("not privileged") || text.contains("not permitted") { return .permissionDenied }
        if bus == "USB" && (text.contains("not supported") || text.contains("unsupported") || text.contains("unknown usb bridge")) { return .usbUnavailable }
        return .unavailable
    }
    static func restored(_ previous: Disk, discovered: Disk) -> Disk {
        var d = previous; d.device = discovered.device; d.volumes = discovered.volumes; d.online = true; d.speed = discovered.bus == "USB" || discovered.kind.contains("NVMe") ? discovered.speed : discovered.speed ?? previous.speed
        if !previous.online {
            d.health = .unknown; d.metrics = []; d.smartRaw = "{}"; d.smartAccess = .notRead; d.sampledAt = nil
            d.reasons = ["Device reconnected; waiting for a new SMART read"]
        }
        return d
    }
}
