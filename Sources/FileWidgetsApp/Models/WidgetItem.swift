import Combine
import CoreGraphics
import Foundation
import FileWidgetsSupport
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
            return L10n.images
        case .documents:
            return L10n.documents
        case .archives:
            return L10n.archives
        case .videos:
            return L10n.videos
        case .audio:
            return L10n.audio
        case .folders:
            return L10n.folders
        case .other:
            return L10n.other
        }
    }
}

enum WidgetTrayKind: Codable, Equatable, Hashable {
    case manual
    case screenshots
    case auto(FileTrayCategory)
    case date(String)

    var title: String {
        switch self {
        case .manual:
            return L10n.pinnedFiles
        case .screenshots:
            return L10n.screenshots
        case .auto(let category):
            return category.title
        case .date(let key):
            return DateTrayFormatter.title(for: key)
        }
    }

    var isScreenshots: Bool {
        self == .screenshots
    }
}

enum DateTrayFormatter {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let day = calendar.date(from: components) else {
            return keyString(for: date)
        }
        return keyString(for: day)
    }

    static func title(for key: String) -> String {
        guard let date = date(from: key) else {
            return key
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func keyString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
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
    var organizeNewDesktopFilesByDate: Bool
    var enabledCategories: Set<FileTrayCategory>
    var customRules: [CustomFileTypeRule]
    var dragExportRetentionMinutes: Int

    static let defaultValue = AutoTraySettings(
        collectDesktopScreenshots: true,
        organizeNewDesktopFiles: false,
        organizeNewDesktopFilesByDate: false,
        enabledCategories: Set(FileTrayCategory.allCases),
        customRules: [],
        dragExportRetentionMinutes: defaultDragExportRetentionMinutes
    )

    init(
        collectDesktopScreenshots: Bool,
        organizeNewDesktopFiles: Bool,
        organizeNewDesktopFilesByDate: Bool = false,
        enabledCategories: Set<FileTrayCategory>,
        customRules: [CustomFileTypeRule],
        dragExportRetentionMinutes: Int
    ) {
        self.collectDesktopScreenshots = collectDesktopScreenshots
        self.organizeNewDesktopFiles = organizeNewDesktopFiles
        self.organizeNewDesktopFilesByDate = organizeNewDesktopFilesByDate
        self.enabledCategories = enabledCategories
        self.customRules = customRules
        self.dragExportRetentionMinutes = Self.clampedDragExportRetentionMinutes(dragExportRetentionMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case collectDesktopScreenshots
        case organizeNewDesktopFiles
        case organizeNewDesktopFilesByDate
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
        organizeNewDesktopFilesByDate = try container.decodeIfPresent(Bool.self, forKey: .organizeNewDesktopFilesByDate)
            ?? Self.defaultValue.organizeNewDesktopFilesByDate
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

struct WidgetBackgroundColor: Codable, Equatable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = Self.clampedComponent(red)
        self.green = Self.clampedComponent(green)
        self.blue = Self.clampedComponent(blue)
        self.alpha = Self.clampedComponent(alpha)
    }

    private static func clampedComponent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
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
    let fileIdentity: String?
    let kind: Kind
    let isImage: Bool

    init(
        title: String,
        subtitle: String,
        url: URL,
        bookmarkData: Data? = nil,
        fileIdentity: String? = nil,
        kind: Kind,
        isImage: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.bookmarkData = bookmarkData
        self.fileIdentity = fileIdentity
        self.kind = kind
        self.isImage = isImage
    }

    init?(url: URL, bookmarkData: Data? = nil, fileIdentity: String? = nil) {
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
            resolvedSubtitle = L10n.folder
        } else if normalizedURL.pathExtension.isEmpty {
            resolvedSubtitle = L10n.file
        } else {
            resolvedSubtitle = normalizedURL.pathExtension.uppercased()
        }

        let contentType = resourceValues?.contentType ?? UTType(filenameExtension: normalizedURL.pathExtension)

        self.init(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            url: normalizedURL,
            bookmarkData: bookmarkData,
            fileIdentity: fileIdentity ?? DesktopVisibilitySupport.fileIdentity(for: normalizedURL),
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
    @Published var backgroundColor: WidgetBackgroundColor?
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
        backgroundColor: WidgetBackgroundColor? = nil,
        displayMode: WidgetDisplayMode = .grid,
        trayKind: WidgetTrayKind = .manual,
        items: [WidgetItem],
        frame: CGRect? = nil
    ) {
        self.id = id
        self.title = title
        self.panelSize = panelSize
        self.backgroundOpacity = backgroundOpacity
        self.backgroundColor = backgroundColor
        self.displayMode = displayMode
        self.trayKind = trayKind
        self.items = items
        self.frame = frame
        self.selectedItemID = nil
    }
}
