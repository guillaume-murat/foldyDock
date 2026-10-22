import Foundation
import CoreGraphics

public struct WindowMenuEntry: Equatable, Sendable {
    public let index: Int
    public let title: String
    public let isSeparator: Bool
    public let isMarked: Bool

    public init(index: Int, title: String, isSeparator: Bool, isMarked: Bool) {
        self.index = index
        self.title = title
        self.isSeparator = isSeparator
        self.isMarked = isMarked
    }
}

public struct AXWindowEntry: Equatable, Sendable {
    public let windowID: CGWindowID
    public let title: String
    public let isMinimized: Bool
    public let isMain: Bool

    public init(windowID: CGWindowID, title: String, isMinimized: Bool, isMain: Bool) {
        self.windowID = windowID
        self.title = title
        self.isMinimized = isMinimized
        self.isMain = isMain
    }
}

public enum WindowCycleDecision: Equatable, Sendable {
    case activateFirstWindow
    case pressMenuIndex(menuIndex: Int, matchingWindowID: CGWindowID?)
    case raiseWindowID(CGWindowID)
    case sendKeyboardShortcut
}

/// Deep state-machine module governing per-PID window order reconciliation, Window Picker snapshot normalization,
/// and sequential round-robin focus cycling across AX windows and macOS Window menus.
public struct AppWindowCyclingEngine: Sendable {
    private var stableWindowOrderPerPid: [pid_t: [CGWindowID]] = [:]
    private var lastCycledMenuRelativeIndexPerPid: [pid_t: Int] = [:]
    private var lastCycledWindowIDPerPid: [pid_t: CGWindowID] = [:]

    public init() {}

    public mutating func removeState(for pid: pid_t) {
        stableWindowOrderPerPid.removeValue(forKey: pid)
        lastCycledMenuRelativeIndexPerPid.removeValue(forKey: pid)
        lastCycledWindowIDPerPid.removeValue(forKey: pid)
    }

