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
    public var ownerExecutablePath: String?
    public var managedEntries: [String: Bool]
    public var managedFileIdentities: [String: String]

    public init(
        activeSessionID: String? = nil,
        ownerPID: Int32? = nil,
        ownerExecutablePath: String? = nil,
        managedEntries: [String: Bool] = [:],
        managedFileIdentities: [String: String] = [:]
    ) {
        self.activeSessionID = activeSessionID
        self.ownerPID = ownerPID
        self.ownerExecutablePath = ownerExecutablePath
        self.managedEntries = managedEntries
        self.managedFileIdentities = managedFileIdentities
    }

    private enum CodingKeys: String, CodingKey {
        case activeSessionID
        case ownerPID
        case ownerExecutablePath
        case managedEntries
        case managedFileIdentities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeSessionID = try container.decodeIfPresent(String.self, forKey: .activeSessionID)
        ownerPID = try container.decodeIfPresent(Int32.self, forKey: .ownerPID)
        ownerExecutablePath = try container.decodeIfPresent(String.self, forKey: .ownerExecutablePath)
        managedEntries = try container.decodeIfPresent([String: Bool].self, forKey: .managedEntries) ?? [:]
        managedFileIdentities = try container.decodeIfPresent([String: String].self, forKey: .managedFileIdentities) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(activeSessionID, forKey: .activeSessionID)
        try container.encodeIfPresent(ownerPID, forKey: .ownerPID)
        try container.encodeIfPresent(ownerExecutablePath, forKey: .ownerExecutablePath)
        try container.encode(managedEntries, forKey: .managedEntries)
        try container.encode(managedFileIdentities, forKey: .managedFileIdentities)
    }
}

public struct DesktopVisibilityStateStore {
    public enum LoadResult {
        case missing
        case loaded(DesktopVisibilityState)
        case failed(backupURL: URL?)
    }

    public let url: URL

    public init(url: URL = FileWidgetsSupportPaths.desktopVisibilityStateURL) {
        self.url = url
    }

    public func load() -> DesktopVisibilityState {
        switch loadResult() {
        case .missing, .failed:
            return DesktopVisibilityState()
        case .loaded(let state):
            return state
        }
    }

    public func loadResult() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            return .loaded(try JSONDecoder().decode(DesktopVisibilityState.self, from: data))
        } catch {
            return .failed(backupURL: backupUnreadableState())
        }
    }

    private func backupUnreadableState() -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let backupURL = url
                .deletingLastPathComponent()
                .appendingPathComponent("desktop-visibility-state-corrupt-\(Self.backupTimestamp()).json", isDirectory: false)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
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

public struct DesktopVisibilityRestoreResult {
    public let completedEntries: [String: Bool]
    public let unresolvedEntries: [String: Bool]
    public let unresolvedFileIdentities: [String: String]

    public var unresolvedCount: Int {
        unresolvedEntries.count
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

    public static func processMatches(pid: Int32, executablePath: String?) -> Bool {
        guard processExists(pid) else { return false }
        guard let executablePath,
              executablePath.isEmpty == false else {
            return true
        }
        guard let currentExecutablePath = processExecutablePath(for: pid) else {
            return false
        }

        return URL(fileURLWithPath: currentExecutablePath).standardizedFileURL.path
            == URL(fileURLWithPath: executablePath).standardizedFileURL.path
    }

    public static func processExecutablePath(for pid: Int32) -> String? {
        guard pid > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }

        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: pathBytes, as: UTF8.self)
    }

    public static func restoreManagedEntries(
        _ managedEntries: [String: Bool],
        fileIdentities: [String: String] = [:]
    ) -> DesktopVisibilityRestoreResult {
        var completedEntries: [String: Bool] = [:]
        var unresolvedEntries: [String: Bool] = [:]
        var unresolvedFileIdentities: [String: String] = [:]

        for (path, wasHiddenBeforeManaging) in managedEntries {
            let expectedIdentity = fileIdentities[path]
            if restoreManagedEntry(
                path: path,
                wasHiddenBeforeManaging: wasHiddenBeforeManaging,
                expectedIdentity: expectedIdentity
            ) {
                completedEntries[path] = wasHiddenBeforeManaging
                continue
            }

            unresolvedEntries[path] = wasHiddenBeforeManaging
            if let expectedIdentity {
                unresolvedFileIdentities[path] = expectedIdentity
            }
        }

        return DesktopVisibilityRestoreResult(
            completedEntries: completedEntries,
            unresolvedEntries: unresolvedEntries,
            unresolvedFileIdentities: unresolvedFileIdentities
        )
    }

    public static func unresolvedState(
        from result: DesktopVisibilityRestoreResult,
        activeSessionID: String?,
        ownerPID: Int32?,
        ownerExecutablePath: String? = nil
    ) -> DesktopVisibilityState {
        if result.unresolvedEntries.isEmpty {
            return DesktopVisibilityState()
        }

        return DesktopVisibilityState(
            activeSessionID: activeSessionID,
            ownerPID: ownerPID,
            ownerExecutablePath: ownerExecutablePath,
            managedEntries: result.unresolvedEntries,
            managedFileIdentities: result.unresolvedFileIdentities
        )
    }

    private static func restoreManagedEntry(
        path: String,
        wasHiddenBeforeManaging: Bool,
        expectedIdentity: String?
    ) -> Bool {
        guard wasHiddenBeforeManaging == false else {
            return true
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return true
        }

        guard let expectedIdentity else {
            return setHidden(false, for: URL(fileURLWithPath: path))
        }

        let url = URL(fileURLWithPath: path)
        guard let currentIdentity = fileIdentity(for: url) else {
            return false
        }

        guard currentIdentity == expectedIdentity else {
            return currentHiddenState(for: url) == false
        }

        return setHidden(false, for: url)
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
