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
        XCTAssertEqual(state.managedEntries["/Users/example/Desktop/report.pdf"], false)
        XCTAssertTrue(state.managedFileIdentities.isEmpty)
    }

    func testVisibilityStatePersistsFileIdentities() throws {
        let state = DesktopVisibilityState(
            activeSessionID: "session",
            ownerPID: 42,
            managedEntries: ["/Users/example/Desktop/report.pdf": false],
            managedFileIdentities: ["/Users/example/Desktop/report.pdf": "1:99"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DesktopVisibilityState.self, from: data)

        XCTAssertEqual(decoded.managedEntries, state.managedEntries)
        XCTAssertEqual(decoded.managedFileIdentities, state.managedFileIdentities)
    }
}
