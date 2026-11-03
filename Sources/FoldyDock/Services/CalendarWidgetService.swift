import Foundation
import Combine

/// What the CalendarWidget shows at one moment.
public struct CalendarWidgetState: Equatable, Sendable {
    /// Start of the current day, so the state only changes when the date does.
    public var today: Date
}

/// Single owner of what the CalendarWidget shows.
@MainActor
public final class CalendarWidgetService: ObservableObject {
    @Published public private(set) var state: CalendarWidgetState

    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var refreshTimer: Timer?
    private static let refreshInterval: TimeInterval = 30

    public init(now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        self.now = now
        self.calendar = calendar
        self.state = CalendarWidgetState(today: calendar.startOfDay(for: now()))
    }

    /// Re-reads the date. Called periodically while the widget is shown, which also covers waking from sleep.
    public func refresh() async {
        let next = CalendarWidgetState(today: calendar.startOfDay(for: now()))
        if next != state { state = next }
    }

    /// Starts or stops the periodic refresh, which only runs while the widget is shown.
    public func setActive(_ active: Bool) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard active else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        Task { await refresh() }
    }
}
