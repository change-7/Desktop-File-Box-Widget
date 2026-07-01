import FileWidgetsSupport
import XCTest

final class DesktopVisibilityStateTests: XCTestCase {
    func testLegacyVisibilityStateDecodesWithoutFileIdentities() throws {
        let data = """
        {
          "activeSessionID": "session",
          "ownerPID": 42,
          "managedEntries": {
            "/Users/example/Desktop/report.pdf": false
          }
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(DesktopVisibilityState.self, from: data)

        XCTAssertEqual(state.activeSessionID, "session")
        XCTAssertEqual(state.ownerPID, 42)
        XCTAssertNil(state.ownerExecutablePath)
        XCTAssertEqual(state.managedEntries["/Users/example/Desktop/report.pdf"], false)
        XCTAssertTrue(state.managedFileIdentities.isEmpty)
    }

    func testVisibilityStatePersistsFileIdentities() throws {
        let state = DesktopVisibilityState(
            activeSessionID: "session",
            ownerPID: 42,
            ownerExecutablePath: "/Applications/File Tray.app/Contents/MacOS/File Tray",
            managedEntries: ["/Users/example/Desktop/report.pdf": false],
            managedFileIdentities: ["/Users/example/Desktop/report.pdf": "1:99"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DesktopVisibilityState.self, from: data)

        XCTAssertEqual(decoded.managedEntries, state.managedEntries)
        XCTAssertEqual(decoded.managedFileIdentities, state.managedFileIdentities)
        XCTAssertEqual(decoded.ownerExecutablePath, state.ownerExecutablePath)
    }

    func testRestoreManagedEntriesKeepsHiddenMismatchedIdentityUnresolved() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let url = temporaryDirectory.appendingPathComponent("hidden.txt", isDirectory: false)
        try "content".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(DesktopVisibilitySupport.setHidden(true, for: url))

        let result = DesktopVisibilitySupport.restoreManagedEntries(
            [url.path: false],
            fileIdentities: [url.path: "wrong-identity"]
        )

        XCTAssertNil(result.completedEntries[url.path])
        XCTAssertEqual(result.unresolvedEntries[url.path], false)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
    }

    func testRestoreManagedEntriesDropsVisibleMismatchedIdentity() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let url = temporaryDirectory.appendingPathComponent("visible.txt", isDirectory: false)
        try "content".write(to: url, atomically: true, encoding: .utf8)

        let result = DesktopVisibilitySupport.restoreManagedEntries(
            [url.path: false],
            fileIdentities: [url.path: "wrong-identity"]
        )

        XCTAssertEqual(result.completedEntries[url.path], false)
        XCTAssertNil(result.unresolvedEntries[url.path])
        XCTAssertEqual(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden, false)
    }

    func testRestoreManagedEntriesRestoresMatchingHiddenFile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let url = temporaryDirectory.appendingPathComponent("hidden.txt", isDirectory: false)
        try "content".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(DesktopVisibilitySupport.setHidden(true, for: url))

        let identity = try XCTUnwrap(DesktopVisibilitySupport.fileIdentity(for: url))
        let result = DesktopVisibilitySupport.restoreManagedEntries(
            [url.path: false],
            fileIdentities: [url.path: identity]
        )

        XCTAssertEqual(result.completedEntries[url.path], false)
        XCTAssertNil(result.unresolvedEntries[url.path])
        XCTAssertEqual(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden, false)
    }

    func testVisibilityStateStoreBacksUpUnreadableState() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let stateURL = temporaryDirectory.appendingPathComponent("desktop-visibility-state.json", isDirectory: false)
        try "not-json".write(to: stateURL, atomically: true, encoding: .utf8)

        let result = DesktopVisibilityStateStore(url: stateURL).loadResult()
        guard case .failed(let backupURL?) = result else {
            return XCTFail("Expected unreadable state to be reported with a backup URL")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "not-json")
    }
}
