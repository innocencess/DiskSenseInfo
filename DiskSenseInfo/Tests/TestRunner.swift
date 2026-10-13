import Foundation

@main struct TestRunner {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) { if !condition() { print("FAIL: " + name); exit(1) }; count += 1; print("PASS: " + name) }
    static func disk() -> Disk { Disk(id: "fixture", device: "disk999", model: "TEST FIXTURE", capacity: 1000, bus: "TEST", kind: "SSD", internalDisk: true, smartStatus: "Unknown") }
    static func parse(_ s: String) throws -> SmartResult { try SmartParser.parse(Data(s.utf8)) }
    static func main() async throws {
        let nvme = try parse("""
        {"device":{"protocol":"NVMe"},"smart_status":{"passed":true},"nvme_smart_health_information_log":{"critical_warning":0,"temperature":42,"available_spare":100,"available_spare_threshold":10,"percentage_used":8,"data_units_read":2,"data_units_written":3,"power_cycles":22,"power_on_hours":99,"unsafe_shutdowns":5,"media_errors":0,"num_err_log_entries":0,"host_reads_s":"184467440737095516160"}}
        """)
        var d = disk(); d.metrics = nvme.metrics
        check(d.value("read_bytes") == 1_024_000, "NVMe data units are 512000 bytes")
        check(d.metrics.first { $0.id == "host_reads" }?.raw == "184467440737095516160", "Large counters preserve string precision")
        check(d.metrics.first { $0.id == "host_reads" }?.formatted(hex: true) == "184467440737095516160", "Large counters never truncate into hexadecimal")
        HealthEngine.evaluate(&d, settings: MonitorSettings(), passed: nvme.passed); check(d.health == .normal, "Passing overall assessment")
        d.metrics.append(Metric(id:"critical_warning",name:"warning",raw:"1")); d.metrics.removeAll { $0.id == "critical_warning" && $0.raw == "0" }
        HealthEngine.evaluate(&d, settings: MonitorSettings(), passed: true); check(d.health == .danger, "NVMe critical warning overrides passed status")
        var absent = disk(); HealthEngine.evaluate(&absent, settings: MonitorSettings(), passed: nil); check(absent.health == .unknown, "Missing SMART is unknown")
        absent.metrics = [Metric(id:"temperature",name:"temp",raw:"35",unit:"°C")]; HealthEngine.evaluate(&absent, settings: MonitorSettings(), passed: nil); check(absent.health == .unknown, "Normal temperature alone cannot establish health")
        absent.metrics = [Metric(id:"available_spare",name:"spare",raw:"5"),Metric(id:"available_spare_threshold",name:"threshold",raw:"10")]; HealthEngine.evaluate(&absent, settings: MonitorSettings(), passed: true); check(absent.health == .danger, "Spare below device threshold is dangerous")
        let ata = try parse("""
        {"smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":197,"name":"Current_Pending_Sector","value":100,"worst":100,"thresh":0,"raw":{"value":4}},{"id":9,"name":"Power_On_Hours","value":90,"worst":90,"thresh":0,"raw":{"value":2000}}]}}
        """)
        d = disk(); d.metrics = ata.metrics; HealthEngine.evaluate(&d, settings: MonitorSettings(), passed: ata.passed); check(d.health == .caution, "Pending sectors cause caution")
        check(d.value("percentage_used") == nil, "Vendor ATA IDs do not invent wear percentage")
        d.metrics = [Metric(id:"ata_1",name:"Read Error",raw:"0",current:10,worst:10,threshold:10)]; HealthEngine.evaluate(&d, settings: MonitorSettings(), passed: true); check(d.health == .danger, "Normalized threshold failure")
        d.metrics = [Metric(id:"ata_9",name:"Power On",raw:"100",current:0,worst:0,threshold:0)]; HealthEngine.evaluate(&d, settings: MonitorSettings(), passed: true); check(d.health == .normal, "Zero threshold does not mean failure")
        let denied = try parse("{\"smartctl\":{\"exit_status\":2,\"messages\":[{\"string\":\"Permission denied\"}]}}")
        check(denied.passed == nil && denied.metrics.isEmpty && !denied.messages.isEmpty, "Permission denial retains actionable diagnostic")
        let partial = try parse("{\"smart_status\":{\"passed\":true},\"smartctl\":{\"exit_status\":4,\"messages\":[{\"string\":\"Log page failed\"}]},\"temperature\":{\"current\":40}}")
        check(partial.passed == true && partial.metrics.count == 1 && partial.messages == ["Log page failed"], "Log failure does not discard readable health data")
        do { _ = try parse("not json"); check(false, "Malformed JSON must throw") } catch { check(true, "Malformed JSON rejected") }
        let nodes: [[String:Any]] = [["DeviceIdentifier":"disk0","Partitions":[["DeviceIdentifier":"disk0s2","DiskUUID":"persistent"]]],["DeviceIdentifier":"disk3","APFSPhysicalStores":[["DeviceIdentifier":"disk0s2"]],"APFSVolumes":[["DeviceIdentifier":"disk3s1","VolumeName":"Private"]]],["DeviceIdentifier":"disk8","APFSPhysicalStores":[["DeviceIdentifier":"disk10s2"]],"APFSVolumes":[["DeviceIdentifier":"disk8s1"]]]]
        let owned = DiskDiscovery.ownedVolumes(device: "disk0", nodes: nodes)
        check(owned.count == 2 && owned.last?["SharedAPFS"] as? Bool == true, "Physical disk maps to APFS volumes without disk1/disk10 prefix collision")
        d = disk(); d.serial = "SECRET_SERIAL"; d.raw = "SECRET_SERIAL"; d.smartRaw = "SECRET_SERIAL"; d.diagnostics = ["SECRET_SERIAL"]; d.volumes = [Volume(id:"SECRET_VOLUME",name:"SECRET_VOLUME",mount:"/Volumes/SECRET_VOLUME",filesystem:"APFS",total:1000,used:200,free:800,shared:true)]; d.metrics = nvme.metrics
        let sample = Sample(d)
        let report = try Exporter.report([d], samples: [sample], redact: true, format: "json")
        let reportText = String(data:report,encoding:.utf8)!
        check(!reportText.contains("SECRET_SERIAL") && !reportText.contains("SECRET_VOLUME") && !reportText.contains("fixture"), "Redaction covers raw payload, volumes, diagnostics, identity and history")
        var inject = sample; inject.metrics = [Metric(id:"csv",name:"=HYPERLINK(test)",raw:"1")]
        let csv = String(data:try Exporter.report([d],samples:[inject],redact:true,format:"csv"),encoding:.utf8)!
        check(csv.contains("'=HYPERLINK"), "CSV formula injection neutralized")
        var gate = AlertGate(); let now = Date()
        check(gate.permit(id:"d",signature:"hot",now:now,cooldown:100), "First alert allowed")
        check(!gate.permit(id:"d",signature:"hot",now:now.addingTimeInterval(20),cooldown:100), "Repeated alert suppressed")
        check(gate.permit(id:"d",signature:"failure",now:now.addingTimeInterval(20),cooldown:100), "Distinct severe condition allowed")
        check(gate.permit(id:"d",signature:"hot",now:now.addingTimeInterval(101),cooldown:100), "Alert after cooldown allowed")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir); var expired = sample; expired.date = now.addingTimeInterval(-100 * 86400)
        try store.save([sample,expired],days:90,now:now); let loaded = try store.load()
        check(loaded.count == 1 && loaded[0].metrics == sample.metrics, "History roundtrip and retention pruning")
        try Data("corrupt".utf8).write(to:store.historyURL)
        do { _ = try store.load(); check(false,"Corrupt history must throw") } catch { check(true,"Corrupt history not silently accepted") }
        do { _ = try await CommandRunner.run("/bin/sleep",["2"],timeout:0.1); check(false,"Timeout must throw") } catch { check(true,"Subprocess timeout enforced") }
        let task = Task { try await CommandRunner.run("/bin/sleep",["5"],timeout:10) }
        try await Task.sleep(nanoseconds:100_000_000); task.cancel()
        do { _ = try await task.value; check(false,"Cancellation must throw") } catch { check(true,"Subprocess cancellation enforced") }
        let output = try await CommandRunner.run("/usr/bin/printf",["%s","literal $(echo unsafe) `uname`"],timeout:2)
        check(String(data:output.data,encoding:.utf8) == "literal $(echo unsafe) `uname`", "Arguments are literal, never shell-evaluated")
        var hotplug = disk(); hotplug.id = "stable-A"; hotplug.discoveryID = "discovery-A"; hotplug.device = "disk2"; hotplug.sampledAt = now
        var renumbered = hotplug; renumbered.device = "disk5"
        check(DiskTopology.merge(previous:[hotplug], current:[renumbered]).count == 1, "Device renumbering does not duplicate physical disk")
        let unplugged = DiskTopology.merge(previous:[hotplug], current:[])
        check(unplugged[0].online == false && unplugged[0].health == .unknown && unplugged[0].sampledAt == now, "Hot unplug keeps historical sample but marks health unknown")
        var replacement = hotplug; replacement.id = "stable-B"; replacement.discoveryID = "discovery-B"
        let replaced = DiskTopology.merge(previous:[hotplug], current:[replacement])
        check(replaced.count == 2 && replaced[0].online && !replaced[1].online, "Reused BSD node cannot silently inherit previous drive health")
        check(!PollingPolicy.shouldSample(hotplug,settings:MonitorSettings(),now:now,force:true,sleeping:true), "Sleep blocks collection even for a forced request")
        check(PollingPolicy.shouldSample(hotplug,settings:MonitorSettings(),now:now.addingTimeInterval(301),force:false,sleeping:false), "Wake allows overdue internal sample")
        var external = hotplug; external.internalDisk = false; external.kind = "HDD"; external.sampledAt = nil
        check(!PollingPolicy.shouldSample(external,settings:MonitorSettings(),now:now,force:false,sleeping:false), "External HDD automatic polling skipped by default")
        check(PollingPolicy.shouldSample(external,settings:MonitorSettings(),now:now,force:true,sleeping:false), "Explicit refresh can sample an external HDD")
        check(Metric(id:"bad",name:"bad",raw:"nan").numeric == nil, "Nonfinite metrics cannot crash temperature conversion")
        let restored = try JSONDecoder().decode(AlertGate.self,from:JSONEncoder().encode(gate))
        check(restored.sent.count == gate.sent.count, "Notification cooldown survives persistence")
        var sataOperations = disk(); sataOperations.kind = "HDD"; sataOperations.smartRaw = "{\"device\":{\"protocol\":\"ATA\"},\"ata_smart_data\":{\"capabilities\":{\"self_tests_supported\":true}}}"
        check(DeviceOperationPolicy.allowsSelfTest(sataOperations), "ATA test allowed only with explicit capability")
        sataOperations.online = false; check(!DeviceOperationPolicy.allowsSelfTest(sataOperations), "Offline disk cannot run test")
        sataOperations.online = true; sataOperations.kind = "NVMe SSD"; check(!DeviceOperationPolicy.allowsSelfTest(sataOperations), "NVMe test disabled despite capability because Darwin backend cannot send it")
        check(!DeviceOperationPolicy.validTest("short; erase") && DeviceOperationPolicy.validTest("long"), "Self-test command is strictly allowlisted")
        let standardATA = try parse("""
        {"logical_block_size":4096,"ata_device_statistics":{"pages":[{"number":7,"table":[{"offset":8,"name":"Percentage Used Endurance Indicator","value":12,"flags":{"valid":true}}]},{"number":1,"table":[{"offset":24,"name":"Logical Sectors Written","value":10,"flags":{"valid":true}},{"offset":32,"name":"Logical Sectors Read","value":999,"flags":{"valid":false}}]}]}}
        """)
        d.metrics = standardATA.metrics
        check(d.value("percentage_used") == 12, "Standard ATA Device Statistics endurance is supported without vendor guessing")
        check(d.value("write_bytes") == 40960 && d.value("read_bytes") == nil, "ATA sector bytes use logical sector size and ignore invalid statistics")
        let apple = try parse("{\"nvme_pci_vendor\":{\"id\":4203},\"nvme_version\":{\"string\":\"<1.2\",\"value\":0}}")
        check(apple.controllerVendor == "Apple Inc. (0x106B)" && apple.protocolVersion == "NVMe <1.2", "Apple vendor ID and reported legacy NVMe version preserved")
        let crucial = try parse("{\"nvme_pci_vendor\":{\"id\":49321},\"nvme_version\":{\"string\":\"1.3\"}}")
        check(crucial.controllerVendor == "Micron/Crucial Technology (0xC0A9)" && crucial.protocolVersion == "NVMe 1.3", "Crucial PCI identity and protocol version parsed separately")
        let unknownVendor = try parse("{\"nvme_pci_vendor\":{\"id\":1234}}")
        check(unknownVendor.controllerVendor == "PCI Vendor 0x04D2", "Unknown vendor retains factual code without guessed manufacturer")
        let sataVersion = try parse("{\"sata_version\":{\"string\":\"SATA 3.3\"}}")
        check(sataVersion.protocolVersion == "SATA 3.3" && sataVersion.speed == nil, "SATA version cannot masquerade as negotiated speed")
        let profiles = try NVMeProfile.parse(Data("{\"SPNVMeDataType\":[{\"_items\":[{\"bsd_name\":\"disk4\",\"device_model\":\"TEST\",\"device_serial\":\"fixture\",\"spnvme_linkspeed\":\"8.0 GT/s\",\"spnvme_linkwidth\":\"x4\"},{\"bsd_name\":\"disk0\",\"device_model\":\"APPLE\",\"size_in_bytes\":1}]}]}".utf8))
        check(profiles.count == 2 && profiles[0].linkSpeed == "8.0 GT/s · x4" && profiles[1].linkSpeed == nil, "Nested NVMe profile extracts actual rate/lane count and leaves absent rate unknown")
        d.manufacturer = "  "; d.controllerVendor = apple.controllerVendor
        check(d.reportedManufacturer == nil && (d.reportedManufacturer ?? d.controllerVendor) == "Apple Inc. (0x106B)", "Empty IOKit vendor cannot suppress the PCI fallback")
        let usb = try USBProfile.parse(Data("{\"SPUSBHostDataType\":[{\"USBKeyLocationID\":\"0x02000000\",\"_items\":[{\"USBKeyLocationID\":\"0x02200000\",\"USBDeviceKeyVendorID\":\"0x0b05\",\"USBDeviceKeyProductID\":\"0x1b9f\",\"USBDeviceKeyLinkSpeed\":\"10 Gb/s\"},{\"USBKeyLocationID\":\"0x02300000\",\"USBDeviceKeyVendorID\":\"0x0b05\",\"USBDeviceKeyProductID\":\"0x1b9f\",\"USBDeviceKeyLinkSpeed\":\"5 Gb/s\"}]}]}".utf8))
        check(USBProfile.match(usb,location:0x02200000,vendor:0x0b05,product:0x1b9f)?.speed == "10 Gb/s", "USB speed matches physical location not similar product or parent bus")
        check(USBProfile.match(usb,location:0x02200000,vendor:0x1234,product:0x1b9f) == nil, "USB vendor mismatch rejected")
        let legacyUSB = try USBProfile.parse(Data("{\"SPUSBDataType\":[{\"location_id\":\"0x02200000 / 3\",\"vendor_id\":\"0x0b05 (ASUS)\",\"product_id\":\"0x1b9f\",\"speed\":\"Up to 10 Gb/s\"}]}".utf8))
        check(legacyUSB.first?.speed == "Up to 10 Gb/s", "Legacy USB report preserves up-to qualification")
        check(SMARTAccessPolicy.classify(bus:"USB",hasData:false,messages:["Operation not supported by device"]) == .usbUnavailable, "USB unsupported path is distinct from disk failure")
        check(SMARTAccessPolicy.classify(bus:"USB",hasData:false,messages:["Permission denied"]) == .permissionDenied, "USB permission denial is not mislabeled bridge limitation")
        check(SMARTAccessPolicy.classify(bus:"USB",hasData:true,messages:["Log not supported"]) == .available, "Partial SMART remains available despite one log failure")
        var disconnected = disk(); disconnected.online = false; disconnected.health = .danger; disconnected.metrics = [Metric(id:"temperature",name:"temp",raw:"99")]; disconnected.reasons = ["Device offline; displayed values are historical"]
        let restoredDisk = SMARTAccessPolicy.restored(disconnected,discovered:disk())
        check(restoredDisk.online && restoredDisk.health == .unknown && restoredDisk.sampledAt == nil && restoredDisk.metrics.isEmpty && restoredDisk.access == .notRead && !restoredDisk.reasons.contains("Device offline; displayed values are historical"), "Reconnection cannot inherit offline explanation or stale SMART health")
        print("\(count) tests passed")
    }
}
