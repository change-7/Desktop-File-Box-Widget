import Combine
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

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
    @Published var items: [WidgetItem]
    @Published var frame: CGRect?
    @Published var selectedItemID: WidgetItem.ID?

    init(
        id: UUID = UUID(),
        title: String,
        panelSize: CGSize,
        backgroundOpacity: Double = 0.78,
        items: [WidgetItem],
        frame: CGRect? = nil
    ) {
        self.id = id
        self.title = title
        self.panelSize = panelSize
        self.backgroundOpacity = backgroundOpacity
        self.items = items
        self.frame = frame
        self.selectedItemID = nil
    }
}
