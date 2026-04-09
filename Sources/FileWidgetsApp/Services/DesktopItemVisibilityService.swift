import FileWidgetsSupport
import Foundation
import OSLog

@MainActor
final class DesktopItemVisibilityService {
    static let shared = DesktopItemVisibilityService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DesktopFileBoxWidget",
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

        DesktopVisibilitySupport.restoreManagedEntries(state.managedEntries)
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

        for path in pinnedDesktopPaths {
            let url = URL(fileURLWithPath: path)
            let currentHiddenState = DesktopVisibilitySupport.currentHiddenState(for: url) ?? false
            if state.managedEntries[path] == nil {
                state.managedEntries[path] = currentHiddenState
            }

            if currentHiddenState == false {
                _ = DesktopVisibilitySupport.setHidden(true, for: url)
            }
        }

        let stalePaths = Set(state.managedEntries.keys).subtracting(pinnedDesktopPaths)
        for path in stalePaths {
            let url = URL(fileURLWithPath: path)
            if state.managedEntries[path] == false {
                _ = DesktopVisibilitySupport.setHidden(false, for: url)
            }
            state.managedEntries.removeValue(forKey: path)
        }

        persistState()
    }

    func restoreManagedDesktopItems() {
        DesktopVisibilitySupport.restoreManagedEntries(state.managedEntries)
        state = DesktopVisibilityState()
        persistState()
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
        do {
            try stateStore.save(state)
        } catch {
            logger.error("Failed to persist desktop visibility state: \(error.localizedDescription, privacy: .public)")
        }
    }
}
