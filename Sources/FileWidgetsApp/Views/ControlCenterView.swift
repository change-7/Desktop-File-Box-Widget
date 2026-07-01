import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var surfaceManager: DesktopSurfaceManager
    @State private var customExtension = ""
    @State private var customCategory: FileTrayCategory = .documents

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.appName)
                    .font(.title2.weight(.semibold))

                Text(L10n.controlCenterDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(L10n.createEmptyWidget) {
                        surfaceManager.createEmptyWidget()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(surfaceManager.isEditing ? L10n.finishLayout : L10n.editLayout) {
                        surfaceManager.toggleEditMode()
                    }
                    .buttonStyle(.bordered)
                }

                Text(L10n.currentWidgets(surfaceManager.panelControllers.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(surfaceManager.isEditing
                    ? L10n.editModeDescription
                    : L10n.useModeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let widgetPersistenceWarning = surfaceManager.widgetPersistenceWarning {
                    Text(widgetPersistenceWarning)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
            Text(L10n.desktopSafety)
                .font(.headline)

            Text(surfaceManager.isDesktopHidingPaused
                ? L10n.desktopHidingPausedDescription
                : L10n.desktopHidingActiveDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(surfaceManager.isDesktopHidingPaused ? L10n.resumeDesktopHiding : L10n.showHiddenDesktopFiles) {
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
                    Text(L10n.attachmentExportRetention(formattedRetention(surfaceManager.autoTraySettings.dragExportRetentionMinutes)))
                        .font(.subheadline.weight(.medium))
                }

                Text(L10n.attachmentExportRetentionHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formattedRetention(_ minutes: Int) -> String {
        L10n.formattedRetention(minutes: minutes)
    }

    private var autoTraySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.automation)
                .font(.headline)

            Toggle(
                isOn: Binding(
                    get: { surfaceManager.autoTraySettings.collectDesktopScreenshots },
                    set: { surfaceManager.setCollectDesktopScreenshots($0) }
                )
            ) {
                Text(L10n.collectNewDesktopScreenshots)
            }

            Toggle(
                isOn: Binding(
                    get: { surfaceManager.autoTraySettings.organizeNewDesktopFiles },
                    set: { surfaceManager.setOrganizeNewDesktopFiles($0) }
                )
            ) {
                Text(L10n.organizeNewDesktopFilesByType)
            }

            Toggle(
                isOn: Binding(
                    get: { surfaceManager.autoTraySettings.organizeNewDesktopFilesByDate },
                    set: { surfaceManager.setOrganizeNewDesktopFilesByDate($0) }
                )
            ) {
                Text(L10n.organizeNewDesktopFilesByDate)
            }

            if surfaceManager.autoTraySettings.organizeNewDesktopFilesByDate {
                Text(L10n.dateTrayPriorityHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
            }

            if surfaceManager.autoTraySettings.organizeNewDesktopFiles {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(FileTrayCategory.allCases) { category in
                        Toggle(
                            isOn: Binding(
                                get: { surfaceManager.autoTraySettings.enabledCategories.contains(category) },
                                set: { surfaceManager.setAutoTrayCategory(category, isEnabled: $0) }
                            )
                        ) {
                            Text(category.title)
                        }
                    }
                }
                .padding(.leading, 10)

                customRulesEditor
            }
        }
    }

    private var customRulesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.customFileTypes)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField(L10n.extensionPlaceholder, text: $customExtension)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Picker(L10n.category, selection: $customCategory) {
                    ForEach(FileTrayCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Button(L10n.add) {
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

                    Button(L10n.remove) {
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
