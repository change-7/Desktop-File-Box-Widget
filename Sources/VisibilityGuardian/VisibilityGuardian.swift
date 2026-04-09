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
        let stateStore = DesktopVisibilityStateStore()

        while DesktopVisibilitySupport.processExists(parentPID) {
            try? await Task.sleep(for: .milliseconds(500))
        }

        var state = stateStore.load()
        guard state.activeSessionID == sessionID,
              state.ownerPID == parentPID else {
            return
        }

        DesktopVisibilitySupport.restoreManagedEntries(state.managedEntries)
        state = DesktopVisibilityState()
        try? stateStore.save(state)
    }
}
