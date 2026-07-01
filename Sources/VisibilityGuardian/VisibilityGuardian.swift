import Foundation
import FileWidgetsSupport

@main
struct VisibilityGuardian {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3,
              let parentPID = Int32(arguments[2]) else {
            return
        }

        let sessionID = arguments[1]
        let ownerExecutablePath = arguments.count >= 4 ? arguments[3] : nil
        let stateStore = DesktopVisibilityStateStore()

        while DesktopVisibilitySupport.processMatches(pid: parentPID, executablePath: ownerExecutablePath) {
            try? await Task.sleep(for: .milliseconds(500))
        }

        var state = stateStore.load()
        guard state.activeSessionID == sessionID,
              state.ownerPID == parentPID,
              state.ownerExecutablePath == ownerExecutablePath else {
            return
        }

        let restoreResult = DesktopVisibilitySupport.restoreManagedEntries(
            state.managedEntries,
            fileIdentities: state.managedFileIdentities
        )
        state = DesktopVisibilitySupport.unresolvedState(
            from: restoreResult,
            activeSessionID: state.activeSessionID,
            ownerPID: state.ownerPID,
            ownerExecutablePath: state.ownerExecutablePath
        )
        try? stateStore.save(state)
    }
}
