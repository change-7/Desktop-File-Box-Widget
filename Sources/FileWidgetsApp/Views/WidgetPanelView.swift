import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetPanelView: View {
    @ObservedObject var widgetModel: WidgetModel
    let isEditing: Bool
    let onSelect: (WidgetItem) -> Void
    let onOpen: (WidgetItem) -> Void
    let onRevealInFinder: (WidgetItem) -> Void
    let onRemoveItem: (WidgetItem) -> Void
    let onApplyPanelSize: (CGSize) -> Void
    let onRename: (String) -> Void
    let onBackgroundOpacityChange: (Double) -> Void
    let onDropItems: ([URL]) -> Void

    private let metrics = WidgetGridMetrics()
    @State private var isDropTargeted = false
    @State private var hoveredItemID: WidgetItem.ID?
    @State private var draftTitle = ""
    @State private var draftBackgroundOpacity = 0.78
    @State private var draftWidth = ""
    @State private var draftHeight = ""
    @FocusState private var focusedField: SizeField?

    private enum SizeField {
        case width
        case height
    }

    private var effectiveBackgroundOpacity: Double {
        isEditing ? draftBackgroundOpacity : widgetModel.backgroundOpacity
    }

    var body: some View {
        GeometryReader { geometry in
            let panelSize = resolvedPanelSize(from: geometry.size)
            let itemLayout = metrics.itemLayout(
                for: panelSize,
                itemCount: widgetModel.items.count,
                isEditing: isEditing
            )
            let gridColumns = Array(
                repeating: GridItem(.fixed(itemLayout.itemSize.width), spacing: metrics.itemSpacing),
                count: itemLayout.columns
            )

            ZStack {
                RoundedRectangle(cornerRadius: metrics.panelCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(effectiveBackgroundOpacity))
                    .padding(metrics.outerPadding)

                RoundedRectangle(cornerRadius: metrics.panelCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(effectiveBackgroundOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.panelCornerRadius, style: .continuous)
                            .strokeBorder(
                                .white.opacity((0.14 + (effectiveBackgroundOpacity * 0.12)) * effectiveBackgroundOpacity),
                                lineWidth: 1
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.panelCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity((0.06 + (effectiveBackgroundOpacity * 0.08)) * effectiveBackgroundOpacity),
                                        .clear,
                                        .black.opacity((0.05 + (effectiveBackgroundOpacity * 0.06)) * effectiveBackgroundOpacity),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(metrics.outerPadding)

                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    header(panelSize: panelSize)

                    if widgetModel.items.isEmpty {
                        EmptyWidgetDropZone(isEditing: isEditing, isDropTargeted: isDropTargeted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: metrics.itemSpacing) {
                            ForEach(widgetModel.items) { item in
                                let baseCell = WidgetItemCell(
                                    item: item,
                                    itemSize: itemLayout.itemSize,
                                    metrics: metrics,
                                    isSelected: widgetModel.selectedItemID == item.id,
                                    removalStyle: isEditing ? .remove : .unpin,
                                    showsRemoveButton: isEditing || hoveredItemID == item.id,
                                    onRemove: { onRemoveItem(item) }
                                )
                                    .contentShape(RoundedRectangle(cornerRadius: metrics.itemCornerRadius, style: .continuous))
                                    .onHover { isHovering in
                                        if isHovering {
                                            hoveredItemID = item.id
                                        } else if hoveredItemID == item.id {
                                            hoveredItemID = nil
                                        }
                                    }
                                    .contextMenu {
                                        if !isEditing {
                                            Button("Open") {
                                                onOpen(item)
                                            }
                                        }

                                        Button("Reveal in Finder") {
                                            onRevealInFinder(item)
                                        }

                                        Divider()

                                        Button(isEditing ? "Remove from Widget" : "Unpin from Widget") {
                                            onRemoveItem(item)
                                        }
                                    }

                                if isEditing {
                                    baseCell
                                } else {
                                    baseCell
                                        .onTapGesture {
                                            onSelect(item)
                                        }
                                        .onTapGesture(count: 2) {
                                            onOpen(item)
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .padding(metrics.panelContentInset)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: dropTargetBinding) { providers in
            guard !isEditing else { return false }
            Task {
                let urls = await loadDroppedURLs(from: providers)
                guard !urls.isEmpty else { return }
                await MainActor.run {
                    onDropItems(urls)
                }
            }
            return providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        }
        .onAppear {
            syncEditorStateFromModel()
        }
        .onChange(of: widgetModel.id) { _, _ in
            syncEditorStateFromModel()
        }
        .onChange(of: widgetModel.title) { _, newValue in
            if !isEditing {
                draftTitle = newValue
            }
        }
        .onChange(of: widgetModel.backgroundOpacity) { _, newValue in
            if !isEditing {
                draftBackgroundOpacity = newValue
            }
        }
        .onChange(of: widgetModel.panelSize) { _, newValue in
            guard focusedField == nil else { return }
            syncSizeDraft(from: newValue)
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                syncEditorStateFromModel()
            } else {
                focusedField = nil
            }
        }
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { !isEditing && isDropTargeted },
            set: { isDropTargeted = !isEditing && $0 }
        )
    }

    private func header(panelSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: isEditing ? 6 : 4) {
            if isEditing {
                HStack(alignment: .center, spacing: 8) {
                    TextField(
                        "Widget Name",
                        text: Binding(
                            get: { draftTitle },
                            set: {
                                draftTitle = $0
                                onRename($0)
                            }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 4) {
                        sizeField(title: "W", text: $draftWidth, field: .width)
                        Text("×")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        sizeField(title: "H", text: $draftHeight, field: .height)
                    }

                    Button("Apply") {
                        applyDraftSize()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.10), in: Capsule())
                    .disabled(parsedDraftWidth == nil || parsedDraftHeight == nil)
                }

                HStack(spacing: 8) {
                    Text("Opacity")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { draftBackgroundOpacity },
                            set: {
                                draftBackgroundOpacity = $0
                                onBackgroundOpacityChange($0)
                            }
                        ),
                        in: 0.0...1.0
                    )
                    .tint(.white.opacity(0.85))

                    Text("\(Int(widgetModel.backgroundOpacity * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            } else {
                Text(widgetModel.title)
                    .font(.headline.weight(.semibold))
            }
        }
        .frame(minHeight: metrics.titleAreaHeight, alignment: .top)
    }

    private func sizeField(title: String, text: Binding<String>, field: SizeField) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.caption2.monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focused($focusedField, equals: field)
            .onSubmit {
                applyDraftSize()
            }
    }

    private var parsedDraftWidth: CGFloat? {
        parseDimension(draftWidth)
    }

    private var parsedDraftHeight: CGFloat? {
        parseDimension(draftHeight)
    }

    private func applyDraftSize() {
        guard let width = parsedDraftWidth,
              let height = parsedDraftHeight else {
            return
        }

        focusedField = nil
        onApplyPanelSize(CGSize(width: width, height: height))
    }

    private func parseDimension(_ value: String) -> CGFloat? {
        guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed.isFinite,
              parsed > 0 else {
            return nil
        }

        return CGFloat(parsed)
    }

    private func syncEditorStateFromModel() {
        draftTitle = widgetModel.title
        draftBackgroundOpacity = widgetModel.backgroundOpacity
        syncSizeDraft(from: widgetModel.panelSize)
    }

    private func syncSizeDraft(from size: CGSize) {
        draftWidth = String(Int(size.width.rounded()))
        draftHeight = String(Int(size.height.rounded()))
    }

    private func resolvedPanelSize(from liveSize: CGSize) -> CGSize {
        guard liveSize.width > 1, liveSize.height > 1 else {
            return metrics.clampedPanelSize(widgetModel.panelSize)
        }

        return metrics.clampedPanelSize(liveSize)
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadDroppedURL(from: provider) {
                urls.append(url.standardizedFileURL)
            }
        }
        return urls
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let resolvedURL: URL?
                switch item {
                case let url as URL:
                    resolvedURL = url
                case let nsURL as NSURL:
                    resolvedURL = nsURL as URL
                case let text as String:
                    resolvedURL = URL(string: text)
                case let data as Data:
                    resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                default:
                    resolvedURL = nil
                }

                continuation.resume(returning: resolvedURL?.isFileURL == true ? resolvedURL : nil)
            }
        }
    }
}

private struct EmptyWidgetDropZone: View {
    let isEditing: Bool
    let isDropTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1.4, dash: [8, 8])
            )
            .foregroundStyle(isDropTargeted ? .white.opacity(0.85) : .white.opacity(0.28))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isDropTargeted ? .white.opacity(0.12) : .white.opacity(0.04))
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: isEditing ? "arrow.up.and.down.and.arrow.left.and.right" : "tray.and.arrow.down.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))

                    if !isEditing {
                        Text("Drop files or folders here")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.94))
                    }

                    Text(isEditing
                        ? "Drag to move. Size and opacity are above."
                        : "Create an empty widget, then drag items from Finder to pin them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .padding(24)
            }
    }
}

