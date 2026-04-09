import Darwin
import Foundation

public struct FileWidgetsSupportPaths {
    public static var applicationSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory.appendingPathComponent("FileWidgets", isDirectory: true)
    }

    public static var desktopVisibilityStateURL: URL {
        applicationSupportDirectory.appendingPathComponent("desktop-visibility-state.json", isDirectory: false)
    }

    public static var widgetsStoreURL: URL {
        applicationSupportDirectory.appendingPathComponent("widgets.json", isDirectory: false)
    }
}

public struct DesktopVisibilityState: Codable {
    public var activeSessionID: String?
    public var ownerPID: Int32?
    public var managedEntries: [String: Bool]

    public init(
        activeSessionID: String? = nil,
        ownerPID: Int32? = nil,
        managedEntries: [String: Bool] = [:]
    ) {
        self.activeSessionID = activeSessionID
        self.ownerPID = ownerPID
        self.managedEntries = managedEntries
    }
}

public struct DesktopVisibilityStateStore {
    public let url: URL

    public init(url: URL = FileWidgetsSupportPaths.desktopVisibilityStateURL) {
        self.url = url
    }

    public func load() -> DesktopVisibilityState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(DesktopVisibilityState.self, from: data) else {
            return DesktopVisibilityState()
        }

        return state
    }

    public func save(_ state: DesktopVisibilityState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: [.atomic])
    }
}

public enum DesktopVisibilitySupport {
    public static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid_t(pid), 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    public static func restoreManagedEntries(_ managedEntries: [String: Bool]) {
        for (path, wasHiddenBeforeManaging) in managedEntries where wasHiddenBeforeManaging == false {
            _ = setHidden(false, for: URL(fileURLWithPath: path))
        }
    }

    @discardableResult
    public static func setHidden(_ hidden: Bool, for url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = hidden

        do {
            try mutableURL.setResourceValues(resourceValues)
            return true
        } catch {
            return false
        }
    }

    public static func currentHiddenState(for url: URL) -> Bool? {
        try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden
    }
}
