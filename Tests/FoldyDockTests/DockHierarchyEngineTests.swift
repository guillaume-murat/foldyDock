import XCTest
@testable import FoldyDock

final class DockHierarchyEngineTests: XCTestCase {

    private func makeApp(title: String, bundleId: String = "com.test.app", isPinned: Bool = true) -> DockItem {
        DockItem(
            id: UUID(),
            type: .app,
            title: title,
            bundleIdentifier: bundleId,
            isPinned: isPinned
        )
    }

    private func makeFolder(title: String = "FOLDER", items: [DockItem]) -> DockItem {
        DockItem(
            id: UUID(),
            type: .folder,
            title: title,
            isPinned: true,
            subItems: items
        )
    }

    // MARK: - Merging Tests

    func testMergeTwoAppsCreatesFolder() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let sep = DockItem(type: .separator)
        var engine = DockHierarchyEngine(items: [app1, app2, sep])

        let success = engine.merge(sourceId: app1.id, targetId: app2.id, folderName: "Dossier")

        XCTAssertTrue(success)
        XCTAssertEqual(engine.items.count, 2)
        XCTAssertEqual(engine.items[0].type, .folder)
        XCTAssertEqual(engine.items[0].title, "DOSSIER")
        XCTAssertEqual(engine.items[0].subItems?.count, 2)
        XCTAssertEqual(engine.items[0].subItems?[0].id, app2.id)
        XCTAssertEqual(engine.items[0].subItems?[1].id, app1.id)
        XCTAssertEqual(engine.items[1].id, sep.id)
    }

    func testMergeAppIntoExistingFolder() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let folder = makeFolder(title: "WORK", items: [app1, app2])
        let app3 = makeApp(title: "App 3")
        var engine = DockHierarchyEngine(items: [folder, app3])

        let success = engine.merge(sourceId: app3.id, targetId: folder.id)

        XCTAssertTrue(success)
        XCTAssertEqual(engine.items.count, 1)
        XCTAssertEqual(engine.items[0].subItems?.count, 3)
        XCTAssertEqual(engine.items[0].subItems?[2].id, app3.id)
    }

    func testMergeFolderIntoFolderFlattensWithoutNesting() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let folder1 = makeFolder(title: "F1", items: [app1, app2])

        let app3 = makeApp(title: "App 3")
        let app4 = makeApp(title: "App 4")
        let folder2 = makeFolder(title: "F2", items: [app3, app4])

        var engine = DockHierarchyEngine(items: [folder1, folder2])

        let success = engine.merge(sourceId: folder2.id, targetId: folder1.id)

        XCTAssertTrue(success)
        XCTAssertEqual(engine.items.count, 1)
        XCTAssertEqual(engine.items[0].subItems?.count, 4)
        // No sub-item should be a folder (depth == 1)
        XCTAssertFalse(engine.items[0].subItems?.contains(where: { $0.type == .folder }) ?? true)
    }

    func testMergeUnpinnedAppPromotesToPinnedInsideFolder() {
        let app1 = makeApp(title: "App 1", isPinned: true)
        let unpinnedApp = makeApp(title: "Running App", isPinned: false)
        var unpinnedList = [unpinnedApp]

        var engine = DockHierarchyEngine(items: [app1])

        let success = engine.merge(
            sourceId: unpinnedApp.id,
            targetId: app1.id,
            unpinnedItems: &unpinnedList,
            folderName: "Dossier"
        )

        XCTAssertTrue(success)
        XCTAssertTrue(unpinnedList.isEmpty)
        XCTAssertEqual(engine.items.count, 1)
        XCTAssertEqual(engine.items[0].type, .folder)
        let subItems = engine.items[0].subItems ?? []
        XCTAssertEqual(subItems.count, 2)
        XCTAssertTrue(subItems[0].isPinned)
        XCTAssertTrue(subItems[1].isPinned)
        XCTAssertEqual(subItems[1].id, unpinnedApp.id)
    }

    // MARK: - Dissolution Tests

    func testDissolveFolderExpandsAllItems() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let app3 = makeApp(title: "App 3")
        let folder = makeFolder(title: "MY FOLDER", items: [app1, app2])
        var engine = DockHierarchyEngine(items: [app3, folder])

        let success = engine.dissolveFolder(folderId: folder.id)

        XCTAssertTrue(success)
        XCTAssertEqual(engine.items.count, 3)
        XCTAssertEqual(engine.items[0].id, app3.id)
        XCTAssertEqual(engine.items[1].id, app1.id)
        XCTAssertEqual(engine.items[2].id, app2.id)
    }

    func testRemoveFromFolderExtractsAndPlacesNextToFolder() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let app3 = makeApp(title: "App 3")
        let folder = makeFolder(title: "TOOLS", items: [app1, app2, app3])
        var engine = DockHierarchyEngine(items: [folder])

        let result = engine.removeFromFolder(subItemId: app2.id, folderId: folder.id)

        XCTAssertNotNil(result.removedItem)
        XCTAssertEqual(result.removedItem?.id, app2.id)
        XCTAssertFalse(result.dissolved)
        XCTAssertEqual(engine.items.count, 2)
        XCTAssertEqual(engine.items[0].type, .folder)
        XCTAssertEqual(engine.items[0].subItems?.count, 2)
        XCTAssertEqual(engine.items[1].id, app2.id)
    }

    func testRemoveFromFolderWithTwoItemsAutoDissolvesSingleton() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let folder = makeFolder(title: "PAIR", items: [app1, app2])
        var engine = DockHierarchyEngine(items: [folder])

        let result = engine.removeFromFolder(subItemId: app2.id, folderId: folder.id)

        XCTAssertNotNil(result.removedItem)
        XCTAssertEqual(result.removedItem?.id, app2.id)
        XCTAssertTrue(result.dissolved)
        // Folder should be dissolved into app1, with app2 inserted immediately after
        XCTAssertEqual(engine.items.count, 2)
        XCTAssertEqual(engine.items[0].id, app1.id)
        XCTAssertEqual(engine.items[0].type, .app)
        XCTAssertEqual(engine.items[1].id, app2.id)
        XCTAssertEqual(engine.items[1].type, .app)
    }

    // MARK: - Reordering Tests

    func testMoveItemBeforeAndAfter() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let app3 = makeApp(title: "App 3")
        var engine = DockHierarchyEngine(items: [app1, app2, app3])

        // Move App 1 after App 2
        let successAfter = engine.moveItem(sourceId: app1.id, targetId: app2.id, placement: .after)
        XCTAssertTrue(successAfter)
        XCTAssertEqual(engine.items.map(\.id), [app2.id, app1.id, app3.id])

        // Move App 3 before App 2
        let successBefore = engine.moveItem(sourceId: app3.id, targetId: app2.id, placement: .before)
        XCTAssertTrue(successBefore)
        XCTAssertEqual(engine.items.map(\.id), [app3.id, app2.id, app1.id])
    }

    func testMoveItemToEnd() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let app3 = makeApp(title: "App 3")
        var unpinned: [DockItem] = []
        var engine = DockHierarchyEngine(items: [app1, app2, app3])

        let success = engine.moveItemToEnd(sourceId: app1.id, unpinnedItems: &unpinned)
        XCTAssertTrue(success)
        XCTAssertEqual(engine.items.map(\.id), [app2.id, app3.id, app1.id])
    }

    func testMoveSubItemReordering() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let app3 = makeApp(title: "App 3")
        let folder = makeFolder(title: "TEST", items: [app1, app2, app3])
        var engine = DockHierarchyEngine(items: [folder])

        // Move App 1 after App 2
        let success = engine.moveSubItem(folderId: folder.id, sourceId: app1.id, targetId: app2.id, placement: .after)
        XCTAssertTrue(success)
        let subIds = engine.items[0].subItems?.map(\.id) ?? []
        XCTAssertEqual(subIds, [app2.id, app1.id, app3.id])
    }

    // MARK: - CRUD & Invariant Tests

    func testInsertSeparator() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        var engine = DockHierarchyEngine(items: [app1, app2])

        engine.insertSeparator(at: 1)
        XCTAssertEqual(engine.items.count, 3)
        XCTAssertEqual(engine.items[1].type, .separator)
    }

    func testCreateEmptyFolderAndRename() {
        var engine = DockHierarchyEngine(items: [])
        engine.createEmptyFolder(at: 0, title: "NEW")

        XCTAssertEqual(engine.items.count, 1)
        XCTAssertEqual(engine.items[0].type, .folder)
        XCTAssertEqual(engine.items[0].title, "NEW")
        XCTAssertEqual(engine.items[0].subItems?.count, 0)

        let renamed = engine.renameFolder(folderId: engine.items[0].id, newTitle: "DEV")
        XCTAssertTrue(renamed)
        XCTAssertEqual(engine.items[0].title, "DEV")
    }

    func testRemoveItemDirectlyOrFromFolder() {
        let app1 = makeApp(title: "App 1")
        let app2 = makeApp(title: "App 2")
        let app3 = makeApp(title: "App 3")
        let folder = makeFolder(title: "FOLDER", items: [app2, app3])
        var engine = DockHierarchyEngine(items: [app1, folder])

        // Remove root item app1
        let removedRoot = engine.removeItem(itemId: app1.id)
        XCTAssertTrue(removedRoot)
        XCTAssertEqual(engine.items.count, 1)
        XCTAssertEqual(engine.items[0].id, folder.id)

        // Remove app2 from folder -> folder had 2 items [app2, app3], so removing app2 auto-dissolves folder to app3
        let removedSub = engine.removeItem(itemId: app2.id)
        XCTAssertTrue(removedSub)
        XCTAssertEqual(engine.items.count, 1)
        XCTAssertEqual(engine.items[0].type, .app)
        XCTAssertEqual(engine.items[0].id, app3.id)
    }
}
