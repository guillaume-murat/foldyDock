import XCTest
@testable import FoldyDock

final class DockItemTests: XCTestCase {
    func testSerializationAndDeserialization() throws {
        let app1 = DockItem(
            type: .app,
            title: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appPath: "/Applications/Safari.app",
            isPinned: true
        )

        let app2 = DockItem(
            type: .app,
            title: "Notes",
            bundleIdentifier: "com.apple.Notes",
            appPath: "/System/Applications/Notes.app",
            isPinned: true
        )

        let folder = DockItem(
            type: .folder,
            title: "Mes Outils",
            isPinned: true,
            subItems: [app1, app2]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(folder)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DockItem.self, from: data)

        XCTAssertEqual(decoded.id, folder.id)
        XCTAssertEqual(decoded.title, "Mes Outils")
        XCTAssertEqual(decoded.type, .folder)
        XCTAssertEqual(decoded.subItems?.count, 2)
        XCTAssertEqual(decoded.subItems?[0].title, "Safari")
        XCTAssertEqual(decoded.subItems?[1].title, "Notes")
    }

    func testAllBundleIdentifiers() {
        let app1 = DockItem(
            type: .app,
            title: "Finder",
            bundleIdentifier: "com.apple.finder"
        )
        XCTAssertEqual(app1.allBundleIdentifiers, ["com.apple.finder"])

        let app2 = DockItem(
            type: .app,
            title: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )

        let folder = DockItem(
            type: .folder,
            title: "Système",
            subItems: [app1, app2]
        )

        XCTAssertEqual(Set(folder.allBundleIdentifiers), Set(["com.apple.finder", "com.apple.Terminal"]))
    }

    func testIsRunningCheck() {
        let app = DockItem(
            type: .app,
            title: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )

        let runningSet: Set<String> = ["com.apple.Safari", "com.apple.finder"]
        XCTAssertTrue(app.isRunning(in: runningSet))

        let nonRunningSet: Set<String> = ["com.apple.Terminal"]
        XCTAssertFalse(app.isRunning(in: nonRunningSet))
    }

    func testIsFinder() {
        let finder = DockItem(type: .app, title: "Finder", bundleIdentifier: "com.apple.finder")
        XCTAssertTrue(finder.isFinder)

        let terminal = DockItem(type: .app, title: "Terminal", bundleIdentifier: "com.apple.Terminal")
        XCTAssertFalse(terminal.isFinder)

        let folder = DockItem(type: .folder, title: "Finder")
        XCTAssertFalse(folder.isFinder)
    }
}
