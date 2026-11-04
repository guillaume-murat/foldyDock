import Foundation
import Combine

/// The colour of a calendar, as set in Calendar.
public struct CalendarColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// A calendar event or a reminder, reduced to what the CalendarWidget needs. A reminder starts and ends
/// at its due time, and counts as all-day when it has a date but no time.
public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isReminder: Bool
    public let color: CalendarColor?

    public init(title: String, start: Date, end: Date, isAllDay: Bool, isReminder: Bool, color: CalendarColor?) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isReminder = isReminder
        self.color = color
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
    /// Shows the system permission prompt.
    func requestAccess() async
    /// Events overlapping the range, from the calendars visible in Calendar.
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    func reminderAccessStatus() -> CalendarAccessStatus
    /// Shows the system permission prompt for reminders.
    func requestReminderAccess() async
    /// Incomplete reminders due in the range.
    func reminders(from start: Date, to end: Date) async -> [CalendarEvent]
    /// Calls the handler whenever events, reminders or calendars change, from any thread.
    func observeChanges(_ handler: @escaping @Sendable () -> Void)
}

/// What the CalendarWidget shows at one moment.
public struct CalendarWidgetState: Equatable, Sendable {
    /// Start of the current day, so the state only changes when the date does.
    public var today: Date
    /// At most three items: today's all-day event if any, then the soonest.
    public var nextEvents: [CalendarEvent]
    public var accessStatus: CalendarAccessStatus
    public var reminderAccessStatus: CalendarAccessStatus
}

/// Single owner of what the CalendarWidget shows.
@MainActor
public final class CalendarWidgetService: ObservableObject {
    @Published public private(set) var state: CalendarWidgetState
    /// True while the system permission prompt is on screen.
    @Published public private(set) var isRequestingAccess = false

    private let source: CalendarEventSource
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var refreshTimer: Timer?
    private var isObservingChanges = false
    private static let refreshInterval: TimeInterval = 30
    private static let nextEventHorizon: TimeInterval = 24 * 60 * 60
    private static let maxNextEvents = 3

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
            nextEvents: [],
            accessStatus: source.accessStatus(),
            reminderAccessStatus: source.reminderAccessStatus()
        )
    }

    /// Re-reads the date and the Next Event. Called periodically while the widget is shown, which also
    /// covers waking from sleep. EventKit runs off the main thread to avoid UI hitches.
    public func refresh() async {
        let date = now()
        let status = source.accessStatus()
        let reminderStatus = source.reminderAccessStatus()
        let source = self.source
        let horizon = date.addingTimeInterval(Self.nextEventHorizon)
        var candidates: [CalendarEvent] = []
        if status == .granted {
            candidates += await Task.detached(priority: .utility) {
                source.events(from: date, to: horizon)
            }.value
        }
        if reminderStatus == .granted {
            candidates += await source.reminders(from: date, to: horizon)
        }
        let updated = CalendarWidgetState(
            today: calendar.startOfDay(for: date),
            nextEvents: Self.nextEvents(among: candidates, at: date, horizon: horizon),
            accessStatus: status,
            reminderAccessStatus: reminderStatus
        )
        if updated != state { state = updated }
    }

    /// Shows the system prompt the first time only; a refused permission is changed in System Settings.
    public func requestAccessIfNeeded() async {
        isRequestingAccess = true
        if source.accessStatus() == .notDetermined {
            await source.requestAccess()
        }
        if source.reminderAccessStatus() == .notDetermined {
            await source.requestReminderAccess()
        }
        isRequestingAccess = false
        await refresh()
    }

    /// Whether a date falls on the day after the one the widget shows.
    public func isTomorrow(_ date: Date) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: state.today) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    private static func nextEvents(among items: [CalendarEvent], at date: Date, horizon: Date) -> [CalendarEvent] {
        let current = items.filter { $0.end > date }
        let allDayToday = current
            .filter { $0.isAllDay && !$0.isReminder && $0.start <= date }
            .min { $0.title < $1.title }
        let timed = current.filter { !$0.isAllDay }
        let inProgress = timed
            .filter { $0.start <= date }
            .sorted { ($0.end, $0.title) < ($1.end, $1.title) }
        let upcoming = timed
            .filter { $0.start > date && $0.start <= horizon }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return Array(((allDayToday.map { [$0] } ?? []) + inProgress + upcoming).prefix(maxNextEvents))
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
        Task {
            guard refreshTimer != nil else { return }
            await refresh()
        }
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
