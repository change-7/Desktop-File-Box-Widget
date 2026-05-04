import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var surfaceManager: DesktopSurfaceManager
    @State private var customExtension = ""
    @State private var customCategory: FileTrayCategory = .documents

    var body: some View {
        ScrollView {
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

                Divider()

                safetyControls

                Divider()

                autoTraySettings
            }
            .padding(22)
        }
    }

    private var safetyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Desktop Safety")
                .font(.headline)

            Text(surfaceManager.isDesktopHidingPaused
                ? "Desktop file hiding is paused for this app session. Pinned files stay visible on the Desktop until hiding is resumed or the app restarts."
                : "If hidden Desktop files ever need to be restored while the app is still running, pause hiding and show them immediately.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(surfaceManager.isDesktopHidingPaused ? "Resume Desktop Hiding" : "Show Hidden Desktop Files") {
                if surfaceManager.isDesktopHidingPaused {
                    surfaceManager.resumeDesktopHiding()
                } else {
                    surfaceManager.pauseDesktopHidingAndRestoreItems()
                }
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Stepper(
                    value: Binding(
                        get: { surfaceManager.autoTraySettings.dragExportRetentionMinutes },
                        set: { surfaceManager.setDragExportRetentionMinutes($0) }
                    ),
                    in: AutoTraySettings.minimumDragExportRetentionMinutes...AutoTraySettings.maximumDragExportRetentionMinutes,
                    step: 15
                ) {
                    Text("Attachment export retention: \(formattedRetention(surfaceManager.autoTraySettings.dragExportRetentionMinutes))")
                        .font(.subheadline.weight(.medium))
                }

                Text("Used only for hidden Desktop items dragged from File Tray into apps or browser upload areas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formattedRetention(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        return "\(hours)h \(remainingMinutes)m"
    }

    private var autoTraySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automation")
                .font(.headline)

            Toggle(
                "Collect new Desktop screenshots",
                isOn: Binding(
                    get: { surfaceManager.autoTraySettings.collectDesktopScreenshots },
                    set: { surfaceManager.setCollectDesktopScreenshots($0) }
                )
            )

            Toggle(
                "Organize new Desktop files by type",
                isOn: Binding(
                    get: { surfaceManager.autoTraySettings.organizeNewDesktopFiles },
                    set: { surfaceManager.setOrganizeNewDesktopFiles($0) }
                )
            )

            if surfaceManager.autoTraySettings.organizeNewDesktopFiles {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(FileTrayCategory.allCases) { category in
                        Toggle(
                            category.title,
                            isOn: Binding(
                                get: { surfaceManager.autoTraySettings.enabledCategories.contains(category) },
                                set: { surfaceManager.setAutoTrayCategory(category, isEnabled: $0) }
                            )
                        )
                    }
                }
                .padding(.leading, 10)

                customRulesEditor
            }
        }
    }

    private var customRulesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom file types")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Extension", text: $customExtension)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Picker("Category", selection: $customCategory) {
                    ForEach(FileTrayCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Button("Add") {
                    surfaceManager.addCustomFileTypeRule(extension: customExtension, category: customCategory)
                    customExtension = ""
                }
                .disabled(customExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(surfaceManager.autoTraySettings.customRules) { rule in
                HStack(spacing: 8) {
                    Text(".\(rule.fileExtension)")
                        .font(.caption.monospaced())

                    Text(rule.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Remove") {
                        surfaceManager.removeCustomFileTypeRule(rule)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding(.leading, 10)
    }
}
