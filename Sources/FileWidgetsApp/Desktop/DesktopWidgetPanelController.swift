import AppKit
import FileWidgetsSupport
import QuickLookUI
import SwiftUI

@MainActor
final class DesktopWidgetPanelController: NSWindowController, NSWindowDelegate {
    private let gridMetrics = WidgetGridMetrics()
    private unowned let surfaceManager: DesktopSurfaceManager
    private let widgetModel: WidgetModel
    private var isEditing = false
    private var isResizeDragActive = false
    private var isApplyingFrameUpdate = false
    private var suppressMoveResolutionUntil = Date.distantPast
    private var hostingView: NSHostingView<WidgetPanelView>?
    private let quickLookKeyMonitor = QuickLookKeyMonitorToken()

    var widgetID: UUID { widgetModel.id }
    var model: WidgetModel { widgetModel }
    var currentFrame: CGRect? { window?.frame ?? widgetModel.frame }
    var currentScreen: NSScreen? { window?.screen }

    init(widgetModel: WidgetModel, surfaceManager: DesktopSurfaceManager) {
        self.surfaceManager = surfaceManager
        self.widgetModel = widgetModel

        let panel = DesktopPanel(
            contentRect: CGRect(origin: .zero, size: gridMetrics.clampedPanelSize(widgetModel.panelSize)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        self.widgetModel.panelSize = gridMetrics.clampedPanelSize(widgetModel.panelSize)
        configureWindow(panel)
        installQuickLookKeyMonitor()
        configureContent(using: panel)
        updateEditMode(surfaceManager.isEditing)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        quickLookKeyMonitor.invalidate()
    }

    override func close() {
        tearDownWindowReferences()
        super.close()
    }

    func placeInitialWindow(on screen: NSScreen?) {
        guard let window else { return }

        if let storedFrame = widgetModel.frame,
           let resolvedStoredFrame = surfaceManager.resolveFrame(
               for: widgetID,
               proposedFrame: storedFrame,
               preferredScreen: screen ?? window.screen,
               mode: .move
           ) {
            applyResolvedFrame(resolvedStoredFrame, display: false, animate: false)
            return
        }

        if let resolvedInitialFrame = surfaceManager.initialFrame(
            for: widgetID,
            panelSize: widgetModel.panelSize,
            preferredScreen: screen ?? window.screen ?? NSScreen.main
        ) {
            applyResolvedFrame(resolvedInitialFrame, display: false, animate: false)
            return
        }

        let targetScreen = screen ?? window.screen ?? NSScreen.main
        let screenFrame = (targetScreen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let fallbackFrame = CGRect(
            x: screenFrame.minX + gridMetrics.desktopInset,
            y: screenFrame.maxY - widgetModel.panelSize.height - gridMetrics.desktopInset,
            width: widgetModel.panelSize.width,
            height: widgetModel.panelSize.height
        )
        applyResolvedFrame(fallbackFrame, display: false, animate: false)
    }

    private func configureWindow(_ panel: DesktopPanel) {
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        panel.edgeResizeFrameChanged = { [weak self] frame in
            self?.applyInteractiveResizeFrame(frame)
        }
        panel.edgeResizeActiveChanged = { [weak self] isActive in
            self?.setResizeDragActive(isActive)
        }
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.acceptsMouseMovedEvents = true
    }

    private func tearDownWindowReferences() {
        closeQuickLookIfNeeded()
        quickLookKeyMonitor.invalidate()
        if let panel = window as? DesktopPanel {
            panel.keyDownHandler = nil
            panel.edgeResizeFrameChanged = nil
            panel.edgeResizeActiveChanged = nil
            panel.isEdgeResizeEnabled = false
        }
        window?.delegate = nil
        window?.contentView = nil
        hostingView = nil
    }

    private func installQuickLookKeyMonitor() {
        guard quickLookKeyMonitor.monitor == nil else { return }

        quickLookKeyMonitor.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandleQuickLookKeyEvent(event) else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    func updateEditMode(_ isEditing: Bool) {
        self.isEditing = isEditing
        isResizeDragActive = false
        guard let window else { return }

        window.isMovableByWindowBackground = isEditing && !isResizeDragActive
        (window as? DesktopPanel)?.isEdgeResizeEnabled = isEditing
        if isEditing {
            widgetModel.selectedItemID = nil
            closeQuickLookIfNeeded()
        }
        updateRootView()
    }

    private func configureContent(using panel: NSWindow) {
        let hostingView = NSHostingView(rootView: makeRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = hostingView
        self.hostingView = hostingView
    }

    private func updateRootView() {
        hostingView?.rootView = makeRootView()
    }

    private func makeRootView() -> WidgetPanelView {
        WidgetPanelView(
            widgetModel: widgetModel,
            isEditing: isEditing,
            onToggleEditLayout: { [weak self] in self?.toggleEditLayout() },
            onSetDisplayMode: { [weak self] displayMode in self?.setDisplayMode(displayMode) },
            onSelect: { [weak self] item in self?.selectItem(item) },
            onOpen: { [weak self] item in self?.openItem(item) },
            onRevealInFinder: { [weak self] item in self?.revealInFinder(item) },
            onRemoveItem: { [weak self] item in self?.removeItemFromWidget(item) },
            onCopyAllItems: { [weak self] in self?.copyAllItemsToPasteboard() },
            onMoveItemToTrash: { [weak self] item in self?.moveItemToTrash(item) },
            onMoveAllItemsToTrash: { [weak self] in self?.moveAllItemsToTrash() },
            onApplyPanelSize: { [weak self] size in self?.updatePanelSize(size) },
            onRename: { [weak self] title in self?.updateTitle(title) },
            onBackgroundOpacityChange: { [weak self] opacity in self?.updateBackgroundOpacity(opacity) },
            onBackgroundColorChange: { [weak self] color in self?.updateBackgroundColor(color) },
            onDropItems: { [weak self] urls in self?.addDroppedItems(urls) },
            onCloseTray: { [weak self] in
                guard let self else { return }
                self.surfaceManager.closeWidget(self.widgetID)
            }
        )
    }

    private func toggleEditLayout() {
        surfaceManager.toggleEditMode()
    }

    private func setDisplayMode(_ displayMode: WidgetDisplayMode) {
        guard widgetModel.displayMode != displayMode else { return }
        widgetModel.displayMode = displayMode
        surfaceManager.widgetAppearanceDidChange()
    }

    private func openItem(_ item: WidgetItem) {
        guard !isEditing else { return }
        NSWorkspace.shared.open(item.url)
    }

    private func revealInFinder(_ item: WidgetItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func selectItem(_ item: WidgetItem) {
        guard !isEditing else { return }

        widgetModel.selectedItemID = item.id
        if let previewPanel = activeQuickLookPanelOwnedByController() {
            previewPanel.reloadData()
            previewPanel.currentPreviewItemIndex = 0
            previewPanel.refreshCurrentPreviewItem()
            return
        }

        window?.makeKey()
    }

    private func addDroppedItems(_ urls: [URL]) {
        guard !isEditing,
              widgetModel.trayKind.isScreenshots == false else {
            return
        }

        var existingPaths = Set(widgetModel.items.map { $0.url.standardizedFileURL.path })
        let newItems = urls.compactMap { WidgetItem(url: $0) }
        let uniqueItems = newItems.filter { item in
            existingPaths.insert(item.url.standardizedFileURL.path).inserted
        }
        guard !uniqueItems.isEmpty else { return }

        widgetModel.items.append(contentsOf: uniqueItems)
        surfaceManager.widgetContentDidChange()
    }

    private func removeItemFromWidget(_ item: WidgetItem) {
        guard let existingIndex = widgetModel.items.firstIndex(of: item) else { return }

        widgetModel.items.remove(at: existingIndex)
        if widgetModel.selectedItemID == item.id {
            widgetModel.selectedItemID = nil
            closeQuickLookIfNeeded()
        }
        surfaceManager.flushState()
    }

    @discardableResult
    func removeItems(where shouldRemove: (WidgetItem) -> Bool) -> Bool {
        let removedItemIDs = Set(widgetModel.items.filter(shouldRemove).map(\.id))
        guard removedItemIDs.isEmpty == false else { return false }

        widgetModel.items.removeAll { removedItemIDs.contains($0.id) }
        if let selectedItemID = widgetModel.selectedItemID,
           removedItemIDs.contains(selectedItemID) {
            widgetModel.selectedItemID = nil
            closeQuickLookIfNeeded()
        }
        return true
    }

    private func copyAllItemsToPasteboard() {
        let urls = widgetModel.items.map(\.url)
        guard urls.isEmpty == false else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func moveItemToTrash(_ item: WidgetItem) {
        moveItemsToTrash([item])
    }

    private func moveAllItemsToTrash() {
        let eligibleItems = widgetModel.items.filter(isTrashableScreenshotItem)
        guard eligibleItems.isEmpty == false,
              confirmMoveAllScreenshotsToTrash() else {
            return
        }
        moveItemsToTrash(eligibleItems)
    }

    private func confirmMoveAllScreenshotsToTrash() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.moveAllScreenshotsAlertTitle
        alert.informativeText = L10n.moveAllScreenshotsAlertMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.moveToTrash)
        alert.addButton(withTitle: L10n.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func moveItemsToTrash(_ items: [WidgetItem]) {
        guard widgetModel.trayKind.isScreenshots,
              items.isEmpty == false else {
            return
        }

        var removedItemIDs = Set<WidgetItem.ID>()
        for item in items {
            guard isTrashableScreenshotItem(item) else {
                continue
            }

            if FileManager.default.fileExists(atPath: item.url.path) == false {
                removedItemIDs.insert(item.id)
                continue
            }

            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                removedItemIDs.insert(item.id)
            } catch {
                continue
            }
        }

        guard removedItemIDs.isEmpty == false else { return }

        widgetModel.items.removeAll { removedItemIDs.contains($0.id) }
        if let selectedItemID = widgetModel.selectedItemID,
           removedItemIDs.contains(selectedItemID) {
            widgetModel.selectedItemID = nil
            closeQuickLookIfNeeded()
        }

        if widgetModel.items.isEmpty {
            surfaceManager.removeScreenshotTrayIfEmpty(widgetID)
        } else {
            surfaceManager.widgetContentDidChange()
        }
    }

    private func isTrashableScreenshotItem(_ item: WidgetItem) -> Bool {
        guard widgetModel.trayKind.isScreenshots,
              item.kind == .file,
              isDirectDesktopChild(item.url),
              DesktopFileClassifier.isScreenshot(item.url),
              let expectedIdentity = item.fileIdentity,
              let currentIdentity = DesktopVisibilitySupport.fileIdentity(for: item.url),
              currentIdentity == expectedIdentity else {
            return false
        }

        return true
    }

    private func isDirectDesktopChild(_ url: URL) -> Bool {
        guard let desktopDirectoryURL else { return false }
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalizedURL.deletingLastPathComponent().standardizedFileURL == desktopDirectoryURL
    }

    private var desktopDirectoryURL: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }

    private func updateTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        widgetModel.title = trimmed.isEmpty ? L10n.untitledWidget : trimmed
        surfaceManager.widgetAppearanceDidChange()
    }

    private func updateBackgroundOpacity(_ opacity: Double) {
        widgetModel.backgroundOpacity = min(max(opacity, 0.0), 1.0)
        surfaceManager.widgetAppearanceDidChange()
    }

    private func updateBackgroundColor(_ color: WidgetBackgroundColor?) {
        widgetModel.backgroundColor = color
        surfaceManager.widgetAppearanceDidChange()
    }

    private func updatePanelSize(_ size: CGSize) {
        guard isEditing, let window else { return }

        let clampedSize = gridMetrics.clampedPanelSize(size)
        let baseFrame = window.frame
        let proposedFrame = CGRect(
            x: baseFrame.minX,
            y: baseFrame.maxY - clampedSize.height,
            width: clampedSize.width,
            height: clampedSize.height
        )

        _ = resolveAndApplyFrame(
            proposedFrame: proposedFrame,
            preferredScreen: window.screen,
            mode: .resizeBottomTrailing,
            restoreOnFailure: true,
            commitToModel: true
        )
    }

    private func applyInteractiveResizeFrame(_ frame: CGRect) {
        guard isEditing, let window else { return }

        let resolvedFrame = clampedInteractiveResizeFrame(frame, preferredScreen: window.screen)
        guard framesDiffer(window.frame, resolvedFrame) else { return }

        suppressMoveResolutionBriefly()
        isApplyingFrameUpdate = true
        window.setFrame(resolvedFrame, display: true, animate: false)
        isApplyingFrameUpdate = false
    }

    private func setResizeDragActive(_ isActive: Bool) {
        let wasActive = isResizeDragActive
        isResizeDragActive = isActive
        window?.isMovableByWindowBackground = isEditing && !isResizeDragActive

        if wasActive, !isActive {
            commitCurrentInteractiveResizeFrame()
        }
    }

    private func commitCurrentInteractiveResizeFrame() {
        guard isEditing, let window else { return }

        suppressMoveResolutionBriefly()
        _ = resolveAndApplyFrame(
            proposedFrame: window.frame,
            preferredScreen: window.screen,
            mode: .resizeFree,
            restoreOnFailure: false,
            commitToModel: true
        )
    }

    private func clampedInteractiveResizeFrame(_ frame: CGRect, preferredScreen: NSScreen?) -> CGRect {
        let targetScreen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? frame
        let clampedSize = gridMetrics.clampedPanelSize(frame.size)
        let maxX = max(screenFrame.minX, screenFrame.maxX - clampedSize.width)
        let maxY = max(screenFrame.minY, screenFrame.maxY - clampedSize.height)

        return CGRect(
            x: min(max(frame.minX, screenFrame.minX), maxX),
            y: min(max(frame.minY, screenFrame.minY), maxY),
            width: clampedSize.width,
            height: clampedSize.height
        )
    }

    private func suppressMoveResolutionBriefly() {
        suppressMoveResolutionUntil = Date().addingTimeInterval(0.25)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isEditing,
              event.type == .keyDown else {
            return false
        }

        switch event.keyCode {
        case 123:
            moveSelection(.left)
            return true
        case 124:
            moveSelection(.right)
            return true
        case 125:
            moveSelection(.down)
            return true
        case 126:
            moveSelection(.up)
            return true
        case 36, 76:
            guard let selectedItem else { return false }
            openItem(selectedItem)
            return true
        case 49:
            guard selectedItem != nil else { return false }
            toggleQuickLook()
            return true
        default:
            return false
        }
    }

    private var selectedItem: WidgetItem? {
        guard let selectedItemID = widgetModel.selectedItemID else {
            return nil
        }

        return widgetModel.items.first(where: { $0.id == selectedItemID })
    }

    private func toggleQuickLook() {
        if let previewPanel = activeQuickLookPanelOwnedByController() {
            previewPanel.orderOut(nil)
            window?.makeKey()
            return
        }

        let previewPanel = QLPreviewPanel.shared()
        previewPanel?.reloadData()
        previewPanel?.currentPreviewItemIndex = 0
        previewPanel?.makeKeyAndOrderFront(nil)
    }

    private func currentQuickLookPanelIfVisible() -> QLPreviewPanel? {
        guard QLPreviewPanel.sharedPreviewPanelExists() else {
            return nil
        }

        let previewPanel = QLPreviewPanel.shared()
        return previewPanel?.isVisible == true ? previewPanel : nil
    }

    private func activeQuickLookPanelOwnedByController() -> QLPreviewPanel? {
        guard let previewPanel = currentQuickLookPanelIfVisible(),
              quickLookPanelBelongsToController(previewPanel) else {
            return nil
        }

        return previewPanel
    }

    private func closeQuickLookIfNeeded() {
        activeQuickLookPanelOwnedByController()?.orderOut(nil)
    }

    private func shouldHandleQuickLookKeyEvent(_ event: NSEvent) -> Bool {
        guard !isEditing,
              Self.quickLookHandledKeyCodes.contains(event.keyCode),
              let previewPanel = activeQuickLookPanelOwnedByController(),
              previewPanel.isKeyWindow else {
            return false
        }

        return true
    }

    private func quickLookPanelBelongsToController(_ previewPanel: QLPreviewPanel) -> Bool {
        let dataSourceOwner = previewPanel.dataSource as AnyObject?
        let delegateOwner = previewPanel.delegate as AnyObject?
        return dataSourceOwner === self || delegateOwner === self
    }

    private func moveSelection(_ direction: SelectionDirection) {
        guard widgetModel.items.isEmpty == false else { return }

        let itemCount = widgetModel.items.count
        let lastIndex = itemCount - 1
        let columns: Int
        if widgetModel.displayMode == .list {
            columns = max(
                gridMetrics.listLayout(
                    for: widgetModel.panelSize,
                    itemCount: itemCount,
                    isEditing: false
                ).columns,
                1
            )
        } else {
            let itemLayout = gridMetrics.itemLayout(
                for: widgetModel.panelSize,
                itemCount: itemCount,
                isEditing: false
            )
            columns = max(itemLayout.columns, 1)
        }
        let currentIndex = widgetModel.selectedItemID.flatMap { selectedID in
            widgetModel.items.firstIndex(where: { $0.id == selectedID })
        }

        let nextIndex: Int
        if let currentIndex {
            let currentRow = currentIndex / columns
            let currentColumn = currentIndex % columns

            func indexFor(row: Int, column: Int) -> Int {
                let requestedIndex = (row * columns) + column
                if requestedIndex <= lastIndex {
                    return requestedIndex
                }

                let lastIndexInRow = min(lastIndex, (row * columns) + (columns - 1))
                return max(row * columns, lastIndexInRow)
            }

            switch direction {
            case .left:
                nextIndex = max(0, currentIndex - 1)
            case .right:
                nextIndex = min(lastIndex, currentIndex + 1)
            case .up:
                let targetRow = max(0, currentRow - 1)
                nextIndex = indexFor(row: targetRow, column: currentColumn)
            case .down:
                let lastRow = max(0, (itemCount - 1) / columns)
                let targetRow = min(lastRow, currentRow + 1)
                nextIndex = indexFor(row: targetRow, column: currentColumn)
            }
        } else {
            nextIndex = 0
        }

        selectItem(widgetModel.items[nextIndex])
    }

    @discardableResult
    private func resolveAndApplyFrame(
        proposedFrame: CGRect? = nil,
        preferredScreen: NSScreen? = nil,
        mode: WidgetSnapMode = .move,
        display: Bool = true,
        animate: Bool = false,
        restoreOnFailure: Bool = true,
        commitToModel: Bool = true
    ) -> Bool {
        guard let window else { return false }

        let frameToResolve = proposedFrame ?? window.frame
        guard let resolvedFrame = surfaceManager.resolveFrame(
            for: widgetModel.id,
            proposedFrame: frameToResolve,
            preferredScreen: preferredScreen ?? window.screen,
            mode: mode
        ) else {
            if restoreOnFailure {
                restoreStoredFrame(display: display, animate: animate)
            }
            return false
        }

        applyResolvedFrame(resolvedFrame, display: display, animate: animate, commitToModel: commitToModel)
        return true
    }

    private func applyResolvedFrame(_ frame: CGRect, display: Bool, animate: Bool, commitToModel: Bool = true) {
        guard let window else { return }
        let normalizedFrame = CGRect(
            x: frame.minX.rounded(),
            y: frame.minY.rounded(),
            width: frame.width.rounded(),
            height: frame.height.rounded()
        )
        if commitToModel {
            widgetModel.frame = normalizedFrame
            widgetModel.panelSize = normalizedFrame.size
            surfaceManager.widgetAppearanceDidChange()
        }

        guard framesDiffer(window.frame, normalizedFrame) else { return }

        isApplyingFrameUpdate = true
        window.setFrame(normalizedFrame, display: display, animate: animate)
        isApplyingFrameUpdate = false
    }

    private func restoreStoredFrame(display: Bool, animate: Bool) {
        guard let fallbackFrame = widgetModel.frame else {
            return
        }

        applyResolvedFrame(fallbackFrame, display: display, animate: animate)
    }

    private func framesDiffer(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) > 0.5
            || abs(lhs.origin.y - rhs.origin.y) > 0.5
            || abs(lhs.size.width - rhs.size.width) > 0.5
            || abs(lhs.size.height - rhs.size.height) > 0.5
    }

    func windowDidMove(_ notification: Notification) {
        guard isEditing,
              !isResizeDragActive,
              !isApplyingFrameUpdate,
              Date() >= suppressMoveResolutionUntil else {
            return
        }
        _ = resolveAndApplyFrame(mode: .move)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard !isResizeDragActive,
              !isApplyingFrameUpdate,
              Date() >= suppressMoveResolutionUntil else {
            return
        }
        _ = resolveAndApplyFrame(preferredScreen: window?.screen, mode: .move)
    }
}

private enum SelectionDirection {
    case left
    case right
    case up
    case down
}

private extension DesktopWidgetPanelController {
    static let quickLookHandledKeyCodes: Set<UInt16> = [36, 49, 76, 123, 124, 125, 126]

    nonisolated static func runOnMainActor<T: Sendable>(
        fallback: @autoclosure () -> T,
        _ body: @MainActor () -> T
    ) -> T {
        guard Thread.isMainThread else {
            return fallback()
        }

        return MainActor.assumeIsolated(body)
    }
}

private final class QuickLookKeyMonitorToken: @unchecked Sendable {
    var monitor: Any?

    func invalidate() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

extension DesktopWidgetPanelController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        Self.runOnMainActor(fallback: false) {
            !isEditing && selectedItem != nil
        }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        Self.runOnMainActor(fallback: ()) {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        Self.runOnMainActor(fallback: ()) {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        Self.runOnMainActor(fallback: 0) {
            selectedItem == nil ? 0 : 1
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        Self.runOnMainActor(fallback: nil) {
            selectedItem?.url as NSURL?
        }
    }
}
