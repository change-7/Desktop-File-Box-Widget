import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var surfaceManager: DesktopSurfaceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("File Tray")
                .font(.title2.weight(.semibold))

            Text("Widgets for your desktop files, with movable file panels, Quick Look, and direct unpin controls.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Create Empty Widget") {
                    surfaceManager.createEmptyWidget()
                }
                .buttonStyle(.borderedProminent)

                Button(surfaceManager.isEditing ? "Finish Layout" : "Edit Layout") {
                    surfaceManager.toggleEditMode()
                }
                .buttonStyle(.bordered)
            }

            Text("Current widgets: \(surfaceManager.panelControllers.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(surfaceManager.isEditing
                ? "Edit mode is on. Drag a widget by its background to move it, type width and height directly, and remove pinned items with the minus button or Remove from Widget."
                : "Use mode is on. Drag files or folders from Finder into widgets, use arrow keys to move selection, press Space for Quick Look, and unpin items from the button or context menu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(22)
    }
}
