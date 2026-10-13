import Foundation
@main struct LiveProbe {
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let disks = try await DiskDiscovery.discover()
        var result: [Disk] = []
        for d in disks { result.append(await DiskCollector(smartctlPath: folder.appendingPathComponent("Resources/smartctl").path,databasePath:folder.appendingPathComponent("Resources/drivedb.h").path).collect(d, settings:MonitorSettings(),automatic:false)) }
        for d in result { print("\(d.model) | \(d.kind) | \(d.health.rawValue) | \(d.metrics.count) metrics | \(d.volumes.count) partitions/volumes | \(d.diagnostics.count) diagnostics | vendor: \(d.controllerVendor ?? d.manufacturer ?? "unavailable") | protocol: \(d.protocolVersion ?? "unavailable") | link: \(d.speed ?? "unavailable") | SMART access: \(d.access.rawValue)") }
        try Exporter.report(result,samples:result.map(Sample.init),redact:true,format:"json").write(to:folder.appendingPathComponent("Docs/LiveValidation-redacted.json"))
        guard result.count > 0, result.allSatisfy({ $0.sampledAt != nil }), result.contains(where: { !$0.metrics.isEmpty }) else { throw NSError(domain:"LiveProbe",code:1) }
    }
}
