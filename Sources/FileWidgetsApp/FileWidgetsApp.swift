import SwiftUI

@main
struct FileWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var surfaceManager = DesktopSurfaceManager.shared

    var body: some Scene {
        Window(L10n.controlCenter, id: "control-center") {
            ControlCenterView(surfaceManager: surfaceManager)
                .frame(minWidth: 420, minHeight: 260)
        }
        .windowResizability(.contentSize)

        MenuBarExtra(L10n.appName, systemImage: "folder.badge.plus") {
            MenuBarContentView(surfaceManager: surfaceManager)
        }
    }
}
