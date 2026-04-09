import AppKit
import Darwin

@MainActor
final class DesktopSurfaceManager: ObservableObject {
    static let shared = DesktopSurfaceManager()

    @Published private(set) var panelControllers: [DesktopWidgetPanelController] = []
    @Published private(set) var isEditing = false

    private let snapGridEngine = SnapGridEngine()
    private let systemWidgetReservationService = SystemWidgetReservationService.shared
    private let desktopItemVisibilityService = DesktopItemVisibilityService.shared
    private let metrics = WidgetGridMetrics()
    private let persistenceStore = WidgetPersistenceStore.shared
    private var didBootstrap = false
    private var pendingStateSync: DispatchWorkItem?
    private var pendingVisibilitySync = false

    private init() {}

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        desktopItemVisibilityService.recoverInterruptedSessionIfNeeded()

        let restoredWidgets = persistenceStore.loadWidgets()
        if restoredWidgets.isEmpty {
            createEmptyWidget()
        } else {
            restoredWidgets.forEach(addWidgetController(for:))
        }

        let sessionID = UUID().uuidString
        desktopItemVisibilityService.beginSession(ownerPID: getpid(), sessionID: sessionID)
        desktopItemVisibilityService.launchGuardianIfPossible(sessionID: sessionID, ownerPID: getpid())
        scheduleStateSync(includingVisibilitySync: true)
    }

    func createEmptyWidget() {
        let nextIndex = panelControllers.count
        let widget = WidgetModel(
            title: nextIndex == 0 ? "Pinned Files" : "Pinned Files \(nextIndex + 1)",
            panelSize: metrics.defaultPanelSize,
            backgroundOpacity: 0.78,
            items: []
        )

        addWidgetController(for: widget)
        scheduleStateSync(includingVisibilitySync: true)
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
        persistenceStore.saveWidgets(widgets)
        guard includingVisibilitySync else { return }

        desktopItemVisibilityService.synchronizePinnedItems(widgets.flatMap { $0.items.map(\.url) })
    }

    func prepareForExit() {
        pendingStateSync?.cancel()
        pendingStateSync = nil
        pendingVisibilitySync = false

        persistenceStore.saveWidgets(currentWidgets())
        desktopItemVisibilityService.restoreManagedDesktopItems()
    }

    private func addWidgetController(for widget: WidgetModel) {
        let controller = DesktopWidgetPanelController(widgetModel: widget, surfaceManager: self)
        panelControllers.append(controller)
        controller.showWindow(nil)
        controller.updateEditMode(isEditing)
        controller.placeInitialWindow(on: NSScreen.main)
    }

    private func currentWidgets() -> [WidgetModel] {
        panelControllers.map(\.model)
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

    func resolveFrame(
        for widgetID: UUID,
        proposedFrame: CGRect,
        preferredScreen: NSScreen?,
        mode: WidgetSnapMode
    ) -> CGRect? {
        guard let targetScreen = screen(for: proposedFrame, preferredScreen: preferredScreen) else {
            return nil
        }

        let screenID = snapGridEngine.screenIdentifier(for: targetScreen)
        let occupiedFrames = panelControllers.compactMap { controller -> WidgetFrameSnapshot? in
            guard controller.widgetID != widgetID,
                  let frame = controller.currentFrame,
                  let controllerScreen = screen(for: frame, preferredScreen: controller.currentScreen),
                  snapGridEngine.screenIdentifier(for: controllerScreen) == screenID else {
                return nil
            }

            return WidgetFrameSnapshot(widgetID: controller.widgetID, frame: frame)
        }
        let blockedFrames = systemWidgetReservationService.reservedFrames(on: targetScreen)

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
}