private struct WidgetItemCell: View {
    enum RemovalStyle {
        case remove
        case unpin
    }

    let item: WidgetItem
    let itemSize: CGSize
    let metrics: WidgetGridMetrics
    let isSelected: Bool
    let removalStyle: RemovalStyle
    let showsRemoveButton: Bool
    let onRemove: () -> Void

    var body: some View {
        let titleFontSize: CGFloat = 11
        let subtitleFontSize: CGFloat = 9
        let showsSubtitle = itemSize.height >= 96 && itemSize.width >= 78
        let titleLineLimit = showsSubtitle ? 1 : 2
        let iconFontSize = max(16, min(28, min(itemSize.width, itemSize.height) * 0.34))
        let verticalSpacing = showsSubtitle ? max(4, min(8, itemSize.height * 0.08)) : 3
        let cornerRadius = max(10, min(metrics.itemCornerRadius, min(itemSize.width, itemSize.height) * 0.2))

        VStack(alignment: .center, spacing: verticalSpacing) {
            WidgetItemArtwork(
                item: item,
                itemSize: itemSize,
                iconFontSize: iconFontSize,
                cornerRadius: cornerRadius,
                metrics: metrics,
                isSelected: isSelected
            )
            .frame(width: itemSize.width, height: metrics.iconContainerHeight(for: itemSize))

            VStack(spacing: 1) {
                Text(item.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .lineLimit(titleLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)

                if showsSubtitle {
                    Text(item.subtitle)
                        .font(.system(size: subtitleFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: showsSubtitle ? 15 : 28,
                alignment: .top
            )
        }
        .frame(width: itemSize.width, height: itemSize.height, alignment: .top)
        .overlay(alignment: .topTrailing) {
            if showsRemoveButton {
                RemoveItemButton(style: removalStyle, action: onRemove)
                    .padding(4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsRemoveButton)
    }
}

private struct RemoveItemButton: View {
    let style: WidgetItemCell.RemovalStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial.opacity(0.94))
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                    }

                Image(systemName: style == .remove ? "minus" : "pin.slash.fill")
                    .font(.system(size: style == .remove ? 11 : 10, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(style == .remove ? "Remove from Widget" : "Unpin from Widget")
    }
}

private struct WidgetItemArtwork: View {
    @StateObject private var artworkLoader: WidgetArtworkLoader

    let item: WidgetItem
    let itemSize: CGSize
    let iconFontSize: CGFloat
    let cornerRadius: CGFloat
    let metrics: WidgetGridMetrics
    let isSelected: Bool

    init(
        item: WidgetItem,
        itemSize: CGSize,
        iconFontSize: CGFloat,
        cornerRadius: CGFloat,
        metrics: WidgetGridMetrics,
        isSelected: Bool
    ) {
        self.item = item
        self.itemSize = itemSize
        self.iconFontSize = iconFontSize
        self.cornerRadius = cornerRadius
        self.metrics = metrics
        self.isSelected = isSelected
        _artworkLoader = StateObject(
            wrappedValue: WidgetArtworkLoader(url: item.url, prefersImagePreview: item.isImage)
        )
    }

    var body: some View {
        let artworkSize = artworkFrameSize

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? .white.opacity(0.18) : .white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? .white.opacity(0.45) : .white.opacity(0.0),
                            lineWidth: 1
                        )
                }

            if let artwork = artworkLoader.artwork {
                if artworkLoader.displaysImagePreview {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: artworkSize.width,
                            height: artworkSize.height
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: artworkSize.width, height: artworkSize.height)
                }
            } else {
                Image(systemName: item.kind == .folder ? "folder.fill" : "doc.fill")
                    .font(.system(size: iconFontSize, weight: .medium))
                    .foregroundStyle(item.kind == .folder ? .yellow : .white)
                    .frame(width: artworkSize.width, height: artworkSize.height)
            }
        }
        .frame(width: itemSize.width, height: metrics.iconContainerHeight(for: itemSize))
        .task(id: item.url) {
            artworkLoader.loadIfNeeded()
        }
    }

    private var artworkFrameSize: CGSize {
        let containerHeight = metrics.iconContainerHeight(for: itemSize)
        let side = min(itemSize.width, containerHeight)
        return CGSize(width: side, height: side)
    }
}

@MainActor
private final class WidgetArtworkLoader: ObservableObject {
    @Published private(set) var artwork: NSImage?
    @Published private(set) var displaysImagePreview = false

