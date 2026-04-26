import CoreGraphics
import Foundation
import OSLog

@MainActor
final class WidgetPersistenceStore {
    static let shared = WidgetPersistenceStore()

    private let fileManager = FileManager.default
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.desktopfileboxwidget.app",
        category: "WidgetPersistence"
    )
    private let storeURL: URL

    private init() {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryURL = applicationSupportURL
            .appendingPathComponent("FileWidgets", isDirectory: true)
        self.storeURL = directoryURL.appendingPathComponent("widgets.json", isDirectory: false)
    }

    func loadWidgets() -> [WidgetModel] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let persistedState = try JSONDecoder().decode(PersistedWidgetState.self, from: data)

            return persistedState.widgets.map { snapshot in
                WidgetModel(
                    id: snapshot.id,
                    title: snapshot.title,
                    panelSize: CGSize(
                        width: snapshot.panelWidth,
                        height: snapshot.panelHeight
                    ),
                    backgroundOpacity: snapshot.backgroundOpacity,
                    displayMode: snapshot.displayMode,
                    items: snapshot.items.compactMap(loadItem(from:)),
                    frame: snapshot.frame.map {
                        CGRect(
                            x: $0.x,
                            y: $0.y,
                            width: $0.width,
                            height: $0.height
                        )
                    }
                )
            }
        } catch {
            logger.error(
                "Failed to load widget state from \(self.storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func saveWidgets(_ widgets: [WidgetModel]) {
        let persistedState = PersistedWidgetState(
            widgets: widgets.map { widget in
                PersistedWidget(
                    id: widget.id,
                    title: widget.title,
                    panelWidth: widget.panelSize.width,
                    panelHeight: widget.panelSize.height,
                    backgroundOpacity: widget.backgroundOpacity,
                    displayMode: widget.displayMode,
                    items: widget.items.map(makePersistedItem(from:)),
                    frame: widget.frame.map {
                        PersistedRect(
                            x: $0.origin.x,
                            y: $0.origin.y,
                            width: $0.size.width,
                            height: $0.size.height
                        )
                    }
                )
            }
        )

        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(persistedState)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            logger.error(
                "Failed to save widget state to \(self.storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadItem(from persistedItem: PersistedWidgetItem) -> WidgetItem? {
        let fallbackURL = URL(fileURLWithPath: persistedItem.path).standardizedFileURL

        if let bookmarkData = persistedItem.bookmarkData {
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                let effectiveBookmarkData = isStale
                    ? refreshedBookmarkData(for: resolvedURL) ?? bookmarkData
                    : bookmarkData

                if let item = WidgetItem(url: resolvedURL, bookmarkData: effectiveBookmarkData) {
                    return item
                }

                logger.warning(
                    "Bookmark resolved to an unreadable item at \(resolvedURL.path, privacy: .public); falling back to path."
                )
            } catch {
                logger.warning(
                    "Failed to resolve bookmark for \(persistedItem.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if let item = WidgetItem(url: fallbackURL) {
            return item
        }

        logger.warning(
            "Skipping broken widget item at \(persistedItem.path, privacy: .public) because neither bookmark nor path could be restored."
        )
        return nil
    }

    private func makePersistedItem(from item: WidgetItem) -> PersistedWidgetItem {
        let standardizedPath = item.url.standardizedFileURL.path
        let bookmarkData = item.bookmarkData ?? refreshedBookmarkData(for: item.url)

        if item.bookmarkData == nil && bookmarkData == nil {
            logger.warning(
                "Saving widget item without bookmark fallback for \(standardizedPath, privacy: .public). Path-only restore will be used."
            )
        }

        return PersistedWidgetItem(
            path: standardizedPath,
            bookmarkData: bookmarkData
        )
    }

    private func refreshedBookmarkData(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.warning(
                "Failed to create bookmark for \(url.standardizedFileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

private struct PersistedWidgetState: Codable {
    let widgets: [PersistedWidget]
}

private struct PersistedWidget: Codable {
    let id: UUID
    let title: String
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let backgroundOpacity: Double
    let displayMode: WidgetDisplayMode
    let items: [PersistedWidgetItem]
    let frame: PersistedRect?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case panelWidth
        case panelHeight
        case backgroundOpacity
        case displayMode
        case items
        case itemPaths
        case frame
    }

    init(
        id: UUID,
        title: String,
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        backgroundOpacity: Double,
        displayMode: WidgetDisplayMode,
        items: [PersistedWidgetItem],
        frame: PersistedRect?
    ) {
        self.id = id
        self.title = title
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.backgroundOpacity = backgroundOpacity
        self.displayMode = displayMode
        self.items = items
        self.frame = frame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        panelWidth = try container.decode(CGFloat.self, forKey: .panelWidth)
        panelHeight = try container.decode(CGFloat.self, forKey: .panelHeight)
        backgroundOpacity = try container.decode(Double.self, forKey: .backgroundOpacity)
        displayMode = try container.decodeIfPresent(WidgetDisplayMode.self, forKey: .displayMode) ?? .grid
        frame = try container.decodeIfPresent(PersistedRect.self, forKey: .frame)
        items = try container.decodeIfPresent([PersistedWidgetItem].self, forKey: .items)
            ?? (try container.decodeIfPresent([String].self, forKey: .itemPaths) ?? []).map {
                PersistedWidgetItem(path: $0, bookmarkData: nil)
            }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(panelWidth, forKey: .panelWidth)
        try container.encode(panelHeight, forKey: .panelHeight)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(frame, forKey: .frame)
    }
}

private struct PersistedWidgetItem: Codable {
    let path: String
    let bookmarkData: Data?
}

private struct PersistedRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}
