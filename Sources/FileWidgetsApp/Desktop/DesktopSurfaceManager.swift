import AppKit
import Darwin
import OSLog

@MainActor
final class DesktopSurfaceManager: ObservableObject {
    static let shared = DesktopSurfaceManager()

    @Published private(set) var panelControllers: [DesktopWidgetPanelController] = []
    @Published private(set) var isEditing = false
    @Published private(set) var autoTraySettings = AutoTraySettings.defaultValue
    @Published private(set) var isDesktopHidingPaused = false
    @Published private(set) var widgetPersistenceWarning: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.filetray.app",
        category: "DesktopSurface"
    )
    private let snapGridEngine = SnapGridEngine()
    private let systemWidgetReservationService = SystemWidgetReservationService.shared
    private let desktopItemVisibilityService = DesktopItemVisibilityService.shared
    private let desktopAutoTrayService = DesktopAutoTrayService()
    private let metrics = WidgetGridMetrics()
    private let persistenceStore = WidgetPersistenceStore.shared
    private let autoTraySettingsStore = AutoTraySettingsStore.shared
    private var didBootstrap = false
    private var isWidgetPersistenceSuspended = false
    private var pendingStateSync: DispatchWorkItem?
    private var pendingVisibilitySync = false

    private init() {}

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        desktopItemVisibilityService.recoverInterruptedSessionIfNeeded()
        autoTraySettings = autoTraySettingsStore.load()
        FileDragExportService.shared.setRetentionMinutes(autoTraySettings.dragExportRetentionMinutes)
        FileDragExportService.shared.performMaintenance()

        switch persistenceStore.loadWidgets() {
        case .missing:
            createEmptyWidget()
        case .loaded(let restoredWidgets) where restoredWidgets.isEmpty:
            createEmptyWidget()
        case .loaded(let restoredWidgets):
            restoredWidgets.forEach { widget in
                localizeGeneratedTitleIfNeeded(for: widget)
                _ = addWidgetController(for: widget)
            }
        case .failed(let backupURL):
            isWidgetPersistenceSuspended = true
            widgetPersistenceWarning = L10n.widgetPersistenceWarning(backupName: backupURL?.lastPathComponent)
            logger.error("Widget persistence is suspended because the saved state could not be loaded")
            createEmptyWidget(persistState: false)
        }

        let sessionID = UUID().uuidString
        let ownerPID = getpid()
        let ownerExecutablePath = Bundle.main.executableURL?.standardizedFileURL.path
        desktopItemVisibilityService.beginSession(
            ownerPID: ownerPID,
            sessionID: sessionID,
            ownerExecutablePath: ownerExecutablePath
        )
        desktopItemVisibilityService.launchGuardianIfPossible(
            sessionID: sessionID,
            ownerPID: ownerPID,
            ownerExecutablePath: ownerExecutablePath
        )
        pruneMissingDesktopItems()
        flushState(includingVisibilitySync: true)
        desktopAutoTrayService.start(
            onNewDesktopItem: { [weak self] url in
                self?.handleNewDesktopItem(url)
            },
            onDesktopItemsChanged: { [weak self] in
                self?.pruneMissingDesktopItems()
            }
        )
    }

    func createEmptyWidget(persistState: Bool = true) {
        let nextIndex = panelControllers.count
        let widget = WidgetModel(
            title: L10n.pinnedFiles(nextIndex + 1),
            panelSize: metrics.defaultPanelSize,
            backgroundOpacity: 0.78,
            displayMode: .grid,
            trayKind: .manual,
            items: []
        )

        addWidgetController(for: widget)
        if persistState {
            scheduleStateSync(includingVisibilitySync: true)
        }
    }

    func widgetContentDidChange() {
        scheduleStateSync(includingVisibilitySync: true)
    }

    func widgetAppearanceDidChange() {
        scheduleStateSync(includingVisibilitySync: false)
    }

    func flushState(includingVisibilitySync: Bool = true) {
        pendingStateSync?.cancel()
        pendingStateSync = nil
        pendingVisibilitySync = false

        let widgets = currentWidgets()
        if isWidgetPersistenceSuspended {
            logger.warning("Skipped widget persistence save because loading saved state failed earlier in this session")
        } else {
            persistenceStore.saveWidgets(widgets)
        }
        guard includingVisibilitySync else { return }
        guard isDesktopHidingPaused == false else {
            desktopItemVisibilityService.restoreManagedDesktopItems(endingSession: false)
            return
        }

        desktopItemVisibilityService.synchronizePinnedItems(widgets.flatMap { $0.items.map(\.url) })
    }

    func prepareForExit() {
        desktopAutoTrayService.stop()
        FileDragExportService.shared.performMaintenance()
        pendingStateSync?.cancel()
        pendingStateSync = nil
        pendingVisibilitySync = false

        if isWidgetPersistenceSuspended {
            logger.warning("Skipped widget persistence save during exit because loading saved state failed earlier in this session")
        } else {
            persistenceStore.saveWidgets(currentWidgets())
        }
        desktopItemVisibilityService.restoreManagedDesktopItems()
    }

    @discardableResult
    private func addWidgetController(for widget: WidgetModel) -> DesktopWidgetPanelController {
        let controller = DesktopWidgetPanelController(widgetModel: widget, surfaceManager: self)
        panelControllers.append(controller)
        controller.showWindow(nil)
        controller.updateEditMode(isEditing)
        controller.placeInitialWindow(on: NSScreen.main)
        return controller
    }

    private func currentWidgets() -> [WidgetModel] {
        panelControllers.map(\.model)
    }

    private func localizeGeneratedTitleIfNeeded(for widget: WidgetModel) {
        switch widget.trayKind {
        case .manual:
            guard let generatedIndex = L10n.generatedPinnedFilesIndex(from: widget.title) else { return }
            widget.title = L10n.pinnedFiles(generatedIndex)
        case .screenshots:
            guard L10n.isGeneratedScreenshotsTitle(widget.title) else { return }
            widget.title = L10n.screenshots
        case .auto(let category):
            guard L10n.isGeneratedCategoryTitle(widget.title) else { return }
            widget.title = category.title
        case .date:
            if widget.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                widget.title = widget.trayKind.title
            }
        }
    }

    private func scheduleStateSync(includingVisibilitySync: Bool) {
        pendingStateSync?.cancel()
        pendingVisibilitySync = pendingVisibilitySync || includingVisibilitySync

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let shouldSyncVisibility = self.pendingVisibilitySync
            self.flushState(includingVisibilitySync: shouldSyncVisibility)
        }
        pendingStateSync = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    func toggleEditMode() {
        isEditing.toggle()
        panelControllers.forEach { $0.updateEditMode(isEditing) }
    }

    func pauseDesktopHidingAndRestoreItems() {
        isDesktopHidingPaused = true
        pendingVisibilitySync = false
        desktopItemVisibilityService.restoreManagedDesktopItems(endingSession: false)
    }

    func resumeDesktopHiding() {
        guard isDesktopHidingPaused else { return }
        isDesktopHidingPaused = false
        scheduleStateSync(includingVisibilitySync: true)
    }

    func setCollectDesktopScreenshots(_ isEnabled: Bool) {
        autoTraySettings.collectDesktopScreenshots = isEnabled
        persistAutoTraySettings()
    }

    func setOrganizeNewDesktopFiles(_ isEnabled: Bool) {
        autoTraySettings.organizeNewDesktopFiles = isEnabled
        persistAutoTraySettings()
    }

    func setOrganizeNewDesktopFilesByDate(_ isEnabled: Bool) {
        autoTraySettings.organizeNewDesktopFilesByDate = isEnabled
        persistAutoTraySettings()
    }

    func setAutoTrayCategory(_ category: FileTrayCategory, isEnabled: Bool) {
        if isEnabled {
            autoTraySettings.enabledCategories.insert(category)
        } else {
            autoTraySettings.enabledCategories.remove(category)
        }
        persistAutoTraySettings()
    }

    func addCustomFileTypeRule(extension rawExtension: String, category: FileTrayCategory) {
        let normalizedExtension = rawExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard normalizedExtension.isEmpty == false else { return }

        autoTraySettings.customRules.removeAll { $0.fileExtension == normalizedExtension }
        autoTraySettings.enabledCategories.insert(category)
        autoTraySettings.customRules.append(
            CustomFileTypeRule(fileExtension: normalizedExtension, category: category)
        )
        persistAutoTraySettings()
    }

    func removeCustomFileTypeRule(_ rule: CustomFileTypeRule) {
        autoTraySettings.customRules.removeAll { $0.id == rule.id }
        persistAutoTraySettings()
    }

    func setDragExportRetentionMinutes(_ minutes: Int) {
        autoTraySettings.dragExportRetentionMinutes = AutoTraySettings.clampedDragExportRetentionMinutes(minutes)
        FileDragExportService.shared.setRetentionMinutes(autoTraySettings.dragExportRetentionMinutes)
        persistAutoTraySettings()
    }

    func closeWidget(_ widgetID: UUID) {
        guard let controllerIndex = panelControllers.firstIndex(where: { $0.widgetID == widgetID }) else {
            return
        }

        let controller = panelControllers.remove(at: controllerIndex)
        controller.close()
        flushState(includingVisibilitySync: true)
    }

    func removeScreenshotTrayIfEmpty(_ widgetID: UUID) {
        guard let controller = panelControllers.first(where: { $0.widgetID == widgetID }),
              controller.model.trayKind == .screenshots,
              controller.model.items.isEmpty else {
            return
        }

        closeWidget(widgetID)
    }

    func resolveFrame(
        for widgetID: UUID,
        proposedFrame: CGRect,
        preferredScreen: NSScreen?,
        mode: WidgetSnapMode
    ) -> CGRect? {
        guard let targetScreen = screen(for: proposedFrame, preferredScreen: preferredScreen) else {
            return nil
        }

        let occupiedFrames: [WidgetFrameSnapshot]
        let blockedFrames: [CGRect]
        if case .resizeFree = mode {
            occupiedFrames = []
            blockedFrames = []
        } else {
            let screenID = snapGridEngine.screenIdentifier(for: targetScreen)
            occupiedFrames = panelControllers.compactMap { controller -> WidgetFrameSnapshot? in
                guard controller.widgetID != widgetID,
                      let frame = controller.currentFrame,
                      let controllerScreen = screen(for: frame, preferredScreen: controller.currentScreen),
                      snapGridEngine.screenIdentifier(for: controllerScreen) == screenID else {
                    return nil
                }

                return WidgetFrameSnapshot(widgetID: controller.widgetID, frame: frame)
            }
            blockedFrames = systemWidgetReservationService.reservedFrames(on: targetScreen)
        }

        return snapGridEngine.resolveFrame(
            for: proposedFrame,
            on: targetScreen,
            occupied: occupiedFrames,
            blockedFrames: blockedFrames,
            mode: mode
        )
    }

    func initialFrame(for widgetID: UUID, panelSize: CGSize, preferredScreen: NSScreen?) -> CGRect? {
        guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }

        let clampedSize = metrics.clampedPanelSize(panelSize)
        let visibleFrame = screen.visibleFrame
        let minX = visibleFrame.minX + metrics.desktopInset
        let maxX = visibleFrame.maxX - metrics.desktopInset - clampedSize.width
        let minY = visibleFrame.minY + metrics.desktopInset
        let maxY = visibleFrame.maxY - metrics.desktopInset - clampedSize.height

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let horizontalStep = max(metrics.minimumItemWidth, 28)
        let verticalStep = max(metrics.idealItemHeight / 2, 28)

        var y = maxY
        while y >= minY {
            var x = minX
            while x <= maxX {
                let candidate = CGRect(
                    x: x,
                    y: y,
                    width: clampedSize.width,
                    height: clampedSize.height
                )
                if let resolvedFrame = resolveFrame(
                    for: widgetID,
                    proposedFrame: candidate,
                    preferredScreen: screen,
                    mode: .move
                ) {
                    return resolvedFrame
                }
                x += horizontalStep
            }
            y -= verticalStep
        }

        return nil
    }

    func screen(for frame: CGRect, preferredScreen: NSScreen?) -> NSScreen? {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        if let matchedScreen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(midpoint) }) {
            return matchedScreen
        }

        return preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func handleNewDesktopItem(_ url: URL) {
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard containsPinnedItem(at: standardizedURL) == false else {
            return
        }

        let settings = autoTraySettings
        if settings.collectDesktopScreenshots,
           DesktopFileClassifier.isScreenshot(standardizedURL) {
            addDesktopItem(standardizedURL, to: .screenshots)
            return
        }

        if settings.organizeNewDesktopFilesByDate {
            addDesktopItem(
                standardizedURL,
                to: .date(DesktopFileClassifier.dateKey(for: standardizedURL))
            )
            return
        }

        guard settings.organizeNewDesktopFiles else {
            return
        }

        let category = DesktopFileClassifier.category(for: standardizedURL, settings: settings)
        guard settings.enabledCategories.contains(category) else {
            return
        }

        addDesktopItem(standardizedURL, to: .auto(category))
    }

    private func addDesktopItem(_ url: URL, to trayKind: WidgetTrayKind) {
        guard let item = WidgetItem(url: url) else { return }

        let controller = controllerForTrayKind(trayKind) ?? createAutoTray(for: trayKind)
        guard controller.model.items.contains(where: { $0.url.standardizedFileURL.path == item.url.standardizedFileURL.path }) == false else {
            return
        }

        controller.model.items.append(item)
        desktopAutoTrayService.markKnown([url])
        widgetContentDidChange()
    }

    private func controllerForTrayKind(_ trayKind: WidgetTrayKind) -> DesktopWidgetPanelController? {
        panelControllers.first { $0.model.trayKind == trayKind }
    }

    private func createAutoTray(for trayKind: WidgetTrayKind) -> DesktopWidgetPanelController {
        let widget = WidgetModel(
            title: trayKind.title,
            panelSize: metrics.defaultPanelSize,
            backgroundOpacity: 0.78,
            displayMode: trayKind == .screenshots ? .grid : .list,
            trayKind: trayKind,
            items: []
        )
        return addWidgetController(for: widget)
    }

    private func containsPinnedItem(at url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return panelControllers.contains { controller in
            controller.model.items.contains { $0.url.standardizedFileURL.path == path }
        }
    }

    private func pruneMissingDesktopItems() {
        var removedAnyItem = false
        var emptyScreenshotWidgetIDs: [UUID] = []

        for controller in panelControllers {
            let removedFromController = controller.removeItems { item in
                guard isDirectDesktopChild(item.url) else { return false }
                return FileManager.default.fileExists(atPath: item.url.path) == false
            }

            guard removedFromController else { continue }
            removedAnyItem = true

            if controller.model.trayKind.isScreenshots,
               controller.model.items.isEmpty {
                emptyScreenshotWidgetIDs.append(controller.widgetID)
            }
        }

        for widgetID in emptyScreenshotWidgetIDs {
            removeScreenshotTrayIfEmpty(widgetID)
        }

        if removedAnyItem,
           emptyScreenshotWidgetIDs.isEmpty {
            flushState(includingVisibilitySync: true)
        }
    }

    private func isDirectDesktopChild(_ url: URL) -> Bool {
        guard let desktopDirectoryURL else { return false }
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalizedURL.deletingLastPathComponent().standardizedFileURL == desktopDirectoryURL
    }

    private var desktopDirectoryURL: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }

    private func persistAutoTraySettings() {
        autoTraySettingsStore.save(autoTraySettings)
    }
}
