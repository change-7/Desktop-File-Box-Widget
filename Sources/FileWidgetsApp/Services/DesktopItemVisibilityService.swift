import FileWidgetsSupport
import Foundation
import OSLog

@MainActor
final class DesktopItemVisibilityService {
    static let shared = DesktopItemVisibilityService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.filetray.app",
        category: "DesktopVisibility"
    )
    private let fileManager = FileManager.default
    private let stateStore: DesktopVisibilityStateStore
    private var state: DesktopVisibilityState

    private init(stateStore: DesktopVisibilityStateStore = DesktopVisibilityStateStore()) {
        self.stateStore = stateStore
        self.state = stateStore.load()
    }

    func recoverInterruptedSessionIfNeeded() {
        guard let ownerPID = state.ownerPID,
              let activeSessionID = state.activeSessionID else {
            return
        }

        guard DesktopVisibilitySupport.processExists(ownerPID) == false else {
            return
        }

        DesktopVisibilitySupport.restoreManagedEntries(
            state.managedEntries,
            fileIdentities: state.managedFileIdentities
        )
        logger.notice("Recovered interrupted visibility session \(activeSessionID, privacy: .public)")
        state = DesktopVisibilityState()
        persistState()
    }

    func beginSession(ownerPID: Int32, sessionID: String) {
        state.activeSessionID = sessionID
        state.ownerPID = ownerPID
        persistState()
    }

    func launchGuardianIfPossible(sessionID: String, ownerPID: Int32) {
        guard let executableURL = visibilityGuardianExecutableURL() else {
            logger.error("VisibilityGuardian executable was not found")
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [sessionID, String(ownerPID)]

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch VisibilityGuardian: \(error.localizedDescription, privacy: .public)")
        }
    }

    func synchronizePinnedItems(_ urls: [URL]) {
        let pinnedDesktopPaths = Set(urls.compactMap(desktopItemPath(for:)))
        var targetState = state

        for path in pinnedDesktopPaths {
            let url = URL(fileURLWithPath: path)
            let currentHiddenState = DesktopVisibilitySupport.currentHiddenState(for: url) ?? false
            let currentIdentity = DesktopVisibilitySupport.fileIdentity(for: url)
            let previousIdentity = targetState.managedFileIdentities[path]
            let identityChanged = previousIdentity != nil
                && currentIdentity != nil
                && previousIdentity != currentIdentity

            if targetState.managedEntries[path] == nil || identityChanged {
                targetState.managedEntries[path] = currentHiddenState
            }
            targetState.managedFileIdentities[path] = currentIdentity
        }

        guard persistState(targetState) else {
            logger.error("Skipped desktop visibility changes because recovery state could not be persisted")
            return
        }

        state = targetState

        for path in pinnedDesktopPaths {
            let url = URL(fileURLWithPath: path)
            if DesktopVisibilitySupport.currentHiddenState(for: url) == false {
                _ = DesktopVisibilitySupport.setHidden(true, for: url)
            }
        }

        let stalePaths = Set(state.managedEntries.keys).subtracting(pinnedDesktopPaths)
        var finalState = state
        for path in stalePaths {
            let url = URL(fileURLWithPath: path)
            guard let wasHiddenBeforeManaging = state.managedEntries[path] else { continue }
            let expectedIdentity = state.managedFileIdentities[path]
            let currentIdentity = DesktopVisibilitySupport.fileIdentity(for: url)
            let identityMatches = expectedIdentity == nil
                || currentIdentity == nil
                || expectedIdentity == currentIdentity

            if wasHiddenBeforeManaging == false,
               fileManager.fileExists(atPath: path),
               identityMatches,
               DesktopVisibilitySupport.setHidden(false, for: url) == false {
                logger.error("Failed to restore visible state for \(path, privacy: .public)")
                continue
            }

            finalState.managedEntries.removeValue(forKey: path)
            finalState.managedFileIdentities.removeValue(forKey: path)
        }

        state = finalState
        persistState()
    }

    @discardableResult
    func restoreManagedDesktopItems(endingSession: Bool = true) -> Int {
        let restoredCount = state.managedEntries.count
        DesktopVisibilitySupport.restoreManagedEntries(
            state.managedEntries,
            fileIdentities: state.managedFileIdentities
        )
        state.managedEntries = [:]
        state.managedFileIdentities = [:]
        if endingSession {
            state.activeSessionID = nil
            state.ownerPID = nil
        }
        persistState()
        return restoredCount
    }

    private var desktopDirectoryURL: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }

    private func desktopItemPath(for url: URL) -> String? {
        guard let desktopDirectoryURL else { return nil }

        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard normalizedURL.deletingLastPathComponent().standardizedFileURL == desktopDirectoryURL else {
            return nil
        }

        return normalizedURL.path
    }

    private func visibilityGuardianExecutableURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VisibilityGuardian", isDirectory: false),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("VisibilityGuardian", isDirectory: false),
        ].compactMap { $0 }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private func persistState() {
        _ = persistState(state)
    }

    @discardableResult
    private func persistState(_ state: DesktopVisibilityState) -> Bool {
        do {
            try stateStore.save(state)
            return true
        } catch {
            logger.error("Failed to persist desktop visibility state: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
