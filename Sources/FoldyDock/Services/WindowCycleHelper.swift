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

    /// Determines whether an item title or position represents the standard Window menu.
    public static func isWindowMenu(title: String, index: Int, totalMenuItems: Int) -> Bool {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let localizedNames: Set<String> = [
            "window", "fenêtre", "fenetre", "fenster", "ventana", "finestra",
            "janela", "venster", "уиндоу", "窗口", "視窗", "окно"
        ]
        return localizedNames.contains(normalized) || (totalMenuItems >= 3 && index == totalMenuItems - 2)
    }

    /// Extracts the indices of candidate open-window items from a Window menu.
    /// In macOS, open windows appear at the bottom of the Window menu after the last separator,
    /// or marked with a checkmark.
    public static func candidateWindowIndices(items: [(title: String, isSeparator: Bool, isMarked: Bool)]) -> [Int] {
        var lastSeparatorIndex = -1
        for (i, item) in items.enumerated() {
            if item.isSeparator || item.title.isEmpty {
                lastSeparatorIndex = i
            }
        }

        if lastSeparatorIndex >= 0 && lastSeparatorIndex < items.count - 1 {
            return (lastSeparatorIndex + 1..<items.count).filter {
                !items[$0].isSeparator && !items[$0].title.isEmpty
            }
        } else {
            return items.indices.filter { items[$0].isMarked }
        }
    }
}
