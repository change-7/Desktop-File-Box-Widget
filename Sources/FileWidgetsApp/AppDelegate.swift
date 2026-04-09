import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DesktopSurfaceManager.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopSurfaceManager.shared.prepareForExit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showControlCenter() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where isControlCenter(window) {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    func hideControlCenter() {
        for window in NSApp.windows where isControlCenter(window) {
            window.orderOut(nil)
        }
    }

    private func isControlCenter(_ window: NSWindow) -> Bool {
        window.title == "Control Center"
    }
}
