import SwiftUI
import AppKit

@main struct DiskSenseInfoApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    var menuTitle: String { if let d = model.selected { if !d.online { return "DSI • Offline" }; if model.settings.menuTemperature, let v = d.value("temperature"), (-273.15...1000).contains(v) { return String(format: "DSI %.0f°C", v) }; return "DSI • " + model.healthName(d.health) }; return "DSI" }
    var body: some Scene {
        WindowGroup("DiskSenseInfo", id: "main") { ContentView().environmentObject(model) }
        Settings { SettingsView().environmentObject(model) }
        MenuBarExtra(menuTitle, systemImage: "opticaldisc") {
            Button(model.tr("開啟 DiskSenseInfo", "Open DiskSenseInfo")) { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
            ForEach(model.disks) { d in Button(d.model + " · " + (d.online ? model.healthName(d.health) : model.tr("離線", "Offline"))) { model.selectedID = d.id; model.settings.selectedID = d.id } }
            Divider()
            Button(model.tr("立即更新", "Refresh now")) { model.refresh(force: true) }.disabled(model.busy)
            Button(model.tr("結束", "Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