    public mutating func recordSelectedWindow(_ window: AppWindowInfo, pid: pid_t, menuEntries: [WindowMenuEntry]) -> Int? {
        if let wid = window.windowID, wid > 0 {
            lastCycledWindowIDPerPid[pid] = wid
        }
        let candidateIndices = WindowCycleHelper.candidateWindowIndices(entries: menuEntries)
        if let menuIndex = window.menuIndex, let relIdx = candidateIndices.firstIndex(of: menuIndex) {
            lastCycledMenuRelativeIndexPerPid[pid] = relIdx
            return menuIndex
        }
        let targetTitle = (window.menuTitle ?? window.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty else { return nil }
        for (relIdx, itemIdx) in candidateIndices.enumerated() {
            let sTitle = menuEntries[itemIdx].title.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.titlesMatch(sTitle, targetTitle) {
                lastCycledMenuRelativeIndexPerPid[pid] = relIdx
                return itemIdx
            }
        }
        return nil
    }

    public static func resolveAXWindowIndex(for window: AppWindowInfo, in axWindows: [AXWindowEntry]) -> Int? {
        let targetTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return axWindows.firstIndex { entry in
            if let wid = window.windowID, wid > 0, entry.windowID == wid {
                return true
            }
            let t = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.titlesMatch(t, targetTitle)
        }
    }

    public static func titlesMatch(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    public static func isEligibleAXWindow(role: String?, subrole: String?, title: String, bundleIdentifier: String) -> Bool {
        guard role == "AXWindow" else { return false }
        if let sub = subrole, !sub.isEmpty {
            guard sub == "AXStandardWindow" || sub == "AXDialog" else { return false }
        }
        if bundleIdentifier == "com.apple.finder" && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    public static func buildWindowInfos(
        pid: pid_t,
        axWindows: [AXWindowEntry],
        menuEntries: [WindowMenuEntry]
    ) -> [AppWindowInfo] {
        var windowInfos: [AppWindowInfo] = []

        for (idx, w) in axWindows.enumerated() {
            let trimmed = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = trimmed.isEmpty ? "Fenêtre \(idx + 1)" : trimmed
            windowInfos.append(AppWindowInfo(
                id: "\(pid)-\(w.windowID)-\(idx)",
                title: displayTitle,
                isMinimized: w.isMinimized,
                isMain: w.isMain,
                windowID: w.windowID,
                menuTitle: trimmed.isEmpty ? nil : trimmed
            ))
        }

        // Pair each Window-menu entry with one not-yet-matched AX window: exact title first, then
        // prefix (Chrome's AX titles add " - Google Chrome" or a tab-group suffix). Unpaired menu
        // entries are windows on other Spaces, which AX does not report.
        let candidateIndices = WindowCycleHelper.candidateWindowIndices(entries: menuEntries)
        let axTitles = windowInfos.map { $0.menuTitle ?? "" }
        var matchedAXIndices = Set<Int>()

        for (cIdx, itemIdx) in candidateIndices.enumerated() {
            let entry = menuEntries[itemIdx]
            let candidateTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidateTitle.isEmpty else { continue }

            let unmatched = axTitles.indices.filter { !matchedAXIndices.contains($0) }
            let matchIdx = unmatched.first { axTitles[$0] == candidateTitle }
                ?? unmatched.first { titlesMatch(axTitles[$0], candidateTitle) }

            guard let i = matchIdx else {
                windowInfos.append(AppWindowInfo(
                    id: "\(pid)-menu-\(itemIdx)-\(cIdx)",
                    title: candidateTitle,
                    isMinimized: false,
                    isMain: entry.isMarked,
                    windowID: nil,
                    menuTitle: candidateTitle,
                    menuIndex: itemIdx
                ))
                continue
            }

            matchedAXIndices.insert(i)
            let existing = windowInfos[i]
            windowInfos[i] = AppWindowInfo(
                id: existing.id,
                title: candidateTitle,
                isMinimized: existing.isMinimized,
                isMain: existing.isMain || entry.isMarked,
                windowID: existing.windowID,
                menuTitle: candidateTitle,
                menuIndex: itemIdx
            )
        }

        return windowInfos
    }

    /// Decides what a click on a running application's dock icon does.
    /// `fallbackWindowCount` is the dock's window count, used when the snapshot is empty (no Accessibility permission).
    public mutating func decideActivation(
        pid: pid_t,
        isFrontmost: Bool,
        isHidden: Bool,
        snapshot: AppWindowSnapshot,
        fallbackWindowCount: Int = 0
    ) -> WindowCycleDecision {
        let menuEntries = snapshot.menuEntries
        let candidateIndices = WindowCycleHelper.candidateWindowIndices(entries: menuEntries)
        let knownWindowCount = max(fallbackWindowCount, snapshot.windows.count, candidateIndices.count)

        guard WindowCycleHelper.shouldCycleWindows(
            isFrontmost: isFrontmost,
            isHidden: isHidden,
            eligibleWindowCount: knownWindowCount
        ) else {
            lastCycledMenuRelativeIndexPerPid.removeValue(forKey: pid)
            lastCycledWindowIDPerPid.removeValue(forKey: pid)
            return .activateFirstWindow
        }

        // Strategy 1: Window menu cycling (handles multi-Space, minimized windows, and Firefox/Chrome/Safari)
        if candidateIndices.count >= 2 {
            // Current window: the checked menu entry, else the menu entry paired with the AX main window
            let markedMenuIndex = candidateIndices.first { menuEntries[$0].isMarked }
                ?? snapshot.windows.first { $0.isMain && $0.windowID != nil }?.menuIndex
            let checkedRelativeIndex = markedMenuIndex.flatMap { candidateIndices.firstIndex(of: $0) }

            let effectiveIndex: Int?
            if let lastIdx = lastCycledMenuRelativeIndexPerPid[pid], lastIdx >= 0, lastIdx < candidateIndices.count {
                effectiveIndex = lastIdx
            } else {
                effectiveIndex = checkedRelativeIndex ?? 0
            }

            let nextRelIdx = WindowCycleHelper.nextWindowIndex(currentIndex: effectiveIndex, windowCount: candidateIndices.count)
            lastCycledMenuRelativeIndexPerPid[pid] = nextRelIdx

            let targetMenuIndex = candidateIndices[nextRelIdx]
            let matchedWindowID = snapshot.windows.first { $0.menuIndex == targetMenuIndex }?.windowID
            return .pressMenuIndex(menuIndex: targetMenuIndex, matchingWindowID: matchedWindowID)
        }

        // Strategy 2: AXWindowEntry stable order cycling
        if let wid = nextAXWindowIDToRaise(pid: pid, axWindows: snapshot.axWindows) {
            return .raiseWindowID(wid)
        }

        // Strategy 3: Keyboard shortcut fallback
        return .sendKeyboardShortcut
    }

    public mutating func nextAXWindowIDToRaise(pid: pid_t, axWindows: [AXWindowEntry]) -> CGWindowID? {
        guard axWindows.count >= 2 else { return nil }
        let currentIDs = axWindows.map(\.windowID)
        let previousOrder = stableWindowOrderPerPid[pid] ?? []
        let stableOrder = WindowCycleHelper.reconcileStableOrder(existingOrder: previousOrder, currentWindowIDs: currentIDs)
        stableWindowOrderPerPid[pid] = stableOrder
        guard stableOrder.count >= 2 else { return nil }

        let currentIndex: Int?
        if let lastWID = lastCycledWindowIDPerPid[pid], let idx = stableOrder.firstIndex(of: lastWID) {
            currentIndex = idx
        } else if let mainWin = axWindows.first(where: { $0.isMain }), let idx = stableOrder.firstIndex(of: mainWin.windowID) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }

        let nextIndex = WindowCycleHelper.nextWindowIndex(currentIndex: currentIndex, windowCount: stableOrder.count)
        let targetWID = stableOrder[nextIndex]
        lastCycledWindowIDPerPid[pid] = targetWID
        return targetWID
    }
}

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

    /// Reconciles a stable sequence of arbitrary identifiers (such as window titles or stable keys)
    /// across z-order changes so round-robin rotation never ping-pongs between the top 2 windows.
    public static func reconcileStableKeys(existingKeys: [String], currentKeys: [String]) -> [String] {
        var updated = existingKeys.filter { currentKeys.contains($0) }
        for key in currentKeys where !updated.contains(key) {
            updated.append(key)
        }
        return updated
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

    public static func candidateWindowIndices(entries: [WindowMenuEntry]) -> [Int] {
        candidateWindowIndices(items: entries.map { (title: $0.title, isSeparator: $0.isSeparator, isMarked: $0.isMarked) })
    }
}
