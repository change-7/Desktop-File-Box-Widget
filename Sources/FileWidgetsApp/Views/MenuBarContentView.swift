import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var surfaceManager: DesktopSurfaceManager
    @Environment(\.openWindow) private var openWindow

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Open Control Center") {
                openWindow(id: "control-center")
                appDelegate?.showControlCenter()
            }

            Button("Hide Control Center") {
                appDelegate?.hideControlCenter()
            }

            Button("Create Empty Widget") {
                surfaceManager.createEmptyWidget()
            }

            Divider()

            Button(surfaceManager.isEditing ? "Finish Layout" : "Edit Layout") {
                surfaceManager.toggleEditMode()
            }

            Divider()

            Button("Quit File Tray") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 220)
    }
}
