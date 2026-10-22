import Testing
import Foundation
import CoreGraphics
@testable import FoldyDock

@Suite("WindowCyclingTests")
struct WindowCyclingTests {
    @Test("WindowCycleHelper returns correct next index in round-robin sequence")
    func testNextWindowIndexRoundRobin() {
        // 3 windows: 0 -> 1 -> 2 -> 0
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: 0, windowCount: 3) == 1)
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: 1, windowCount: 3) == 2)
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: 2, windowCount: 3) == 0)
    }

    @Test("WindowCycleHelper handles edge cases: nil index, single window, and empty list")
    func testNextWindowIndexEdgeCases() {
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: nil, windowCount: 3) == 0)
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: 0, windowCount: 1) == 0)
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: 0, windowCount: 0) == 0)
        #expect(WindowCycleHelper.nextWindowIndex(currentIndex: 5, windowCount: 2) == 0)
    }

    @Test("WindowCycleHelper evaluates cycling conditions correctly")
    func testShouldCycleConditions() {
        // App is not frontmost -> should NOT cycle (1st click brings app to foreground)
        #expect(WindowCycleHelper.shouldCycleWindows(isFrontmost: false, isHidden: false, eligibleWindowCount: 3) == false)

        // App is hidden -> should NOT cycle
        #expect(WindowCycleHelper.shouldCycleWindows(isFrontmost: true, isHidden: true, eligibleWindowCount: 3) == false)

        // App has only 1 window -> should NOT cycle
        #expect(WindowCycleHelper.shouldCycleWindows(isFrontmost: true, isHidden: false, eligibleWindowCount: 1) == false)
        #expect(WindowCycleHelper.shouldCycleWindows(isFrontmost: true, isHidden: false, eligibleWindowCount: 0) == false)

        // App is frontmost, visible, with multiple windows -> should cycle
        #expect(WindowCycleHelper.shouldCycleWindows(isFrontmost: true, isHidden: false, eligibleWindowCount: 2) == true)
        #expect(WindowCycleHelper.shouldCycleWindows(isFrontmost: true, isHidden: false, eligibleWindowCount: 5) == true)
    }

    @Test("WindowCycleHelper reconciles stable order across z-order changes and window churn")
    func testReconcileStableOrder() {
        // Initial discovery
        let initial = WindowCycleHelper.reconcileStableOrder(existingOrder: [], currentWindowIDs: [101, 102, 103])
        #expect(initial == [101, 102, 103])

        // When WindowServer shifts z-order (e.g. 102 is now in front), order is preserved!
        let afterRaise = WindowCycleHelper.reconcileStableOrder(existingOrder: initial, currentWindowIDs: [102, 101, 103])
        #expect(afterRaise == [101, 102, 103])

        // When window 102 is closed, it is cleanly removed
        let afterClose = WindowCycleHelper.reconcileStableOrder(existingOrder: afterRaise, currentWindowIDs: [101, 103])
        #expect(afterClose == [101, 103])

        // When window 104 is newly opened, it is appended
        let afterNew = WindowCycleHelper.reconcileStableOrder(existingOrder: afterClose, currentWindowIDs: [101, 103, 104])
        #expect(afterNew == [101, 103, 104])
    }

    @Test("WindowCycleHelper simulates 6 full cycles without ping-ponging")
    func testFullCyclingSimulation() {
        var stableOrder = [CGWindowID]()
        let allWindows: [CGWindowID] = [201, 202, 203]

        var focusedID: CGWindowID = 201
        var visitedTargets: [CGWindowID] = []

        for _ in 1...6 {
            stableOrder = WindowCycleHelper.reconcileStableOrder(existingOrder: stableOrder, currentWindowIDs: allWindows)
            let currentIndex = stableOrder.firstIndex(of: focusedID)
            let nextIndex = WindowCycleHelper.nextWindowIndex(currentIndex: currentIndex, windowCount: stableOrder.count)
            let targetID = stableOrder[nextIndex]

            visitedTargets.append(targetID)
            // Simulated focus shift
            focusedID = targetID
        }

        // Must cycle sequentially: 202 -> 203 -> 201 -> 202 -> 203 -> 201
        #expect(visitedTargets == [202, 203, 201, 202, 203, 201])
    }

    @Test("WindowCycleHelper recognizes Window menu titles across multiple languages and positions")
    func testIsWindowMenu() {
        #expect(WindowCycleHelper.isWindowMenu(title: "Window", index: 3, totalMenuItems: 8) == true)
        #expect(WindowCycleHelper.isWindowMenu(title: "Fenêtre", index: 3, totalMenuItems: 8) == true)
        #expect(WindowCycleHelper.isWindowMenu(title: "fenêtre", index: 3, totalMenuItems: 8) == true)
        #expect(WindowCycleHelper.isWindowMenu(title: "Fenster", index: 3, totalMenuItems: 8) == true)
        #expect(WindowCycleHelper.isWindowMenu(title: "Ventana", index: 3, totalMenuItems: 8) == true)
        
        // Second to last item fallback
        #expect(WindowCycleHelper.isWindowMenu(title: "CustomMenu", index: 8, totalMenuItems: 10) == true)
        #expect(WindowCycleHelper.isWindowMenu(title: "File", index: 1, totalMenuItems: 10) == false)
    }

    @Test("WindowCycleHelper extracts candidate window indices from menu items")
    func testCandidateWindowIndices() {
        // Typical macOS menu: commands, separator, windows (one checked)
        let menuItems: [(title: String, isSeparator: Bool, isMarked: Bool)] = [
            (title: "Minimize", isSeparator: false, isMarked: false),
            (title: "Zoom", isSeparator: false, isMarked: false),
            (title: "", isSeparator: true, isMarked: false),
            (title: "Window 1 - Doc A", isSeparator: false, isMarked: true),
            (title: "Window 2 - Doc B", isSeparator: false, isMarked: false),
            (title: "Window 3 - Doc C", isSeparator: false, isMarked: false)
        ]

        let indices = WindowCycleHelper.candidateWindowIndices(items: menuItems)
        #expect(indices == [3, 4, 5])

        // Whenchecked is index 3 (relative 0), next index is relative 1 -> target is 4 (Window 2)
        let checkedRelativeIndex = indices.firstIndex(of: 3)
        let nextRelativeIndex = WindowCycleHelper.nextWindowIndex(currentIndex: checkedRelativeIndex, windowCount: indices.count)
        #expect(indices[nextRelativeIndex] == 4)
    }

    @Test("WindowCycleHelper reconciles stable string keys across z-order shifts without ping-ponging")
    func testReconcileStableKeys() {
        var stableKeys: [String] = []
        let zOrderedSnapshots = [
            ["wid-10", "wid-20", "wid-30"],
            ["wid-20", "wid-10", "wid-30"],
            ["wid-30", "wid-20", "wid-10"]
        ]

        var lastKey: String? = "wid-10"
        var visited: [String] = []

        for snapshot in zOrderedSnapshots {
            stableKeys = WindowCycleHelper.reconcileStableKeys(existingKeys: stableKeys, currentKeys: snapshot)
            let currentIdx = lastKey.flatMap { stableKeys.firstIndex(of: $0) }
            let nextIdx = WindowCycleHelper.nextWindowIndex(currentIndex: currentIdx, windowCount: stableKeys.count)
            let nextKey = stableKeys[nextIdx]
            visited.append(nextKey)
            lastKey = nextKey
        }

        #expect(stableKeys == ["wid-10", "wid-20", "wid-30"])
        #expect(visited == ["wid-20", "wid-30", "wid-10"])
    }

    @Test("AppWindowCyclingEngine activates background app on first click, then cycles sequentially on subsequent clicks including identical Firefox titles")
    func testAppWindowCyclingEngineEndToEnd() {
        var engine = AppWindowCyclingEngine()
        let pid: pid_t = 4242

        // Snapshot with 3 Firefox windows where two have identical "Mozilla Firefox" titles
        let menuItems: [WindowMenuEntry] = [
            WindowMenuEntry(index: 0, title: "Minimize", isSeparator: false, isMarked: false),
            WindowMenuEntry(index: 1, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 2, title: "Mozilla Firefox", isSeparator: false, isMarked: true),
            WindowMenuEntry(index: 3, title: "Mozilla Firefox", isSeparator: false, isMarked: false),
            WindowMenuEntry(index: 4, title: "GitHub - foldyDock", isSeparator: false, isMarked: false)
        ]

        let axWindows: [AXWindowEntry] = [
            AXWindowEntry(windowID: 101, title: "Mozilla Firefox", isMinimized: false, isMain: true),
            AXWindowEntry(windowID: 102, title: "Mozilla Firefox", isMinimized: false, isMain: false),
            AXWindowEntry(windowID: 103, title: "GitHub - foldyDock", isMinimized: true, isMain: false)
        ]
        let snapshot = AppWindowSnapshot(
            windows: AppWindowCyclingEngine.buildWindowInfos(pid: pid, axWindows: axWindows, menuEntries: menuItems),
            axWindows: axWindows,
            menuEntries: menuItems
        )

        // 1st click when app is NOT frontmost -> activates app without cycling
        let firstDecision = engine.decideActivation(
            pid: pid,
            isFrontmost: false,
            isHidden: false,
            snapshot: snapshot
        )
        #expect(firstDecision == .activateFirstWindow)

        // 2nd click when app IS frontmost -> cycles to relative window 1 (menu index 3)
        let secondDecision = engine.decideActivation(
            pid: pid,
            isFrontmost: true,
            isHidden: false,
            snapshot: snapshot
        )
        #expect(secondDecision == .pressMenuIndex(menuIndex: 3, matchingWindowID: 102))

        // 3rd click (even if Firefox hasn't updated its checkmark asynchronously yet!) -> cycles to relative window 2 (menu index 4, windowID 103)
        let thirdDecision = engine.decideActivation(
            pid: pid,
            isFrontmost: true,
            isHidden: false,
            snapshot: snapshot
        )
        #expect(thirdDecision == .pressMenuIndex(menuIndex: 4, matchingWindowID: 103))

        // 4th click -> wraps around to relative window 0 (menu index 2, windowID 101)
        let fourthDecision = engine.decideActivation(
            pid: pid,
            isFrontmost: true,
            isHidden: false,
            snapshot: snapshot
        )
        #expect(fourthDecision == .pressMenuIndex(menuIndex: 2, matchingWindowID: 101))
    }

    @Test("AppWindowCyclingEngine normalizes AX and Window menu snapshots into AppWindowInfo list without losing duplicate-titled AX windows")
    func testBuildOpenWindowInfos() {
        let axWindows: [AXWindowEntry] = [
            AXWindowEntry(windowID: 101, title: "Nouvel onglet — Mozilla Firefox", isMinimized: false, isMain: true),
            AXWindowEntry(windowID: 102, title: "Nouvel onglet — Mozilla Firefox", isMinimized: false, isMain: false)
        ]
        let menuItems: [WindowMenuEntry] = [
            WindowMenuEntry(index: 0, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 1, title: "Nouvel onglet — Mozilla Firefox", isSeparator: false, isMarked: true),
            WindowMenuEntry(index: 2, title: "Nouvel onglet — Mozilla Firefox", isSeparator: false, isMarked: false),
            WindowMenuEntry(index: 3, title: "Other Space Window", isSeparator: false, isMarked: false)
        ]

        let infos = AppWindowCyclingEngine.buildWindowInfos(pid: 99, axWindows: axWindows, menuEntries: menuItems)
        #expect(infos.count == 3)
        #expect(infos[0].windowID == 101)
        #expect(infos[0].isMain == true)
        #expect(infos[1].windowID == 102)
        #expect(infos[1].isMain == false)
        #expect(infos[2].windowID == nil)
        #expect(infos[2].title == "Other Space Window")
    }

    @Test("Window menu titles match AX titles that carry an app or tab-group suffix (Chrome) without duplicating the window")
    func testBuildOpenWindowInfosMatchesSuffixedAXTitles() {
        let axWindows: [AXWindowEntry] = [
            AXWindowEntry(windowID: 201, title: "Nouvel onglet - Google Chrome", isMinimized: false, isMain: true)
        ]
        let menuItems: [WindowMenuEntry] = [
            WindowMenuEntry(index: 0, title: "Tout ramener au premier plan", isSeparator: false, isMarked: false),
            WindowMenuEntry(index: 1, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 2, title: "Claude in Chrome", isSeparator: false, isMarked: false),
            WindowMenuEntry(index: 3, title: "Nouvel onglet", isSeparator: false, isMarked: true)
        ]

        let infos = AppWindowCyclingEngine.buildWindowInfos(pid: 42, axWindows: axWindows, menuEntries: menuItems)
        #expect(infos.count == 2)
        #expect(infos[0].windowID == 201)
        #expect(infos[0].title == "Nouvel onglet")
        #expect(infos[0].menuTitle == "Nouvel onglet")
        #expect(infos[0].isMain == true)
        #expect(infos[1].windowID == nil)
        #expect(infos[1].title == "Claude in Chrome")
    }
}

