import CoreServices
import Foundation
import UniformTypeIdentifiers

enum DesktopFileClassifier {
    static func dateKey(for url: URL) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = resourceValues?.creationDate
            ?? resourceValues?.contentModificationDate
            ?? Date()
        return DateTrayFormatter.key(for: date)
    }

    static func isScreenshot(_ url: URL) -> Bool {
        guard isImage(url) else { return false }

        if let metadataItem = MDItemCreate(nil, url.path as CFString),
           let isScreenCapture = MDItemCopyAttribute(metadataItem, "kMDItemIsScreenCapture" as CFString) {
            if let isScreenCapture = isScreenCapture as? Bool {
                return isScreenCapture
            }
        }

        let filename = url.deletingPathExtension().lastPathComponent.lowercased()
        let screenshotTokens = [
            "screenshot",
            "screen shot",
            "스크린샷",
            "화면 기록",
            "截屏",
            "スクリーンショット",
        ]
        return screenshotTokens.contains { filename.contains($0) }
    }

    static func category(for url: URL, settings: AutoTraySettings) -> FileTrayCategory {
        let normalizedExtension = url.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let customRule = settings.customRules.first(where: { $0.fileExtension == normalizedExtension }) {
            return customRule.category
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        if resourceValues?.isDirectory == true {
            return .folders
        }

        let contentType = resourceValues?.contentType ?? UTType(filenameExtension: normalizedExtension)
        guard let contentType else {
            return .other
        }

        if contentType.conforms(to: .image) {
            return .images
        }

        if contentType.conforms(to: .movie) {
            return .videos
        }

        if contentType.conforms(to: .audio) {
            return .audio
        }

        if contentType.conforms(to: .archive) {
            return .archives
        }

        if contentType.conforms(to: .text)
            || contentType.conforms(to: .pdf)
            || contentType.conforms(to: .presentation)
            || contentType.conforms(to: .spreadsheet)
            || contentType.conforms(to: .rtf) {
            return .documents
        }

        return .other
    }

    private static func isImage(_ url: URL) -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        guard resourceValues?.isDirectory != true else {
            return false
        }

        let contentType = resourceValues?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return contentType?.conforms(to: .image) ?? false
    }
}
