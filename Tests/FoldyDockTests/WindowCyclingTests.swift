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
}