    private let url: URL
    private let prefersImagePreview: Bool
    private var hasLoaded = false

    init(url: URL, prefersImagePreview: Bool) {
        self.url = url
        self.prefersImagePreview = prefersImagePreview
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let cacheKey = url as NSURL
        if prefersImagePreview,
           let cachedPreview = WidgetImagePreviewCache.shared.object(forKey: cacheKey) {
            artwork = cachedPreview
            displaysImagePreview = true
            return
        }

        if let cachedIcon = WidgetFileIconCache.shared.object(forKey: cacheKey) {
            artwork = cachedIcon
            displaysImagePreview = false
            return
        }

        if prefersImagePreview {
            let fileURL = url
            Task.detached(priority: .userInitiated) {
                let imageData = try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
                await MainActor.run {
                    guard let imageData,
                          let preview = NSImage(data: imageData) else {
                        self.loadFallbackIcon()
                        return
                    }

                    WidgetImagePreviewCache.shared.setObject(preview, forKey: fileURL as NSURL)
                    self.artwork = preview
                    self.displaysImagePreview = true
                }
            }
        } else {
            loadFallbackIcon()
        }
    }

    private func loadFallbackIcon() {
        let cacheKey = url as NSURL
        if let cachedIcon = WidgetFileIconCache.shared.object(forKey: cacheKey) {
            artwork = cachedIcon
            displaysImagePreview = false
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        WidgetFileIconCache.shared.setObject(icon, forKey: cacheKey)
        artwork = icon
        displaysImagePreview = false
    }
}

@MainActor
private enum WidgetImagePreviewCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 128
        return cache
    }()
}

@MainActor
private enum WidgetFileIconCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        return cache
    }()
}
