import XCTest
@testable import FoldyDock

@MainActor
final class DockViewModelTests: XCTestCase {
    var tempDirectory: URL!
    var persistenceService: DockPersistenceService!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        persistenceService = DockPersistenceService(customDirectoryURL: tempDirectory)
    }

    override func tearDown() async throws {
        AppObserverService.shared.refreshRunningApps()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    func testMergeTwoAppsIntoFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let app3 = DockItem(type: .app, title: "App 3", bundleIdentifier: "com.test.app3")

        let config = DockConfig(items: [app1, app2, app3])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.items.count, 3)

        // Merge app1 onto app2
        vm.mergeIntoFolder(sourceId: app1.id, targetId: app2.id, folderName: "Dossier Test")

        XCTAssertEqual(vm.items.count, 2)
        guard let folder = vm.items.first(where: { $0.type == DockItemType.folder }) else {
            XCTFail("Folder was not created")
            return
        }

        XCTAssertEqual(folder.title, "DOSSIER TEST")
        XCTAssertEqual(folder.subItems?.count, 2)
        XCTAssertEqual(folder.subItems?[0].id, app2.id)
        XCTAssertEqual(folder.subItems?[1].id, app1.id)
    }

    func testRenameFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let folder = DockItem(type: .folder, title: "Ancien Nom", subItems: [app1, app2])

        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        vm.renameFolder(folderId: folder.id, newTitle: "Nouveau Nom")

        XCTAssertEqual(vm.items[0].title, "NOUVEAU NOM")
    }

    func testReorderItems() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let app3 = DockItem(type: .app, title: "App 3", bundleIdentifier: "com.test.app3")

        let config = DockConfig(items: [app1, app2, app3])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Move app3 to app1's place (before app1)
        vm.moveItem(sourceId: app3.id, targetId: app1.id, placement: .before)

        XCTAssertEqual(vm.items[0].id, app3.id)
        XCTAssertEqual(vm.items[1].id, app1.id)
        XCTAssertEqual(vm.items[2].id, app2.id)
    }

    func testReorderItemPlacementAfter() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let app3 = DockItem(type: .app, title: "App 3", bundleIdentifier: "com.test.app3")

        let config = DockConfig(items: [app1, app2, app3])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Move app1 after app2
        vm.moveItem(sourceId: app1.id, targetId: app2.id, placement: .after)

        XCTAssertEqual(vm.items[0].id, app2.id)
        XCTAssertEqual(vm.items[1].id, app1.id)
        XCTAssertEqual(vm.items[2].id, app3.id)
    }

    func testReorderFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let subApp = DockItem(type: .app, title: "Sub", bundleIdentifier: "com.test.sub")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [subApp])
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")

        let config = DockConfig(items: [app1, folder, app2])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Move folder before app1
        vm.moveItem(sourceId: folder.id, targetId: app1.id, placement: .before)

        XCTAssertEqual(vm.items[0].id, folder.id)
        XCTAssertEqual(vm.items[1].id, app1.id)
        XCTAssertEqual(vm.items[2].id, app2.id)

        // Move folder after app2
        vm.moveItem(sourceId: folder.id, targetId: app2.id, placement: .after)

        XCTAssertEqual(vm.items[0].id, app1.id)
        XCTAssertEqual(vm.items[1].id, app2.id)
        XCTAssertEqual(vm.items[2].id, folder.id)
    }

    func testMoveItemToEnd() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let app3 = DockItem(type: .app, title: "App 3", bundleIdentifier: "com.test.app3")

        let config = DockConfig(items: [app1, app2, app3])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        vm.moveItemToEnd(sourceId: app1.id)

        XCTAssertEqual(vm.items[0].id, app2.id)
        XCTAssertEqual(vm.items[1].id, app3.id)
        XCTAssertEqual(vm.items[2].id, app1.id)
    }

    func testDissolveFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1, app2])

        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        vm.dissolveFolder(folderId: folder.id)

        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(vm.items[0].id, app1.id)
        XCTAssertEqual(vm.items[1].id, app2.id)
    }

    func testMergeUnpinnedAppIntoExistingFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1, app2])

        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Simulate an unpinned running app
        let unpinnedApp = DockItem(type: .app, title: "Unpinned", bundleIdentifier: "com.test.unpinned", isPinned: false)
        vm.unpinnedRunningItems = [unpinnedApp]

        // Merge unpinnedApp into the folder
        vm.mergeIntoFolder(sourceId: unpinnedApp.id, targetId: folder.id)

        XCTAssertTrue(vm.unpinnedRunningItems.isEmpty)
        guard let updatedFolder = vm.items.first(where: { $0.id == folder.id }) else {
            XCTFail("Folder not found")
            return
        }
        XCTAssertEqual(updatedFolder.subItems?.count, 3)
        XCTAssertTrue(updatedFolder.subItems?.contains(where: { $0.id == unpinnedApp.id }) ?? false)
    }

    func testToggleFolderPopoverClosesOpenFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1])
        let vm = DockViewModel(persistenceService: persistenceService)

        // Open folder
        vm.toggleFolderPopover(folder)
        XCTAssertEqual(vm.activeFolder?.id, folder.id)

        // Toggle again -> closes folder
        vm.toggleFolderPopover(folder)
        XCTAssertNil(vm.activeFolder)
    }

    func testToggleFolderPopoverPreventsImmediateReopenAfterOutsideDismiss() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1])
        let vm = DockViewModel(persistenceService: persistenceService)

        // Open folder
        vm.toggleFolderPopover(folder)
        XCTAssertEqual(vm.activeFolder?.id, folder.id)

        // Simulate outside click dismissing the popover in SwiftUI
        vm.closeFolderPopover()
        XCTAssertNil(vm.activeFolder)

        // Click event immediately hits the icon right after dismiss (within 0.4s)
        vm.toggleFolderPopover(folder)
        // Must stay closed!
        XCTAssertNil(vm.activeFolder)

        // Next click after debounce has reset can open it again
        vm.toggleFolderPopover(folder)
        XCTAssertEqual(vm.activeFolder?.id, folder.id)
    }

    func testHandleFolderMiddleClickTerminatesApp() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1, app2])

        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        vm.toggleFolderPopover(folder)

        // Set simulated item frames in the folder popover
        let frame1 = CGRect(x: 10, y: 10, width: 60, height: 60)
        let frame2 = CGRect(x: 80, y: 10, width: 60, height: 60)
        vm.folderItemFrames = [
            app1.id: frame1,
            app2.id: frame2
        ]

        // Middle-click on app1
        vm.handleFolderMiddleClick(at: CGPoint(x: 30, y: 30))

        // Middle-click outside any app
        vm.handleFolderMiddleClick(at: CGPoint(x: 200, y: 200))
    }

    func testTriggerBounceForStandaloneApp() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertFalse(vm.isItemBouncing(app1))

        vm.triggerBounce(for: app1)
        XCTAssertTrue(vm.isItemBouncing(app1))
    }

    func testTriggerBounceForAppInsideFolderBouncesFolderAndApp() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1])
        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertFalse(vm.isItemBouncing(app1))
        XCTAssertFalse(vm.isItemBouncing(folder))

        // Launch app1 inside folder
        vm.triggerBounce(for: app1)

        // Both the app itself AND its parent folder must bounce!
        XCTAssertTrue(vm.isItemBouncing(app1))
        XCTAssertTrue(vm.isItemBouncing(folder))
    }

    func testRunningSubItemIdsForFolder() {
        let runningApp = DockItem(type: .app, title: "Finder", bundleIdentifier: "com.apple.finder")
        let nonRunningApp = DockItem(type: .app, title: "Fake", bundleIdentifier: "com.nonexistent.fakeapp.unique123")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [runningApp, nonRunningApp])
        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        let runningIds = vm.runningSubItemIds(for: folder)

        // Finder is running on macOS, while fakeapp is not
        XCTAssertTrue(runningIds.contains(runningApp.id))
        XCTAssertFalse(runningIds.contains(nonRunningApp.id))
    }

    func testRunningSubItemsForFolderReturnsOrderedRunningApps() {
        let runningApp = DockItem(type: .app, title: "Finder", bundleIdentifier: "com.apple.finder")
        let nonRunningApp = DockItem(type: .app, title: "Fake", bundleIdentifier: "com.nonexistent.fakeapp.unique123")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [runningApp, nonRunningApp])
        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        let runningItems = vm.runningSubItems(for: folder)

        XCTAssertEqual(runningItems.count, 1)
        XCTAssertEqual(runningItems.first?.id, runningApp.id)
        XCTAssertEqual(runningItems.first?.title, "Finder")

        // Non-running app must not be in runningSubItems
        XCTAssertFalse(runningItems.contains(where: { $0.id == nonRunningApp.id }))
    }

    func testFolderWithMoreThanFourApps() {
        let apps = (1...7).map {
            DockItem(type: .app, title: "App \($0)", bundleIdentifier: "com.test.app\($0)")
        }
        let folder = DockItem(type: .folder, title: "Grand Dossier", subItems: apps)
        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].subItems?.count, 7)

        // All 7 items exist in folder
        for i in 1...7 {
            XCTAssertTrue(vm.items[0].subItems?.contains(where: { $0.title == "App \(i)" }) ?? false)
        }
    }

    func testUpdateIconSizeExpandsAndShrinks() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let config = DockConfig(iconSize: 52.0, items: [app1, app2])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.config.iconSize, 52.0)

        // Dragging right edge outward (positive translationX) increases iconSize
        vm.startResizing()
        XCTAssertTrue(vm.isResizing)
        vm.updateIconSize(translationX: 30.0, isRightEdge: true)
        XCTAssertGreaterThan(vm.config.iconSize, 52.0)

        // Dragging right edge inward (negative translationX) decreases iconSize
        vm.updateIconSize(translationX: -30.0, isRightEdge: true)
        XCTAssertLessThan(vm.config.iconSize, 52.0)

        // Reset and test left edge
        vm.finishResizing()
        XCTAssertFalse(vm.isResizing)
        let baseSize = vm.config.iconSize

        // Dragging left edge outward (negative translationX = moving to the left) increases iconSize
        vm.startResizing()
        vm.updateIconSize(translationX: -30.0, isRightEdge: false)
        XCTAssertGreaterThan(vm.config.iconSize, baseSize)

        // Dragging left edge inward (positive translationX = moving to the right) decreases iconSize
        vm.updateIconSize(translationX: 30.0, isRightEdge: false)
        XCTAssertLessThan(vm.config.iconSize, baseSize)
    }

    func testIconSizeClampingMinAndMax() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(iconSize: 52.0, items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Drag right edge extremely far outward
        vm.startResizing()
        vm.updateIconSize(translationX: 5000.0, isRightEdge: true)
        XCTAssertEqual(vm.config.iconSize, DockViewModel.maxIconSize)

        // Drag right edge extremely far inward
        vm.updateIconSize(translationX: -5000.0, isRightEdge: true)
        XCTAssertEqual(vm.config.iconSize, DockViewModel.minIconSize)
    }

    func testFinishResizingPersistsToDisk() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(iconSize: 52.0, items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        vm.startResizing()
        vm.updateIconSize(translationX: 40.0, isRightEdge: true)
        let newSize = vm.config.iconSize
        XCTAssertNotEqual(newSize, 52.0)

        vm.finishResizing()
        XCTAssertFalse(vm.isResizing)

        // Verify loaded config from disk has the new iconSize
        let loaded = persistenceService.loadConfig()
        XCTAssertEqual(loaded.iconSize, newSize)
    }

    func testRemoveUnpinnedItem() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        let unpinnedApp = DockItem(type: .app, title: "Phone", bundleIdentifier: "com.apple.mobilephone", isPinned: false)
        vm.unpinnedRunningItems = [unpinnedApp]

        XCTAssertEqual(vm.unpinnedRunningItems.count, 1)

        // Remove the unpinned item
        vm.removeItem(itemId: unpinnedApp.id)

        XCTAssertTrue(vm.unpinnedRunningItems.isEmpty)
    }

    func testTerminateUnpinnedItemRemovesFromUnpinnedList() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        let unpinnedApp = DockItem(type: .app, title: "Phone", bundleIdentifier: "com.apple.mobilephone", isPinned: false)
        vm.unpinnedRunningItems = [unpinnedApp]

        XCTAssertEqual(vm.unpinnedRunningItems.count, 1)

        // Terminate unpinned item
        vm.terminate(item: unpinnedApp)

        XCTAssertTrue(vm.unpinnedRunningItems.isEmpty)
    }

    func testInsertSeparatorAtIndex() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let config = DockConfig(items: [app1, app2])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.items.count, 2)

        // Insert separator between App 1 and App 2
        vm.insertSeparator(at: 1)
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertEqual(vm.items[1].type, .separator)
        XCTAssertEqual(vm.items[1].title, "Séparateur")

        // Persisted to disk
        let loaded = persistenceService.loadConfig()
        XCTAssertEqual(loaded.items.count, 3)
        XCTAssertEqual(loaded.items[1].type, .separator)
    }

    func testCreateEmptyFolderAtIndex() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Create empty folder
        vm.createEmptyFolder(at: 0, title: "Mon Dossier")
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(vm.items[0].type, .folder)
        XCTAssertEqual(vm.items[0].title, "MON DOSSIER")
        XCTAssertEqual(vm.items[0].subItems?.count, 0)

        // Empty folder should not auto-dissolve
        XCTAssertEqual(vm.items.count, 2)
    }

    func testLegacySettingsItemFilteredOut() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let settingsItem = DockItem(type: .settings, title: "Paramètres FoldyDock")
        let config = DockConfig(items: [app1, settingsItem])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // The settings item should be automatically filtered out from dock items
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.bundleIdentifier, "com.test.app1")
        XCTAssertFalse(vm.items.contains { $0.type == .settings })

        vm.saveConfig()
        let loaded = persistenceService.loadConfig()
        XCTAssertFalse(loaded.items.contains { $0.type == .settings })
    }

    func testOpenSettingsWindowTrigger() {
        let vm = DockViewModel(persistenceService: persistenceService)
        var opened = false
        vm.onOpenSettingsWindow = {
            opened = true
        }

        vm.openSettingsWindow()
        XCTAssertTrue(opened)
    }

    func testRemoveSeparator() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let sep = DockItem(type: .separator, title: "Séparateur")
        let config = DockConfig(items: [app1, sep])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.items.count, 2)

        vm.removeItem(itemId: sep.id)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].id, app1.id)
    }

    func testInsertionIndexCalculation() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let app3 = DockItem(type: .app, title: "App 3", bundleIdentifier: "com.test.app3")
        let config = DockConfig(items: [app1, app2, app3])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Simulate itemFrames:
        // App 1: x: 10..70 (mid: 40)
        // App 2: x: 80..140 (mid: 110)
        // App 3: x: 150..210 (mid: 180)
        vm.itemFrames = [
            app1.id: CGRect(x: 10, y: 10, width: 60, height: 60),
            app2.id: CGRect(x: 80, y: 10, width: 60, height: 60),
            app3.id: CGRect(x: 150, y: 10, width: 60, height: 60)
        ]

        // Click to the left of App 1 (x: 20 < 40) -> index 0
        XCTAssertEqual(vm.insertionIndex(for: 20), 0)

        // Click between App 1 and App 2 (x: 75 -> between 40 and 110) -> index 1
        XCTAssertEqual(vm.insertionIndex(for: 75), 1)

        // Click between App 2 and App 3 (x: 145 -> between 110 and 180) -> index 2
        XCTAssertEqual(vm.insertionIndex(for: 145), 2)

        // Click to the right of App 3 (x: 220 >= 180) -> index 3
        XCTAssertEqual(vm.insertionIndex(for: 220), 3)
    }

    func testToggleTrashUpdatesConfigAndPersists() {
        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertTrue(vm.config.showTrash)

        vm.toggleTrash()
        XCTAssertFalse(vm.config.showTrash)

        let reloaded = persistenceService.loadConfig()
        XCTAssertFalse(reloaded.showTrash)

        vm.toggleTrash()
        XCTAssertTrue(vm.config.showTrash)
    }

    func testDropOnTrashRemovesPinnedItem() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let config = DockConfig(items: [app1, app2])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.items.count, 2)

        vm.dropOnTrash(sourceId: app1.id)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.id, app2.id)

        let reloaded = persistenceService.loadConfig()
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.id, app2.id)
    }

    func testDropOnTrashTerminatesUnpinnedApp() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let config = DockConfig(items: [app1])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)
        let unpinned = DockItem(type: .app, title: "Running 1", bundleIdentifier: "com.test.running1", isPinned: false)
        vm.unpinnedRunningItems = [unpinned]

        vm.dropOnTrash(sourceId: unpinned.id)
        XCTAssertTrue(vm.unpinnedRunningItems.isEmpty)
    }

    func testWindowCountReturnsZeroWhenAppNotRunning() {
        let app = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let vm = DockViewModel(persistenceService: persistenceService)
        vm.items = [app]

        XCTAssertEqual(vm.windowCount(for: app), 0)
    }

    func testWindowCountForRunningAppWithMultipleWindows() {
        let app = DockItem(type: .app, title: "Firefox", bundleIdentifier: "org.mozilla.firefox")
        let appObserver = AppObserverService.shared
        appObserver.setRunningBundleIdsForTesting(["org.mozilla.firefox"])
        appObserver.setWindowCountsForTesting(["org.mozilla.firefox": 2])

        let vm = DockViewModel(persistenceService: persistenceService, appObserver: appObserver)
        vm.items = [app]

        XCTAssertEqual(vm.windowCount(for: app), 2)
    }

    func testWindowCountForRunningAppWithZeroWindowsReturnsOne() {
        let app = DockItem(type: .app, title: "Finder", bundleIdentifier: "com.apple.finder")
        let appObserver = AppObserverService.shared
        appObserver.setRunningBundleIdsForTesting(["com.apple.finder"])
        appObserver.setWindowCountsForTesting(["com.apple.finder": 0])

        let vm = DockViewModel(persistenceService: persistenceService, appObserver: appObserver)
        vm.items = [app]

        // When running with 0 windows, displays 1 dot to indicate process is active
        XCTAssertEqual(vm.windowCount(for: app), 1)
    }

    func testWindowCountForFolderReturnsOneWhenAnyAppIsRunning() {
        let sub1 = DockItem(type: .app, title: "Sub 1", bundleIdentifier: "com.test.sub1")
        let sub2 = DockItem(type: .app, title: "Sub 2", bundleIdentifier: "com.test.sub2")
        let folder = DockItem(type: .folder, title: "My Folder", subItems: [sub1, sub2])

        let appObserver = AppObserverService.shared
        appObserver.setRunningBundleIdsForTesting(["com.test.sub1", "com.test.sub2"])
        appObserver.setWindowCountsForTesting(["com.test.sub1": 2, "com.test.sub2": 3])

        let vm = DockViewModel(persistenceService: persistenceService, appObserver: appObserver)
        vm.items = [folder]

        // Under folders, a single dot (1) is displayed if one or more sub-apps are running
        XCTAssertEqual(vm.windowCount(for: folder), 1)

        // When no sub-apps are running, returns 0
        appObserver.setRunningBundleIdsForTesting([])
        XCTAssertEqual(vm.windowCount(for: folder), 0)
    }

    func testSubItemWindowCountsReturnsCorrectCountsForRunningSubItems() {
        let sub1 = DockItem(type: .app, title: "Firefox", bundleIdentifier: "org.mozilla.firefox")
        let sub2 = DockItem(type: .app, title: "Chrome", bundleIdentifier: "com.google.Chrome")
        let sub3 = DockItem(type: .app, title: "Safari", bundleIdentifier: "com.apple.Safari")
        let folder = DockItem(type: .folder, title: "Browsers", subItems: [sub1, sub2, sub3])

        let appObserver = AppObserverService.shared
        appObserver.setRunningBundleIdsForTesting(["org.mozilla.firefox", "com.google.Chrome"])
        appObserver.setWindowCountsForTesting(["org.mozilla.firefox": 2, "com.google.Chrome": 1])

        let vm = DockViewModel(persistenceService: persistenceService, appObserver: appObserver)
        vm.items = [folder]

        let counts = vm.subItemWindowCounts(for: folder)
        XCTAssertEqual(counts[sub1.id], 2)
        XCTAssertEqual(counts[sub2.id], 1)
        XCTAssertNil(counts[sub3.id]) // Not running
    }

    func testMoveSubItemReordersInsideFolder() {
        let app1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.test.app1")
        let app2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.test.app2")
        let app3 = DockItem(type: .app, title: "App 3", bundleIdentifier: "com.test.app3")
        let folder = DockItem(type: .folder, title: "Dossier", subItems: [app1, app2, app3])

        let config = DockConfig(items: [folder])
        persistenceService.saveConfig(config)

        let vm = DockViewModel(persistenceService: persistenceService)

        // Move app3 before app1
        vm.moveSubItem(folderId: folder.id, sourceId: app3.id, targetId: app1.id, placement: .before)

        guard let updated = vm.items.first(where: { $0.id == folder.id }),
              let subs = updated.subItems else {
            XCTFail("Folder or subItems missing")
            return
        }

        XCTAssertEqual(subs.map(\.id), [app3.id, app1.id, app2.id])

        // Move app1 after app2
        vm.moveSubItem(folderId: folder.id, sourceId: app1.id, targetId: app2.id, placement: .after)

        guard let updated2 = vm.items.first(where: { $0.id == folder.id }),
              let subs2 = updated2.subItems else {
            XCTFail("Folder or subItems missing")
            return
        }

        XCTAssertEqual(subs2.map(\.id), [app3.id, app2.id, app1.id])

        // Verify persisted
        let loaded = persistenceService.loadConfig()
        let loadedFolder = loaded.items.first(where: { $0.id == folder.id })
        XCTAssertEqual(loadedFolder?.subItems?.map(\.id), [app3.id, app2.id, app1.id])
    }

    func testNewConfigOptionsDefaultValuesAndDockHeight() {
        let config = DockConfig.defaultConfig
        XCTAssertEqual(config.horizontalPadding, 12.0)
        XCTAssertEqual(config.verticalPadding, 12.0)
        XCTAssertEqual(config.labelDistance, 10.0)
        XCTAssertTrue(config.showAppTitles)
        XCTAssertTrue(config.showFolderTitles)
        XCTAssertEqual(config.dockHeight, 52.0 + 12.0 * 2)

        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.dockHeight, CGFloat(52.0 + 12.0 * 2))
    }

    func testNewConfigOptionsSerializationAndDeserialization() throws {
        let config = DockConfig(
            autohideEnabled: false,
            autohideDelay: 0.5,
            iconSize: 64.0,
            items: [],
            showTrash: false,
            horizontalPadding: 18.0,
            verticalPadding: 8.0,
            showAppTitles: false,
            showFolderTitles: false,
            labelDistance: 14.0
        )

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DockConfig.self, from: encoded)

        XCTAssertEqual(decoded.horizontalPadding, 18.0)
        XCTAssertEqual(decoded.verticalPadding, 8.0)
        XCTAssertEqual(decoded.labelDistance, 14.0)
        XCTAssertFalse(decoded.showAppTitles)
        XCTAssertFalse(decoded.showFolderTitles)
        XCTAssertEqual(decoded.dockHeight, 64.0 + 8.0 * 2)
    }

    func testUpdatingPaddingAndVisibilityPersistsConfig() {
        let vm = DockViewModel(persistenceService: persistenceService)
        vm.config.horizontalPadding = 20.0
        vm.config.verticalPadding = 16.0
        vm.config.showAppTitles = false
        vm.config.showFolderTitles = false
        vm.saveConfig()

        let reloaded = persistenceService.loadConfig()
        XCTAssertEqual(reloaded.horizontalPadding, 20.0)
        XCTAssertEqual(reloaded.verticalPadding, 16.0)
        XCTAssertFalse(reloaded.showAppTitles)
        XCTAssertFalse(reloaded.showFolderTitles)
    }

    func testShowDelayAndHideDelayConfigAndPersistence() throws {
        let config = DockConfig.defaultConfig
        XCTAssertEqual(config.showDelay, 0.0)
        XCTAssertEqual(config.hideDelay, 0.3)
        XCTAssertEqual(config.autohideDelay, 0.3)

        let vm = DockViewModel(persistenceService: persistenceService)
        var receivedConfig: DockConfig?
        vm.onConfigUpdated = { updated in
            receivedConfig = updated
        }

        vm.config.showDelay = 0.4
        vm.config.hideDelay = 0.8
        vm.saveConfig()

        XCTAssertNotNil(receivedConfig)
        XCTAssertEqual(receivedConfig?.showDelay, 0.4)
        XCTAssertEqual(receivedConfig?.hideDelay, 0.8)
        XCTAssertEqual(receivedConfig?.autohideDelay, 0.8)

        let reloaded = persistenceService.loadConfig()
        XCTAssertEqual(reloaded.showDelay, 0.4)
        XCTAssertEqual(reloaded.hideDelay, 0.8)
        XCTAssertEqual(reloaded.autohideDelay, 0.8)
    }

    func testVerticalPaddingUpTo48() {
        let vm = DockViewModel(persistenceService: persistenceService)
        vm.config.verticalPadding = 48.0
        XCTAssertEqual(vm.dockHeight, CGFloat(52.0 + 48.0 * 2))

        vm.saveConfig()
        let reloaded = persistenceService.loadConfig()
        XCTAssertEqual(reloaded.verticalPadding, 48.0)
        XCTAssertEqual(reloaded.dockHeight, 52.0 + 48.0 * 2)
    }

    func testLabelDistanceConfigAndPersistence() {
        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.config.labelDistance, 10.0)

        vm.config.labelDistance = 15.0
        vm.saveConfig()

        let reloaded = persistenceService.loadConfig()
        XCTAssertEqual(reloaded.labelDistance, 15.0)
    }

    func testAppLauncherConfigAndToggle() {
        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertTrue(vm.config.showAppLauncher)

        vm.toggleAppLauncher()
        XCTAssertFalse(vm.config.showAppLauncher)

        let reloaded = persistenceService.loadConfig()
        XCTAssertFalse(reloaded.showAppLauncher)

        vm.toggleAppLauncher()
        XCTAssertTrue(vm.config.showAppLauncher)
    }

    func testApplicationsLauncherOpenAndClose() {
        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertFalse(vm.isApplicationsLauncherOpen)

        vm.toggleApplicationsLauncher()
        XCTAssertTrue(vm.isApplicationsLauncherOpen)

        // Opening a folder should close the applications launcher
        let dummyFolder = DockItem(type: .folder, title: "Tools", subItems: [])
        vm.toggleFolderPopover(dummyFolder)
        XCTAssertFalse(vm.isApplicationsLauncherOpen)
        XCTAssertEqual(vm.activeFolder?.id, dummyFolder.id)

        // Opening applications launcher should close active folder
        vm.toggleApplicationsLauncher()
        XCTAssertTrue(vm.isApplicationsLauncherOpen)
        XCTAssertNil(vm.activeFolder)

        vm.closeApplicationsLauncher()
        XCTAssertFalse(vm.isApplicationsLauncherOpen)
    }

    func testAppDiscoveryScanInstalledApps() {
        let apps = AppDiscoveryService.scanInstalledApps()
        XCTAssertFalse(apps.isEmpty, "Scan should discover installed macOS applications")
        XCTAssertTrue(apps.contains(where: { $0.url.path.hasSuffix(".app") }))
    }

    func testPinInstalledApp() {
        let vm = DockViewModel(persistenceService: persistenceService)
        let initialCount = vm.items.count

        let testApp = InstalledApp(
            name: "Test App",
            bundleIdentifier: "com.test.uniqueApp",
            url: URL(fileURLWithPath: "/Applications/Test.app")
        )

        vm.pinInstalledApp(testApp)
        XCTAssertEqual(vm.items.count, initialCount + 1)
        let pinned = vm.items.last
        XCTAssertEqual(pinned?.title, "Test App")
        XCTAssertEqual(pinned?.bundleIdentifier, "com.test.uniqueApp")
        XCTAssertEqual(pinned?.appPath, "/Applications/Test.app")
        XCTAssertTrue(pinned?.isPinned ?? false)
    }

    func testHiddenAppOpacityConfigAndPersistence() {
        let vm = DockViewModel(persistenceService: persistenceService)
        XCTAssertEqual(vm.config.hiddenAppOpacity, 0.5)

        vm.config.hiddenAppOpacity = 0.35
        vm.saveConfig()

        let reloaded = persistenceService.loadConfig()
        XCTAssertEqual(reloaded.hiddenAppOpacity, 0.35)
    }

    func testIsItemHiddenForAppAndFolder() {
        let appObserver = AppObserverService()
        let vm = DockViewModel(persistenceService: persistenceService, appObserver: appObserver)

        let testApp = DockItem(type: .app, title: "Hidden App", bundleIdentifier: "com.test.hiddenApp", isPinned: true)
        let visibleApp = DockItem(type: .app, title: "Visible App", bundleIdentifier: "com.test.visibleApp", isPinned: true)

        appObserver.setRunningBundleIdsForTesting(["com.test.hiddenApp", "com.test.visibleApp"])
        appObserver.setHiddenAppBundleIdsForTesting(["com.test.hiddenApp"])

        XCTAssertTrue(vm.isItemHidden(testApp))
        XCTAssertFalse(vm.isItemHidden(visibleApp))

        // Folder where all running apps are hidden
        let folderAllHidden = DockItem(type: .folder, title: "All Hidden", isPinned: true, subItems: [testApp])
        XCTAssertTrue(vm.isItemHidden(folderAllHidden))

        // Folder with mixed apps
        let folderMixed = DockItem(type: .folder, title: "Mixed", isPinned: true, subItems: [testApp, visibleApp])
        XCTAssertFalse(vm.isItemHidden(folderMixed))
        XCTAssertEqual(vm.hiddenSubItemIds(for: folderMixed), [testApp.id])
    }

    func testLegacyConfigFieldsBackwardCompatibility() throws {
        // JSON containing legacy fields (liquidGlassIntensity, backgroundBlurRadius, showPinBadges)
        // should decode successfully into DockConfig without crashing
        let legacyJson = """
        {
            "autohideEnabled": true,
            "autohideDelay": 0.3,
            "showDelay": 0.0,
            "iconSize": 52.0,
            "items": [],
            "showTrash": true,
            "horizontalPadding": 12.0,
            "verticalPadding": 12.0,
            "showAppTitles": true,
            "showFolderTitles": true,
            "showPinBadges": true,
            "labelDistance": 10.0,
            "showAppLauncher": true,
            "hiddenAppOpacity": 0.5,
            "liquidGlassIntensity": 0.8,
            "backgroundBlurRadius": 20.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DockConfig.self, from: legacyJson)
        XCTAssertEqual(decoded.iconSize, 52.0)
        XCTAssertEqual(decoded.horizontalPadding, 12.0)
        XCTAssertEqual(decoded.verticalPadding, 12.0)
        XCTAssertTrue(decoded.showAppTitles)
        XCTAssertTrue(decoded.showFolderTitles)
    }
    func testLaunchAtLoginConfigAndToggle() {
        final class MockLaunchAtLoginProvider: LaunchAtLoginProviding, @unchecked Sendable {
            var isEnabled: Bool = false
            var setEnabledCallCount = 0

            func setEnabled(_ enabled: Bool) -> Bool {
                setEnabledCallCount += 1
                isEnabled = enabled
                return true
            }
        }

        let mockProvider = MockLaunchAtLoginProvider()
        mockProvider.isEnabled = false

        let vm = DockViewModel(
            persistenceService: persistenceService,
            appObserver: AppObserverService.shared,
            launchAtLoginService: mockProvider
        )

        XCTAssertFalse(vm.config.launchAtLogin)

        vm.setLaunchAtLogin(true)
        XCTAssertTrue(vm.config.launchAtLogin)
        XCTAssertTrue(mockProvider.isEnabled)
        XCTAssertEqual(mockProvider.setEnabledCallCount, 1)

        let reloaded = persistenceService.loadConfig()
        XCTAssertTrue(reloaded.launchAtLogin)

        vm.toggleLaunchAtLogin()
        XCTAssertFalse(vm.config.launchAtLogin)
        XCTAssertFalse(mockProvider.isEnabled)
        XCTAssertEqual(mockProvider.setEnabledCallCount, 2)
    }

    func testLaunchAtLoginSerializationAndDeserialization() throws {
        var config = DockConfig.defaultConfig
        config.launchAtLogin = true

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DockConfig.self, from: encoded)

        XCTAssertTrue(decoded.launchAtLogin)
    }

    func testLaunchAtLoginBackwardCompatibilityDefaultsToFalse() throws {
        let legacyJson = """
        {
            "autohideEnabled": true,
            "autohideDelay": 0.3,
            "showDelay": 0.0,
            "iconSize": 52.0,
            "items": [],
            "showTrash": true,
            "horizontalPadding": 12.0,
            "verticalPadding": 12.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DockConfig.self, from: legacyJson)
        XCTAssertFalse(decoded.launchAtLogin)
    }

    func testAppBundleURLForOpenInFinder() {
        let vm = DockViewModel(persistenceService: persistenceService)

        let byPath = DockItem(type: .app, title: "Calculator", bundleIdentifier: "com.apple.calculator",
                              appPath: "/System/Applications/Calculator.app")
        XCTAssertEqual(vm.appBundleURL(for: byPath)?.path, "/System/Applications/Calculator.app")

        let stalePath = DockItem(type: .app, title: "Finder", bundleIdentifier: "com.apple.finder",
                                 appPath: "/Applications/Moved Away.app")
        XCTAssertEqual(vm.appBundleURL(for: stalePath)?.lastPathComponent, "Finder.app")

        let folder = DockItem(type: .folder, title: "IA", subItems: [])
        XCTAssertNil(vm.appBundleURL(for: folder))
    }
}
