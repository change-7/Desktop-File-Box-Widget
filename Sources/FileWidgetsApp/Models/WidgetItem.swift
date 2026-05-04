import Combine
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum WidgetDisplayMode: String, Codable {
    case grid
    case list
}

enum FileTrayCategory: String, CaseIterable, Codable, Identifiable {
    case images
    case documents
    case archives
    case videos
    case audio
    case folders
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images:
            return "Images"
        case .documents:
            return "Documents"
        case .archives:
            return "Archives"
        case .videos:
            return "Videos"
        case .audio:
            return "Audio"
        case .folders:
            return "Folders"
        case .other:
            return "Other"
        }
    }
}

enum WidgetTrayKind: Codable, Equatable, Hashable {
    case manual
    case screenshots
    case auto(FileTrayCategory)

    var title: String {
        switch self {
        case .manual:
            return "Pinned Files"
        case .screenshots:
            return "Screenshots"
        case .auto(let category):
            return category.title
        }
    }

    var isScreenshots: Bool {
        self == .screenshots
    }
}

struct CustomFileTypeRule: Identifiable, Codable, Hashable {
    var id: UUID
    var fileExtension: String
    var category: FileTrayCategory

    init(id: UUID = UUID(), fileExtension: String, category: FileTrayCategory) {
        self.id = id
        self.fileExtension = fileExtension
        self.category = category
    }
}

struct AutoTraySettings: Codable, Equatable {
    static let defaultDragExportRetentionMinutes = 360
    static let minimumDragExportRetentionMinutes = 15
    static let maximumDragExportRetentionMinutes = 24 * 60

    var collectDesktopScreenshots: Bool
    var organizeNewDesktopFiles: Bool
    var enabledCategories: Set<FileTrayCategory>
    var customRules: [CustomFileTypeRule]
    var dragExportRetentionMinutes: Int

    static let defaultValue = AutoTraySettings(
        collectDesktopScreenshots: true,
        organizeNewDesktopFiles: false,
        enabledCategories: Set(FileTrayCategory.allCases),
        customRules: [],
        dragExportRetentionMinutes: defaultDragExportRetentionMinutes
    )

    init(
        collectDesktopScreenshots: Bool,
        organizeNewDesktopFiles: Bool,
        enabledCategories: Set<FileTrayCategory>,
        customRules: [CustomFileTypeRule],
        dragExportRetentionMinutes: Int
    ) {
        self.collectDesktopScreenshots = collectDesktopScreenshots
        self.organizeNewDesktopFiles = organizeNewDesktopFiles
        self.enabledCategories = enabledCategories
        self.customRules = customRules
        self.dragExportRetentionMinutes = Self.clampedDragExportRetentionMinutes(dragExportRetentionMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case collectDesktopScreenshots
        case organizeNewDesktopFiles
        case enabledCategories
        case customRules
        case dragExportRetentionMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectDesktopScreenshots = try container.decodeIfPresent(Bool.self, forKey: .collectDesktopScreenshots)
            ?? Self.defaultValue.collectDesktopScreenshots
        organizeNewDesktopFiles = try container.decodeIfPresent(Bool.self, forKey: .organizeNewDesktopFiles)
            ?? Self.defaultValue.organizeNewDesktopFiles
        enabledCategories = try container.decodeIfPresent(Set<FileTrayCategory>.self, forKey: .enabledCategories)
            ?? Self.defaultValue.enabledCategories
        customRules = try container.decodeIfPresent([CustomFileTypeRule].self, forKey: .customRules)
            ?? Self.defaultValue.customRules
        dragExportRetentionMinutes = Self.clampedDragExportRetentionMinutes(
            try container.decodeIfPresent(Int.self, forKey: .dragExportRetentionMinutes)
                ?? Self.defaultDragExportRetentionMinutes
        )
    }

    static func clampedDragExportRetentionMinutes(_ minutes: Int) -> Int {
        min(max(minutes, minimumDragExportRetentionMinutes), maximumDragExportRetentionMinutes)
    }
}

struct WidgetItem: Identifiable, Hashable {
    enum Kind: String {
        case file
        case folder
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let url: URL
    let bookmarkData: Data?
    let kind: Kind
    let isImage: Bool

    init(
        title: String,
        subtitle: String,
        url: URL,
        bookmarkData: Data? = nil,
        kind: Kind,
        isImage: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.bookmarkData = bookmarkData
        self.kind = kind
        self.isImage = isImage
    }

    init?(url: URL, bookmarkData: Data? = nil) {
        let normalizedURL = url.standardizedFileURL
        let resourceValues = try? normalizedURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .localizedNameKey,
            .contentTypeKey,
        ])

        let isDirectory = resourceValues?.isDirectory ?? false
        let resolvedTitle = resourceValues?.localizedName
            ?? (normalizedURL.pathExtension.isEmpty
                ? normalizedURL.lastPathComponent
                : normalizedURL.deletingPathExtension().lastPathComponent)

        guard !resolvedTitle.isEmpty else {
            return nil
        }

        let resolvedSubtitle: String
        if isDirectory {
            resolvedSubtitle = "Folder"
        } else if normalizedURL.pathExtension.isEmpty {
            resolvedSubtitle = "File"
        } else {
            resolvedSubtitle = normalizedURL.pathExtension.uppercased()
        }

        let contentType = resourceValues?.contentType ?? UTType(filenameExtension: normalizedURL.pathExtension)

        self.init(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            url: normalizedURL,
            bookmarkData: bookmarkData,
            kind: isDirectory ? .folder : .file,
            isImage: !isDirectory && (contentType?.conforms(to: .image) ?? false)
        )
    }
}

@MainActor
final class WidgetModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var panelSize: CGSize
    @Published var backgroundOpacity: Double
    @Published var displayMode: WidgetDisplayMode
    @Published var trayKind: WidgetTrayKind
    @Published var items: [WidgetItem]
    @Published var frame: CGRect?
    @Published var selectedItemID: WidgetItem.ID?

    init(
        id: UUID = UUID(),
        title: String,
        panelSize: CGSize,
        backgroundOpacity: Double = 0.78,
        displayMode: WidgetDisplayMode = .grid,
        trayKind: WidgetTrayKind = .manual,
        items: [WidgetItem],
        frame: CGRect? = nil
    ) {
        self.id = id
        self.title = title
        self.panelSize = panelSize
        self.backgroundOpacity = backgroundOpacity
        self.displayMode = displayMode
        self.trayKind = trayKind
        self.items = items
        self.frame = frame
        self.selectedItemID = nil
    }
}
