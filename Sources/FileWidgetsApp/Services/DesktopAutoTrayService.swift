import Foundation
import OSLog

@MainActor
final class DesktopAutoTrayService {
    private let fileManager = FileManager.default
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.filetray.app",
        category: "DesktopAutoTray"
    )

    private var directoryDescriptor: CInt = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var pendingScan: DispatchWorkItem?
    private var candidateTasks: [String: Task<Void, Never>] = [:]
    private var knownItems: [String: String] = [:]
    private var startedAt = Date()
    private var onNewDesktopItem: ((URL) -> Void)?
    private var onDesktopItemsChanged: (() -> Void)?

    func start(
        onNewDesktopItem: @escaping (URL) -> Void,
        onDesktopItemsChanged: @escaping () -> Void
    ) {
        stop()
        self.onNewDesktopItem = onNewDesktopItem
        self.onDesktopItemsChanged = onDesktopItemsChanged
        startedAt = Date()
        knownItems = currentDesktopItems()

        guard let desktopURL else {
            logger.error("Desktop directory was not found")
            return
        }

        directoryDescriptor = open(desktopURL.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            logger.error("Failed to open Desktop directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.directoryDescriptor >= 0 {
                close(self.directoryDescriptor)
                self.directoryDescriptor = -1
            }
        }
        directorySource = source
        source.resume()
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        candidateTasks.values.forEach { $0.cancel() }
        candidateTasks.removeAll()
        directorySource?.cancel()
        directorySource = nil
        onNewDesktopItem = nil
        onDesktopItemsChanged = nil
        if directoryDescriptor >= 0 {
            close(directoryDescriptor)
            directoryDescriptor = -1
        }
    }

    func markKnown(_ urls: [URL]) {
        for url in urls.map({ $0.standardizedFileURL.resolvingSymlinksInPath() }) {
            knownItems[url.path] = itemSignature(for: url)
        }
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.scanDesktop()
        }
        pendingScan = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func scanDesktop() {
        guard let desktopURL else { return }
        let urls = (try? fileManager.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .creationDateKey],
            options: [.skipsSubdirectoryDescendants]
        )) ?? []

        let standardizedURLs = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        var currentItems: [String: String] = [:]

        for url in standardizedURLs {
            let path = url.path
            let signature = itemSignature(for: url)
            currentItems[path] = signature

            guard knownItems[path] != signature else { continue }
            scheduleCandidateProcessing(url)
        }

        knownItems = currentItems
        onDesktopItemsChanged?()
    }

    private func scheduleCandidateProcessing(_ url: URL) {
        let path = url.path
        candidateTasks[path]?.cancel()

        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled else {
                    return
                }

                self.candidateTasks[path] = nil
                self.processCandidate(url)
            }
        }
        candidateTasks[path] = task
    }

    private func processCandidate(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path),
              isDirectDesktopChild(url),
              isVisible(url),
              wasCreatedAfterServiceStart(url) else {
            return
        }

        onNewDesktopItem?(url)
    }

    private func currentDesktopItems() -> [String: String] {
        guard let desktopURL else { return [:] }
        let urls = (try? fileManager.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []
        var items: [String: String] = [:]
        for url in urls {
            let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
            items[standardizedURL.path] = itemSignature(for: standardizedURL)
        }
        return items
    }

    private func itemSignature(for url: URL) -> String {
        let attributes = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        let systemNumber = (attributes[.systemNumber] as? NSNumber)?.stringValue ?? "0"
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.stringValue ?? "0"
        let creationTime = (attributes[.creationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let modificationTime = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attributes[.size] as? NSNumber)?.stringValue ?? "0"
        return "\(systemNumber):\(fileNumber):\(creationTime):\(modificationTime):\(size)"
    }

    private var desktopURL: URL? {
        fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }

    private func isDirectDesktopChild(_ url: URL) -> Bool {
        guard let desktopURL else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == desktopURL
    }

    private func isVisible(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isHiddenKey])
        return values?.isHidden != true
    }

    private func wasCreatedAfterServiceStart(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        guard let creationDate = values?.creationDate else {
            return true
        }
        return creationDate >= startedAt.addingTimeInterval(-1)
    }
}
