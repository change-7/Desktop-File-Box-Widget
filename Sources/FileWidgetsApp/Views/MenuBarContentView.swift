import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var surfaceManager: DesktopSurfaceManager
    @Environment(\.openWindow) private var openWindow

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(L10n.openControlCenter) {
                openWindow(id: "control-center")
                appDelegate?.showControlCenter()
            }

            Button(L10n.hideControlCenter) {
                appDelegate?.hideControlCenter()
            }

            Button(L10n.createEmptyWidget) {
                surfaceManager.createEmptyWidget()
            }

            Divider()

            Button(surfaceManager.isEditing ? L10n.finishLayout : L10n.editLayout) {
                surfaceManager.toggleEditMode()
            }

            Button(surfaceManager.isDesktopHidingPaused ? L10n.resumeDesktopHiding : L10n.showHiddenDesktopFiles) {
                if surfaceManager.isDesktopHidingPaused {
                    surfaceManager.resumeDesktopHiding()
                } else {
                    surfaceManager.pauseDesktopHidingAndRestoreItems()
                }
            }

            Divider()

            Button(L10n.quitFileTray) {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 220)
    }
}
