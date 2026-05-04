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
    public var managedFileIdentities: [String: String]

    public init(
        activeSessionID: String? = nil,
        ownerPID: Int32? = nil,
        managedEntries: [String: Bool] = [:],
        managedFileIdentities: [String: String] = [:]
    ) {
        self.activeSessionID = activeSessionID
        self.ownerPID = ownerPID
        self.managedEntries = managedEntries
        self.managedFileIdentities = managedFileIdentities
    }

    private enum CodingKeys: String, CodingKey {
        case activeSessionID
        case ownerPID
        case managedEntries
        case managedFileIdentities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeSessionID = try container.decodeIfPresent(String.self, forKey: .activeSessionID)
        ownerPID = try container.decodeIfPresent(Int32.self, forKey: .ownerPID)
        managedEntries = try container.decodeIfPresent([String: Bool].self, forKey: .managedEntries) ?? [:]
        managedFileIdentities = try container.decodeIfPresent([String: String].self, forKey: .managedFileIdentities) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(activeSessionID, forKey: .activeSessionID)
        try container.encodeIfPresent(ownerPID, forKey: .ownerPID)
        try container.encode(managedEntries, forKey: .managedEntries)
        try container.encode(managedFileIdentities, forKey: .managedFileIdentities)
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

    public static func restoreManagedEntries(
        _ managedEntries: [String: Bool],
        fileIdentities: [String: String] = [:]
    ) {
        for (path, wasHiddenBeforeManaging) in managedEntries where wasHiddenBeforeManaging == false {
            let url = URL(fileURLWithPath: path)
            if let expectedIdentity = fileIdentities[path],
               let currentIdentity = fileIdentity(for: url),
               currentIdentity != expectedIdentity {
                continue
            }

            _ = setHidden(false, for: url)
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

    public static func fileIdentity(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }

        return "\(systemNumber.stringValue):\(fileNumber.stringValue)"
    }
}
