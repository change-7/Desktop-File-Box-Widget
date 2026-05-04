import Foundation
import OSLog

@MainActor
final class FileDragExportService {
    static let shared = FileDragExportService()

    private let fileManager = FileManager.default
    private let staleExportAge: TimeInterval = 24 * 60 * 60
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.filetray.app",
        category: "FileDragExport"
    )
    private var retentionMinutes = AutoTraySettings.defaultDragExportRetentionMinutes
    private var cleanupWorkItems: [URL: DispatchWorkItem] = [:]

    private init() {}

    func setRetentionMinutes(_ minutes: Int) {
        retentionMinutes = AutoTraySettings.clampedDragExportRetentionMinutes(minutes)
    }

    func dragURL(for originalURL: URL) -> URL {
        removeStaleExportsIfNeeded()

        let standardizedURL = originalURL.standardizedFileURL.resolvingSymlinksInPath()
        guard shouldCreateVisibleCopy(for: standardizedURL) else {
            return standardizedURL
        }

        do {
            return try makeVisibleTemporaryCopy(of: standardizedURL)
        } catch {
            logger.error("Failed to create visible drag export for \(standardizedURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return standardizedURL
        }
    }

    func scheduleCleanup(for exportedURL: URL) {
        guard isManagedExport(exportedURL) else { return }

        cleanupWorkItems[exportedURL]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.removeExport(containing: exportedURL)
        }
        cleanupWorkItems[exportedURL] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay, execute: workItem)
    }

    private func shouldCreateVisibleCopy(for url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isHiddenKey])
        guard values?.isHidden == true else {
            return false
        }

        return fileManager.fileExists(atPath: url.path)
    }

    private func makeVisibleTemporaryCopy(of originalURL: URL) throws -> URL {
        let exportDirectory = exportRootURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destinationURL = exportDirectory
            .appendingPathComponent(originalURL.lastPathComponent, isDirectory: false)
        try fileManager.copyItem(at: originalURL, to: destinationURL)
        try setHidden(false, for: destinationURL)
        return destinationURL
    }

    private func setHidden(_ isHidden: Bool, for url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = isHidden
        try mutableURL.setResourceValues(resourceValues)
    }

    private func removeExport(containing exportedURL: URL) {
        cleanupWorkItems[exportedURL] = nil
        let directoryURL = exportedURL.deletingLastPathComponent()
        guard isManagedExportDirectory(directoryURL) else { return }
        try? fileManager.removeItem(at: directoryURL)
    }

    private func removeStaleExportsIfNeeded() {
        guard let exportDirectories = try? fileManager.contentsOfDirectory(
            at: exportRootURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return
        }

        let expirationDate = Date().addingTimeInterval(-staleExportAge)
        for directoryURL in exportDirectories {
            let creationDate = (try? directoryURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard creationDate < expirationDate else { continue }
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    private func isManagedExport(_ url: URL) -> Bool {
        isManagedExportDirectory(url.deletingLastPathComponent())
    }

    private func isManagedExportDirectory(_ url: URL) -> Bool {
        let standardizedDirectory = url.standardizedFileURL
        let standardizedRoot = exportRootURL.standardizedFileURL
        return standardizedDirectory.deletingLastPathComponent() == standardizedRoot
    }

    private var cleanupDelay: TimeInterval {
        TimeInterval(retentionMinutes * 60)
    }

    private var exportRootURL: URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return applicationSupportURL
            .appendingPathComponent("FileWidgets", isDirectory: true)
            .appendingPathComponent("DragExports", isDirectory: true)
    }
}
