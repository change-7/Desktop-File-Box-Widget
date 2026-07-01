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
    private var didRecoverFromUnreadableState: Bool

    private init(stateStore: DesktopVisibilityStateStore = DesktopVisibilityStateStore()) {
        self.stateStore = stateStore
        switch stateStore.loadResult() {
        case .missing:
            self.state = DesktopVisibilityState()
            self.didRecoverFromUnreadableState = false
        case .loaded(let state):
            self.state = state
            self.didRecoverFromUnreadableState = false
        case .failed(let backupURL):
            self.state = DesktopVisibilityState()
            self.didRecoverFromUnreadableState = true
            logger.error("Desktop visibility state was unreadable. Backup: \(backupURL?.path ?? "none", privacy: .public)")
        }
    }

    func recoverInterruptedSessionIfNeeded() {
        guard let ownerPID = state.ownerPID,
              let activeSessionID = state.activeSessionID else {
            return
        }

        guard DesktopVisibilitySupport.processMatches(
            pid: ownerPID,
            executablePath: state.ownerExecutablePath
        ) == false else {
            return
        }

        let restoreResult = DesktopVisibilitySupport.restoreManagedEntries(
            state.managedEntries,
            fileIdentities: state.managedFileIdentities
        )
        if restoreResult.unresolvedCount > 0 {
            logger.error("Recovered interrupted visibility session \(activeSessionID, privacy: .public) with \(restoreResult.unresolvedCount, privacy: .public) unresolved entries")
        } else {
            logger.notice("Recovered interrupted visibility session \(activeSessionID, privacy: .public)")
        }
        state = DesktopVisibilitySupport.unresolvedState(
            from: restoreResult,
            activeSessionID: activeSessionID,
            ownerPID: ownerPID,
            ownerExecutablePath: state.ownerExecutablePath
        )
        persistState()
    }

    func beginSession(ownerPID: Int32, sessionID: String, ownerExecutablePath: String?) {
        state.activeSessionID = sessionID
        state.ownerPID = ownerPID
        state.ownerExecutablePath = ownerExecutablePath
    }

    func launchGuardianIfPossible(sessionID: String, ownerPID: Int32, ownerExecutablePath: String?) {
        guard let executableURL = visibilityGuardianExecutableURL() else {
            logger.error("VisibilityGuardian executable was not found")
            return
        }

        let process = Process()
        process.executableURL = executableURL
        var arguments = [sessionID, String(ownerPID)]
        if let ownerExecutablePath,
           ownerExecutablePath.isEmpty == false {
            arguments.append(ownerExecutablePath)
        }
        process.arguments = arguments

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
            if didRecoverFromUnreadableState && currentHiddenState {
                logger.warning("Skipped managing already-hidden Desktop item after unreadable recovery state: \(path, privacy: .public)")
                targetState.managedEntries.removeValue(forKey: path)
                targetState.managedFileIdentities.removeValue(forKey: path)
                continue
            }

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
            guard let expectedIdentity = state.managedFileIdentities[path],
                  let currentIdentity = DesktopVisibilitySupport.fileIdentity(for: url),
                  currentIdentity == expectedIdentity else {
                logger.error("Skipped hiding Desktop item because its identity changed before hide: \(path, privacy: .public)")
                state.managedEntries.removeValue(forKey: path)
                state.managedFileIdentities.removeValue(forKey: path)
                continue
            }

            if DesktopVisibilitySupport.currentHiddenState(for: url) == false,
               DesktopVisibilitySupport.setHidden(true, for: url) == false {
                logger.error("Failed to hide managed Desktop item \(path, privacy: .public)")
                state.managedEntries.removeValue(forKey: path)
                state.managedFileIdentities.removeValue(forKey: path)
            }
        }

        let stalePaths = Set(state.managedEntries.keys).subtracting(pinnedDesktopPaths)
        var finalState = state
        for path in stalePaths {
            guard let wasHiddenBeforeManaging = state.managedEntries[path] else { continue }
            let restoreResult = DesktopVisibilitySupport.restoreManagedEntries(
                [path: wasHiddenBeforeManaging],
                fileIdentities: state.managedFileIdentities[path].map { [path: $0] } ?? [:]
            )

            if restoreResult.unresolvedEntries[path] != nil {
                logger.error("Failed to restore visible state for \(path, privacy: .public)")
                continue
            }

            finalState.managedEntries.removeValue(forKey: path)
            finalState.managedFileIdentities.removeValue(forKey: path)
        }

        state = finalState
        persistState()
        didRecoverFromUnreadableState = false
    }

    @discardableResult
    func restoreManagedDesktopItems(endingSession: Bool = true) -> Int {
        let activeSessionID = state.activeSessionID
        let ownerPID = state.ownerPID
        let ownerExecutablePath = state.ownerExecutablePath
        let restoreResult = DesktopVisibilitySupport.restoreManagedEntries(
            state.managedEntries,
            fileIdentities: state.managedFileIdentities
        )
        let restoredCount = restoreResult.completedEntries.count

        state = DesktopVisibilitySupport.unresolvedState(
            from: restoreResult,
            activeSessionID: activeSessionID,
            ownerPID: ownerPID,
            ownerExecutablePath: ownerExecutablePath
        )
        if endingSession && state.managedEntries.isEmpty {
            state.activeSessionID = nil
            state.ownerPID = nil
            state.ownerExecutablePath = nil
        }
        if restoreResult.unresolvedCount > 0 {
            logger.error("Could not restore \(restoreResult.unresolvedCount, privacy: .public) managed Desktop visibility entries")
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
