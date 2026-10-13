import SwiftUI
import AppKit
@main struct RenderLive {
    @MainActor static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let ns = NSApplication.shared; ns.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let resources = root.appendingPathComponent("Resources")
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("DiskSenseInfo-render-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: scratch) }
                let model = AppModel(dataDirectory:scratch,resources:resources,monitor:false)
                let disks = try await DiskDiscovery.discover()
                for d in disks { model.disks.append(await DiskCollector(smartctlPath:resources.appendingPathComponent("smartctl").path,databasePath:resources.appendingPathComponent("drivedb.h").path).collect(d,settings:model.settings,automatic:false)) }
                model.selectedID = model.disks.first?.id
                model.samples = model.disks.map(Sample.init)
                for (tab,name) in [(0,"LivePreview"),(1,"SMARTPreview"),(2,"HistoryPreview"),(3,"DiagnosticsPreview"),(0,"DarkPreview"),(0,"EnglishPreview"),(4,"SettingsPreview"),(0,"USBPreview")] {
                    model.selectedID = name == "USBPreview" ? (model.disks.first { $0.bus == "USB" }?.id ?? model.disks.first?.id) : model.disks.first?.id
                    model.settings.language = name == "EnglishPreview" ? "en" : "zh"
                    let dark = name == "DarkPreview"
                    ns.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    let rootView = tab == 4 ? AnyView(SettingsView().environmentObject(model)) : AnyView(ContentView(initialTab:tab).environmentObject(model))
                    let view = NSHostingView(rootView: rootView.environment(\.colorScheme, dark ? .dark : .light))
                    view.frame = tab == 4 ? NSRect(x:0,y:0,width:620,height:760) : NSRect(x:0,y:0,width:1280,height:name == "USBPreview" ? 1100 : 860)
                    let window = NSWindow(contentRect:view.frame,styleMask:[.titled,.resizable],backing:.buffered,defer:false)
                    window.contentView = view
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw NSError(domain:"Render",code:1) }
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    guard let png = bitmap.representation(using:.png,properties:[:]) else { throw NSError(domain:"Render",code:2) }
                    try png.write(to:root.appendingPathComponent("Docs/" + name + ".png"))
                }
                print("Rendered app-owned SwiftUI view with real drive data, without screen capture.")
                exit(0)
            } catch { print(error); exit(1) }
        }
        ns.run()
    }
}
