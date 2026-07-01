import Foundation
import OSLog

@MainActor
final class AutoTraySettingsStore {
    static let shared = AutoTraySettingsStore()

    private let fileManager = FileManager.default
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.filetray.app",
        category: "AutoTraySettings"
    )
    private let storeURL: URL

    private init() {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryURL = applicationSupportURL
            .appendingPathComponent("FileWidgets", isDirectory: true)
        self.storeURL = directoryURL.appendingPathComponent("auto-tray-settings.json", isDirectory: false)
    }

    func load() -> AutoTraySettings {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return .defaultValue
        }

        do {
            let data = try Data(contentsOf: storeURL)
            return try JSONDecoder().decode(AutoTraySettings.self, from: data)
        } catch {
            let backupURL = backupUnreadableStore()
            logger.error(
                "Failed to load auto tray settings from \(self.storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public). Backup: \(backupURL?.path ?? "none", privacy: .public)"
            )
            return .defaultValue
        }
    }

    func save(_ settings: AutoTraySettings) {
        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(settings)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            logger.error(
                "Failed to save auto tray settings to \(self.storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func backupUnreadableStore() -> URL? {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return nil
        }

        do {
            let backupURL = storeURL
                .deletingLastPathComponent()
                .appendingPathComponent("auto-tray-settings-corrupt-\(Self.backupTimestamp()).json", isDirectory: false)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: storeURL, to: backupURL)
            return backupURL
        } catch {
            logger.error(
                "Failed to back up unreadable auto tray settings at \(self.storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
