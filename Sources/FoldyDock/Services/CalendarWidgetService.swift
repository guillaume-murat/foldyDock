import Foundation
import Combine

/// A calendar event, reduced to what the CalendarWidget needs.
public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

public enum CalendarAccessStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

/// Seam to the user's calendars. `EventKitCalendarEventSource` in production, fixtures in tests.
public protocol CalendarEventSource: Sendable {
    func accessStatus() -> CalendarAccessStatus
    /// Shows the system permission prompt and returns the resulting status.
    func requestAccess() async -> CalendarAccessStatus
    /// Events overlapping the range, from the calendars visible in Calendar.
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    /// Calls the handler whenever events or calendars change, from any thread.
    func observeChanges(_ handler: @escaping @Sendable () -> Void)
}

/// What the CalendarWidget shows at one moment.
public struct CalendarWidgetState: Equatable, Sendable {
    /// Start of the current day, so the state only changes when the date does.
    public var today: Date
    public var nextEvent: CalendarEvent?
    public var accessStatus: CalendarAccessStatus
}

/// Single owner of what the CalendarWidget shows.
@MainActor
public final class CalendarWidgetService: ObservableObject {
    @Published public private(set) var state: CalendarWidgetState

    private let source: CalendarEventSource
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var refreshTimer: Timer?
    private var isObservingChanges = false
    private static let refreshInterval: TimeInterval = 30
    private static let nextEventHorizon: TimeInterval = 24 * 60 * 60

    public init(
        source: CalendarEventSource = EventKitCalendarEventSource(),
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.source = source
        self.now = now
        self.calendar = calendar
        self.state = CalendarWidgetState(
            today: calendar.startOfDay(for: now()),
            nextEvent: nil,
            accessStatus: source.accessStatus()
        )
    }

    /// Re-reads the date and the Next Event. Called periodically while the widget is shown, which also
    /// covers waking from sleep. EventKit runs off the main thread to avoid UI hitches.
    public func refresh() async {
        let date = now()
        let status = source.accessStatus()
        var nextEvent: CalendarEvent?
        if status == .granted {
            let source = self.source
            let horizon = date.addingTimeInterval(Self.nextEventHorizon)
            let events = await Task.detached(priority: .utility) {
                source.events(from: date, to: horizon)
            }.value
            nextEvent = Self.nextEvent(among: events, at: date, horizon: horizon)
        }
        let next = CalendarWidgetState(
            today: calendar.startOfDay(for: date),
            nextEvent: nextEvent,
            accessStatus: status
        )
        if next != state { state = next }
    }

    /// Shows the system prompt the first time only; a refused permission is changed in System Settings.
    public func requestAccessIfNeeded() async {
        if source.accessStatus() == .notDetermined {
            _ = await source.requestAccess()
        }
        await refresh()
    }

    private static func nextEvent(among events: [CalendarEvent], at date: Date, horizon: Date) -> CalendarEvent? {
        let timed = events.filter { !$0.isAllDay && $0.end > date }
        let inProgress = timed.filter { $0.start <= date }
        if let current = inProgress.min(by: { ($0.end, $0.title) < ($1.end, $1.title) }) {
            return current
        }
        return timed
            .filter { $0.start <= horizon }
            .min(by: { ($0.start, $0.title) < ($1.start, $1.title) })
    }

    /// Starts or stops the periodic refresh, which only runs while the widget is shown.
    public func setActive(_ active: Bool) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard active else { return }
        observeSourceChangesOnce()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        Task { await refresh() }
    }

    private func observeSourceChangesOnce() {
        guard !isObservingChanges else { return }
        isObservingChanges = true
        source.observeChanges { [weak self] in
            Task { @MainActor in
                guard let self, self.refreshTimer != nil else { return }
                await self.refresh()
            }
        }
    }
}
