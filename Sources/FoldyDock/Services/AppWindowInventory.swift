import Foundation
import CoreGraphics

/// One row of CGWindowList, reduced to what the inventory needs.
public struct CGWindowRow: Equatable, Sendable {
    public let ownerPID: pid_t
    public let layer: Int
    public let width: Double
    public let height: Double
    public let alpha: Double
    public let title: String

    public init(ownerPID: pid_t, layer: Int = 0, width: Double, height: Double, alpha: Double = 1, title: String = "") {
        self.ownerPID = ownerPID
        self.layer = layer
        self.width = width
        self.height = height
        self.alpha = alpha
        self.title = title
    }
}

/// One Accessibility window of an application, before User Window eligibility is applied.
public struct AXWindowReading: Equatable, Sendable {
    public let windowID: CGWindowID
    public let role: String?
    public let subrole: String?
    public let title: String
    public let isMinimized: Bool
    public let isMain: Bool

    public init(windowID: CGWindowID, role: String?, subrole: String?, title: String, isMinimized: Bool, isMain: Bool) {
        self.windowID = windowID
        self.role = role
        self.subrole = subrole
        self.title = title
        self.isMinimized = isMinimized
        self.isMain = isMain
    }
}

public struct RunningAppRef: Hashable, Sendable {
    public let pid: pid_t
    public let bundleIdentifier: String

    public init(pid: pid_t, bundleIdentifier: String) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Seam to the window server and Accessibility. `SystemAppWindowSource` in production, fixtures in tests.
public protocol AppWindowSource: Sendable {
    /// Every on- and off-screen window of every application (all Spaces).
    func cgWindowRows() -> [CGWindowRow]
    /// Accessibility windows of one application (current Space only).
    func axWindows(pid: pid_t) -> [AXWindowReading]
    /// Entries of the application's Window menu (lists windows on every Space).
    func windowMenuEntries(pid: pid_t) -> [WindowMenuEntry]
}

/// The App Window Inventory of one application at one moment.
public struct AppWindowSnapshot: Equatable, Sendable {
    /// Paired User Windows, in display order.
    public let windows: [AppWindowInfo]
    /// Eligible AX windows (current Space), as read.
    public let axWindows: [AXWindowEntry]
    /// Raw Window menu entries, as read.
    public let menuEntries: [WindowMenuEntry]
}

/// What the dock shows for every running application.
public struct AppWindowSummary: Equatable, Sendable {
    /// Number of User Windows per bundle identifier (dock window dots).
    public let windowCounts: [String: Int]
    /// Applications whose User Windows on the current Space are all minimized (yellow button).
    public let allMinimizedBundleIds: Set<String>
}

/// Single owner of "which User Windows does this application have".
public actor AppWindowInventory {
    private nonisolated let source: AppWindowSource
    private let now: @Sendable () -> Date
    private static let countMaxAge: TimeInterval = 10

    private struct CachedCount {
        let raw: Int
        let count: Int
        let readAt: Date
    }
    private var cachedCounts: [pid_t: CachedCount] = [:]

    public init(source: AppWindowSource, now: @escaping @Sendable () -> Date = Date.init) {
        self.source = source
        self.now = now
    }

    /// Counts for every running application. Raw CGWindowList rows include helper windows (e.g. Chrome's
    /// full-screen toolbar), so the inventory count wins; the raw count is the fallback when the inventory
    /// finds nothing (no Accessibility permission, or no Window menu while the windows are on another Space).
    public func refresh(apps: [RunningAppRef]) -> AppWindowSummary {
        let rawCounts = Self.rawWindowCounts(rows: source.cgWindowRows())
        let date = now()
        var counts: [String: Int] = [:]
        var nextCache: [pid_t: CachedCount] = [:]
        var allMinimized: Set<String> = []
        for app in apps {
            // Minimizing does not change the raw rows, so this is read on every refresh.
            let userWindows = source.axWindows(pid: app.pid).filter { Self.isUserWindow($0, bundleIdentifier: app.bundleIdentifier) }
            if !userWindows.isEmpty && userWindows.allSatisfy(\.isMinimized) {
                allMinimized.insert(app.bundleIdentifier)
            }

            guard let raw = rawCounts[app.pid], raw > 0 else { continue }
            var entry = cachedCounts[app.pid]
            if entry == nil || entry!.raw != raw || date.timeIntervalSince(entry!.readAt) > Self.countMaxAge {
                let inventoryCount = snapshot(for: app).windows.count
                entry = CachedCount(raw: raw, count: inventoryCount > 0 ? inventoryCount : raw, readAt: date)
            }
            nextCache[app.pid] = entry
            counts[app.bundleIdentifier] = entry!.count
        }
        cachedCounts = nextCache
        return AppWindowSummary(windowCounts: counts, allMinimizedBundleIds: allMinimized)
    }

    static func rawWindowCounts(rows: [CGWindowRow]) -> [pid_t: Int] {
        rows.reduce(into: [:]) { counts, row in
            guard row.layer == 0, row.alpha > 0.05, row.width >= 150, row.height >= 150 else { return }
            // macOS 500x500 untitled offscreen helper windows
            if row.width == 500 && row.height == 500 && row.title.isEmpty { return }
            counts[row.ownerPID, default: 0] += 1
        }
    }

    /// Fresh reading for the Window Picker Popover, window cycling and window selection.
    public nonisolated func snapshot(for app: RunningAppRef) -> AppWindowSnapshot {
        let axWindows = source.axWindows(pid: app.pid)
            .filter { Self.isUserWindow($0, bundleIdentifier: app.bundleIdentifier) }
            .map { AXWindowEntry(windowID: $0.windowID, title: $0.title, isMinimized: $0.isMinimized, isMain: $0.isMain) }
        let menuEntries = source.windowMenuEntries(pid: app.pid)
        let windows = AppWindowCyclingEngine.buildWindowInfos(pid: app.pid, axWindows: axWindows, menuEntries: menuEntries)
        return AppWindowSnapshot(windows: windows, axWindows: axWindows, menuEntries: menuEntries)
    }

    static func isUserWindow(_ window: AXWindowReading, bundleIdentifier: String) -> Bool {
        AppWindowCyclingEngine.isEligibleAXWindow(
            role: window.role,
            subrole: window.subrole,
            title: window.title.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier
        )
    }
}
