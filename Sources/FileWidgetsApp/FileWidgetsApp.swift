import SwiftUI

@main
struct FileWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var surfaceManager = DesktopSurfaceManager.shared

    var body: some Scene {
        Window("Control Center", id: "control-center") {
            ControlCenterView(surfaceManager: surfaceManager)
                .frame(minWidth: 420, minHeight: 260)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("File Tray", systemImage: "folder.badge.plus") {
            MenuBarContentView(surfaceManager: surfaceManager)
        }
    }
}
