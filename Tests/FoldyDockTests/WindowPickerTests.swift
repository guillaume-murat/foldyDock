import Testing
import Foundation
@testable import FoldyDock

@Suite("WindowPickerTests")
struct WindowPickerTests {
    @Test("DockConfig preserves window picker settings across encoding and decoding")
    func testDockConfigWindowPickerPersistence() throws {
        let config = DockConfig(
            showWindowPickerOnHover: true,
            windowPickerHoverDelay: 0.45
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DockConfig.self, from: data)

        #expect(decoded.showWindowPickerOnHover == true)
        #expect(decoded.windowPickerHoverDelay == 0.45)
    }

    @Test("AppWindowInfo model initializes and compares correctly")
    func testAppWindowInfoProperties() {
        let win1 = AppWindowInfo(
            id: "pid-101",
            title: "Document 1",
            isMinimized: false,
            isMain: true,
            windowID: 101,
            menuTitle: "Document 1"
        )
        let win2 = AppWindowInfo(
            id: "pid-101",
            title: "Document 1",
            isMinimized: false,
            isMain: true,
            windowID: 101,
            menuTitle: "Document 1"
        )
        let win3 = AppWindowInfo(
            id: "pid-102",
            title: "Document 2 (Minimisée)",
            isMinimized: true,
            isMain: false,
            windowID: 102,
            menuTitle: "Document 2 (Minimisée)"
        )

        #expect(win1 == win2)
        #expect(win1 != win3)
        #expect(win3.isMinimized == true)
        #expect(win1.isMain == true)
    }

    @Test("DockViewModel window picker starts closed and respects dismissal")
    @MainActor
    func testDockViewModelWindowPickerState() {
        let vm = DockViewModel()
        #expect(vm.isWindowPickerOpen == false)
        #expect(vm.activeWindowPickerItem == nil)
        #expect(vm.activeWindowPickerList.isEmpty)

        // Mock an active picker state
        let item = DockItem(type: .app, title: "TestApp", bundleIdentifier: "com.test.app")
        vm.activeWindowPickerItem = item
        vm.activeWindowPickerList = [
            AppWindowInfo(id: "1", title: "Window 1", isMinimized: false, isMain: true),
            AppWindowInfo(id: "2", title: "Window 2", isMinimized: false, isMain: false)
        ]
        #expect(vm.isWindowPickerOpen == true)

        vm.closeWindowPicker()
        #expect(vm.isWindowPickerOpen == false)
        #expect(vm.activeWindowPickerItem == nil)
        #expect(vm.activeWindowPickerList.isEmpty)
    }

    @Test("Launching an item automatically closes any open window picker")
    @MainActor
    func testLaunchClosesWindowPicker() {
        let vm = DockViewModel()
        let item = DockItem(type: .app, title: "TestApp", bundleIdentifier: "com.test.app")
        vm.activeWindowPickerItem = item
        #expect(vm.isWindowPickerOpen == true)

        vm.launch(item: item)
        #expect(vm.isWindowPickerOpen == false)
    }

    @Test("Hovering another app immediately closes any active picker from a previous app")
    @MainActor
    func testHoveringAnotherAppClosesActivePicker() {
        let vm = DockViewModel()
        let item1 = DockItem(type: .app, title: "App 1", bundleIdentifier: "com.app1")
        let item2 = DockItem(type: .app, title: "App 2", bundleIdentifier: "com.app2")

        vm.activeWindowPickerItem = item1
        vm.activeWindowPickerList = [
            AppWindowInfo(id: "1", title: "Doc 1", isMinimized: false, isMain: true),
            AppWindowInfo(id: "2", title: "Doc 2", isMinimized: false, isMain: false)
        ]
        #expect(vm.isWindowPickerOpen == true)

        // Starting hover on item2 closes item1's picker immediately
        vm.handleItemHoverStart(item: item2)
        #expect(vm.isWindowPickerOpen == false)
        #expect(vm.activeWindowPickerItem == nil)
    }

    @Test("Non-running app does not schedule a window picker on hover")
    @MainActor
    func testNonRunningAppDoesNotOpenPicker() {
        let vm = DockViewModel()
        let item = DockItem(type: .app, title: "DeadApp", bundleIdentifier: "com.dead.app")
        vm.handleItemHoverStart(item: item)
        #expect(vm.isWindowPickerOpen == false)
    }

    @Test("DockPopoverCoordinator enforces mutual exclusion between Folder, Window Picker, and Applications Launcher popovers and resolves anchor rects")
    func testDockPopoverCoordinatorMutualExclusionAndAnchors() {
        var coordinator = DockPopoverCoordinator()
        let folder = DockItem(type: .folder, title: "DEV")
        let app = DockItem(type: .app, title: "Firefox", bundleIdentifier: "org.mozilla.firefox")
        let wins = [
            AppWindowInfo(id: "1", title: "Win 1", isMinimized: false, isMain: true),
            AppWindowInfo(id: "2", title: "Win 2", isMinimized: false, isMain: false)
        ]

        // 1. Open Window Picker
        coordinator.openWindowPicker(item: app, windows: wins)
        #expect(coordinator.activePopover == .windowPicker(item: app, windows: wins))
        #expect(coordinator.hasActivePopover == true)

        // 2. Opening Folder closes Window Picker automatically
        let now = Date()
        coordinator.toggleFolder(folder, now: now)
        #expect(coordinator.activePopover == .folder(folder))
        #expect(coordinator.activeWindowPickerItem == nil)

        // 3. Opening Applications Launcher closes Folder automatically
        coordinator.toggleApplicationsLauncher(now: now)
        #expect(coordinator.activePopover == .applicationsLauncher)
        #expect(coordinator.activeFolder == nil)

        // 4. Outside-click dismissal debounce prevents immediate reopen within 0.4s
        coordinator.closeFolder(now: now)
        coordinator.openFolder(folder)
        coordinator.closeFolder(now: now)
        coordinator.toggleFolder(folder, now: now.addingTimeInterval(0.15))
        #expect(coordinator.activeFolder == nil)

        // After 0.45s, toggling opens the folder again
        coordinator.toggleFolder(folder, now: now.addingTimeInterval(0.45))
        #expect(coordinator.activeFolder == folder)

        // 5. Anchor rect calculation uses exact FolderIconGrid frame when available
        let itemFrames: [UUID: CGRect] = [
            folder.id: CGRect(x: 200, y: 0, width: 160, height: 76)
        ]
        let anchorRect = DockPopoverCoordinator.anchorRect(
            for: folder.id,
            itemFrames: itemFrames,
            dockHeight: 76,
            fallbackMidX: 300
        )
        #expect(anchorRect == CGRect(x: 200, y: 74, width: 160, height: 1))
    }

    @Test("fetchOpenWindowsAsync returns empty array for non-existent bundle")
    func testFetchOpenWindowsAsyncNonExistent() async {
        let observer = await AppObserverService()
        let windows = await observer.fetchOpenWindowsAsync(for: "com.nonexistent.fakeapp")
        #expect(windows.isEmpty)
    }
}
