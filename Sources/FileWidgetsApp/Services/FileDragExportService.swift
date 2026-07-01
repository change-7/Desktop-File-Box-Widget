import Foundation
import OSLog

@MainActor
final class FileDragExportService {
    static let shared = FileDragExportService()

    private let fileManager = FileManager.default
    private let maximumTemporaryExportBytes: Int64 = 128 * 1024 * 1024
    private let maximumTotalTemporaryExportBytes: Int64 = 512 * 1024 * 1024
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

    func performMaintenance() {
        removeStaleExportsIfNeeded()
        trimExportsIfNeeded()
    }

    func dragURL(for originalURL: URL) -> URL? {
        performMaintenance()

        let standardizedURL = originalURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isHidden(standardizedURL) else {
            return standardizedURL
        }

        guard shouldCreateVisibleCopy(for: standardizedURL) else {
            return nil
        }

        do {
            return try makeVisibleTemporaryCopy(of: standardizedURL)
        } catch {
            logger.error("Failed to create visible drag export for \(standardizedURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func isHidden(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isHiddenKey])
        return values?.isHidden == true
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
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .fileSizeKey])
        guard values?.isHidden == true,
              values?.isDirectory != true,
              values?.isRegularFile == true else {
            return false
        }

        guard let fileSizeValue = values?.fileSize else {
            return false
        }
        let fileSize = Int64(fileSizeValue)
        guard fileSize <= maximumTemporaryExportBytes else {
            logger.warning("Skipping temporary drag export for large hidden file \(url.path, privacy: .public)")
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

    private func trimExportsIfNeeded() {
        guard var exportDirectories = try? fileManager.contentsOfDirectory(
            at: exportRootURL,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return
        }

        var totalBytes: Int64 = 0
        var directoriesWithSize: [(url: URL, creationDate: Date, size: Int64)] = []
        for directoryURL in exportDirectories {
            let resourceValues = try? directoryURL.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }

            let size = directorySize(directoryURL)
            totalBytes += size
            directoriesWithSize.append((
                url: directoryURL,
                creationDate: resourceValues?.creationDate ?? .distantPast,
                size: size
            ))
        }

        guard totalBytes > maximumTotalTemporaryExportBytes else { return }

        exportDirectories = directoriesWithSize
            .sorted { $0.creationDate < $1.creationDate }
            .map(\.url)
        for directoryURL in exportDirectories {
            guard totalBytes > maximumTotalTemporaryExportBytes else { break }
            let size = directorySize(directoryURL)
            try? fileManager.removeItem(at: directoryURL)
            totalBytes -= size
        }
    }

    private func directorySize(_ directoryURL: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
            ])
            guard resourceValues?.isRegularFile == true else { continue }

            let allocatedSize = resourceValues?.totalFileAllocatedSize
                ?? resourceValues?.fileAllocatedSize
                ?? 0
            totalBytes += Int64(max(allocatedSize, 0))
        }
        return totalBytes
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
