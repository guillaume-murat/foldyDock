import Foundation
import CoreGraphics

/// Pure logic helper for calculating window focus cycling order, stable ordering reconciliation, and activation conditions.
public enum WindowCycleHelper {
    /// Determines the next window index in a round-robin rotation.
    public static func nextWindowIndex(currentIndex: Int?, windowCount: Int) -> Int {
        guard windowCount > 0 else { return 0 }
        guard let current = currentIndex, current >= 0, current < windowCount else {
            return 0
        }
        return (current + 1) % windowCount
    }

    /// Evaluates whether an application activation should trigger window focus cycling.
    /// Cycling only triggers when the application is already the frontmost active app, is not hidden,
    /// and has multiple eligible windows open.
    public static func shouldCycleWindows(isFrontmost: Bool, isHidden: Bool = false, eligibleWindowCount: Int) -> Bool {
        return isFrontmost && !isHidden && eligibleWindowCount > 1
    }

    /// Reconciles a stable window sequence across WindowServer z-order changes.
    /// Preserves existing relative order of known windows, removes closed windows,
    /// and appends newly discovered windows to the end of the sequence.
    public static func reconcileStableOrder(existingOrder: [CGWindowID], currentWindowIDs: [CGWindowID]) -> [CGWindowID] {
        var updated = existingOrder.filter { currentWindowIDs.contains($0) }
        for wid in currentWindowIDs where !updated.contains(wid) {
            updated.append(wid)
        }
        return updated
    }
}
