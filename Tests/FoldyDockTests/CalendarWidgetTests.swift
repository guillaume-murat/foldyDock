import Testing
import Foundation
@testable import FoldyDock

/// Fixture adapter: a permission status and a list of events, with no EventKit involved.
final class FixtureCalendarSource: CalendarEventSource, @unchecked Sendable {
    var status: CalendarAccessStatus = .granted
    var statusAfterRequest: CalendarAccessStatus = .granted
    var events: [CalendarEvent] = []
    var reminderStatus: CalendarAccessStatus = .granted
    var reminderStatusAfterRequest: CalendarAccessStatus = .granted
    var reminders: [CalendarEvent] = []
    private(set) var reminderRequestCount = 0
    private(set) var requestCount = 0
    var onRequest: (@Sendable () async -> Void)?
    private var changeHandlers: [@Sendable () -> Void] = []

    func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        changeHandlers.append(handler)
    }

    func notifyChange() {
        changeHandlers.forEach { $0() }
    }

    func accessStatus() -> CalendarAccessStatus { status }

    func requestAccess() async {
        requestCount += 1
        await onRequest?()
        status = statusAfterRequest
    }

    func reminderAccessStatus() -> CalendarAccessStatus { reminderStatus }

    func requestReminderAccess() async {
        reminderRequestCount += 1
        reminderStatus = reminderStatusAfterRequest
    }

    func reminders(from start: Date, to end: Date) async -> [CalendarEvent] {
        reminders.filter { $0.start >= start && $0.start <= end }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        events.filter { $0.start < end && $0.end > start }
    }
}

final class TestFlag: @unchecked Sendable {
    var value: Bool?
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, color: CalendarColor? = nil) -> CalendarEvent {
    CalendarEvent(title: title, start: start, end: end, isAllDay: allDay, isReminder: false, color: color)
}

private func reminder(_ title: String, due: Date, dateOnly: Bool = false) -> CalendarEvent {
    CalendarEvent(title: title, start: due, end: due, isAllDay: dateOnly, isReminder: true, color: nil)
}

@MainActor
private func makeService(_ source: FixtureCalendarSource, clock: TestClock) -> CalendarWidgetService {
    CalendarWidgetService(source: source, now: { clock.now }, calendar: utcCalendar)
}

@MainActor
private func makeViewModel(service: CalendarWidgetService, config: DockConfig = DockConfig()) -> (DockViewModel, DockPersistenceService) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let persistence = DockPersistenceService(customDirectoryURL: directory)
    persistence.saveConfig(config)
    let viewModel = DockViewModel(persistenceService: persistence, appObserver: .shared, calendarWidgetService: service)
    return (viewModel, persistence)
}

@Suite("CalendarWidgetTests")
@MainActor
struct CalendarWidgetTests {
    // MARK: - Date

    @Test("The widget shows the current day and changes at midnight")
    func testDateChangesAtMidnight() async {
        let clock = TestClock()
        clock.now = at(3, 23, 59)
        let service = makeService(FixtureCalendarSource(), clock: clock)
        await service.refresh()
        #expect(service.state.today == at(3, 0))

        clock.now = at(4, 0, 1)
        await service.refresh()
        #expect(service.state.today == at(4, 0))
    }

    // MARK: - Preference

    @Test("The CalendarWidget preference is off by default and absent from older configurations")
    func testPreferenceDefaultsToOff() throws {
        #expect(DockConfig().showCalendarWidget == false)
        #expect(DockConfig.defaultConfig.showCalendarWidget == false)

        let older = try JSONDecoder().decode(DockConfig.self, from: Data("{}".utf8))
        #expect(older.showCalendarWidget == false)
    }

    @Test("Switching the CalendarWidget on survives a restart")
    func testPreferencePersists() async {
        let (viewModel, persistence) = makeViewModel(service: makeService(FixtureCalendarSource(), clock: TestClock()))
        await viewModel.setCalendarWidgetEnabled(true)

        #expect(viewModel.config.showCalendarWidget == true)
        #expect(persistence.loadConfig().showCalendarWidget == true)
    }

    // MARK: - Next Event

    private func nextEvent(among events: [CalendarEvent], at date: Date) async -> CalendarEvent? {
        let source = FixtureCalendarSource()
        source.events = events
        let clock = TestClock()
        clock.now = date
        let service = makeService(source, clock: clock)
        await service.refresh()
        return service.state.nextEvents.first
    }

    @Test("The soonest upcoming event is the Next Event")
    func testSoonestUpcomingEvent() async {
        let standup = event("Standup", at(3, 10), at(3, 11))
        let lunch = event("Lunch", at(3, 12), at(3, 13))
        #expect(await nextEvent(among: [lunch, standup], at: at(3, 9)) == standup)
    }

    @Test("An event in progress wins over an upcoming one")
    func testEventInProgressWins() async {
        let workshop = event("Workshop", at(3, 9), at(3, 11))
        let lunch = event("Lunch", at(3, 12), at(3, 13))
        #expect(await nextEvent(among: [lunch, workshop], at: at(3, 10)) == workshop)
    }

    @Test("Among overlapping events in progress, the one ending first wins")
    func testOverlappingEventsInProgress() async {
        let focus = event("Focus block", at(3, 8), at(3, 17))
        let review = event("Review", at(3, 10), at(3, 11))
        #expect(await nextEvent(among: [focus, review], at: at(3, 10, 30)) == review)
    }

    @Test("A finished event is never the Next Event")
    func testFinishedEventIgnored() async {
        #expect(await nextEvent(among: [event("Standup", at(3, 8), at(3, 9))], at: at(3, 9)) == nil)
    }

    @Test("Only events starting within the next 24 hours qualify")
    func testTwentyFourHourLimit() async {
        let inside = event("Inside", at(4, 8, 59), at(4, 10))
        let outside = event("Outside", at(4, 9, 1), at(4, 10))
        #expect(await nextEvent(among: [inside], at: at(3, 9)) == inside)
        #expect(await nextEvent(among: [outside], at: at(3, 9)) == nil)
    }

    // MARK: - Permission

    @Test("Without calendar access the widget shows the date alone")
    func testRefusedAccessShowsDateAlone() async {
        let source = FixtureCalendarSource()
        source.status = .denied
        source.events = [event("Standup", at(3, 10), at(3, 11))]
        let clock = TestClock()
        clock.now = at(3, 9)
        let service = makeService(source, clock: clock)

        await service.refresh()

        #expect(service.state.today == at(3, 0))
        #expect(service.state.nextEvents.first == nil)
        #expect(service.state.accessStatus == .denied)
    }

    @Test("Switching the widget on requests access, then shows the Next Event")
    func testSwitchingOnRequestsAccess() async {
        let source = FixtureCalendarSource()
        source.status = .notDetermined
        let standup = event("Standup", at(3, 10), at(3, 11))
        source.events = [standup]
        let clock = TestClock()
        clock.now = at(3, 9)
        let (viewModel, _) = makeViewModel(service: makeService(source, clock: clock))

        await viewModel.setCalendarWidgetEnabled(true)

        #expect(source.requestCount == 1)
        #expect(viewModel.calendarWidgetService.state.nextEvents.first == standup)
    }

    @Test("Launching with the widget on, or switching it off, never requests access")
    func testNoRequestAtLaunchOrWhenOff() async {
        let source = FixtureCalendarSource()
        source.status = .notDetermined
        let (viewModel, _) = makeViewModel(
            service: makeService(source, clock: TestClock()),
            config: DockConfig(showCalendarWidget: true)
        )
        await viewModel.calendarWidgetService.refresh()
        await viewModel.setCalendarWidgetEnabled(false)

        #expect(source.requestCount == 0)
    }

    @Test("A refused or granted permission is not requested again")
    func testNoRepeatRequest() async {
        let source = FixtureCalendarSource()
        source.status = .denied
        let (viewModel, _) = makeViewModel(service: makeService(source, clock: TestClock()))

        await viewModel.setCalendarWidgetEnabled(true)

        #expect(source.requestCount == 0)
    }

    // MARK: - Live updates

    @Test("When the Next Event ends, the widget moves to the following event, then to the date alone")
    func testMovesOnWhenEventEnds() async {
        let source = FixtureCalendarSource()
        let standup = event("Standup", at(3, 10), at(3, 11))
        let lunch = event("Lunch", at(3, 12), at(3, 13))
        source.events = [standup, lunch]
        let clock = TestClock()
        clock.now = at(3, 10, 30)
        let service = makeService(source, clock: clock)
        await service.refresh()
        #expect(service.state.nextEvents.first == standup)

        clock.now = at(3, 11)
        await service.refresh()
        #expect(service.state.nextEvents.first == lunch)

        clock.now = at(3, 13)
        await service.refresh()
        #expect(service.state.nextEvents.first == nil)
    }

    @Test("An event appears once it enters the 24-hour limit")
    func testEventEntersLimit() async {
        let source = FixtureCalendarSource()
        let trip = event("Trip", at(4, 12), at(4, 13))
        source.events = [trip]
        let clock = TestClock()
        clock.now = at(3, 11)
        let service = makeService(source, clock: clock)
        await service.refresh()
        #expect(service.state.nextEvents.first == nil)

        clock.now = at(3, 12, 1)
        await service.refresh()
        #expect(service.state.nextEvents.first == trip)
    }

    @Test("A change in the calendars updates the widget while it is shown")
    func testCalendarChangeRefreshes() async {
        let source = FixtureCalendarSource()
        let clock = TestClock()
        clock.now = at(3, 9)
        let service = makeService(source, clock: clock)
        service.setActive(true)
        defer { service.setActive(false) }
        await service.refresh()
        #expect(service.state.nextEvents.first == nil)

        let standup = event("Standup", at(3, 10), at(3, 11))
        source.events = [standup]
        source.notifyChange()
        for _ in 0..<100 where service.state.nextEvents.first == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(service.state.nextEvents.first == standup)
    }

    @Test("A calendar change is ignored while the widget is hidden")
    func testCalendarChangeIgnoredWhenHidden() async {
        let source = FixtureCalendarSource()
        let clock = TestClock()
        clock.now = at(3, 9)
        let service = makeService(source, clock: clock)
        service.setActive(true)
        service.setActive(false)
        await service.refresh()

        source.events = [event("Standup", at(3, 10), at(3, 11))]
        source.notifyChange()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(service.state.nextEvents.first == nil)
    }

    @Test("Access granted after a refusal shows events without a restart")
    func testAccessGrantedLater() async {
        let source = FixtureCalendarSource()
        source.status = .denied
        let standup = event("Standup", at(3, 10), at(3, 11))
        source.events = [standup]
        let clock = TestClock()
        clock.now = at(3, 9)
        let service = makeService(source, clock: clock)
        await service.refresh()
        #expect(service.state.nextEvents.first == nil)

        source.status = .granted
        await service.refresh()
        #expect(service.state.nextEvents.first == standup)
        #expect(service.state.accessStatus == .granted)
    }

    // MARK: - Access help in the preferences

    @Test("The preferences explain a missing permission only while the widget is on")
    func testAccessHelpVisibility() async {
        let source = FixtureCalendarSource()
        source.status = .denied
        let (viewModel, _) = makeViewModel(service: makeService(source, clock: TestClock()))
        #expect(viewModel.showsCalendarAccessHelp == false)

        await viewModel.setCalendarWidgetEnabled(true)
        #expect(viewModel.showsCalendarAccessHelp == true)

        source.status = .granted
        await viewModel.calendarWidgetService.refresh()
        #expect(viewModel.showsCalendarAccessHelp == false)

        source.status = .denied
        await viewModel.calendarWidgetService.refresh()
        await viewModel.setCalendarWidgetEnabled(false)
        #expect(viewModel.showsCalendarAccessHelp == false)
    }

    @Test("The preferences explain a permission never requested while the widget is on")
    func testAccessHelpWhenNotDetermined() async {
        let source = FixtureCalendarSource()
        source.status = .notDetermined
        let (viewModel, _) = makeViewModel(
            service: makeService(source, clock: TestClock()),
            config: DockConfig(showCalendarWidget: true)
        )

        #expect(viewModel.showsCalendarAccessHelp == true)
    }

    @Test("The preferences stay quiet behind the system prompt")
    func testNoAccessHelpBehindPrompt() async {
        let source = FixtureCalendarSource()
        source.status = .notDetermined
        let (viewModel, _) = makeViewModel(service: makeService(source, clock: TestClock()))
        let observed = TestFlag()
        source.onRequest = { @MainActor in
            observed.value = viewModel.showsCalendarAccessHelp
        }

        await viewModel.setCalendarWidgetEnabled(true)

        #expect(source.requestCount == 1)
        #expect(observed.value == false)
    }

    // MARK: - Up Next presentation

    @Test("The Next Event keeps the colour of its calendar")
    func testNextEventKeepsCalendarColor() async {
        let orange = CalendarColor(red: 1, green: 0.6, blue: 0)
        let trip = event("Trip", at(3, 10), at(3, 11), color: orange)
        #expect(await nextEvent(among: [trip], at: at(3, 9))?.color == orange)
    }

    @Test("Only an event starting on the following day counts as tomorrow")
    func testIsTomorrow() async {
        let clock = TestClock()
        clock.now = at(3, 23)
        let service = makeService(FixtureCalendarSource(), clock: clock)
        await service.refresh()

        #expect(service.isTomorrow(at(4, 0)) == true)
        #expect(service.isTomorrow(at(3, 22)) == false)
        #expect(service.isTomorrow(at(2, 22)) == false)
        #expect(service.isTomorrow(at(5, 0)) == false)
    }

    // MARK: - Reminders

    private func nextEvent(events: [CalendarEvent] = [], reminders: [CalendarEvent], at date: Date,
                           configure: (FixtureCalendarSource) -> Void = { _ in }) async -> CalendarEvent? {
        let source = FixtureCalendarSource()
        source.events = events
        source.reminders = reminders
        configure(source)
        let clock = TestClock()
        clock.now = date
        let service = makeService(source, clock: clock)
        await service.refresh()
        return service.state.nextEvents.first
    }

    @Test("A reminder due soonest is the Next Event")
    func testReminderBeforeEvent() async {
        let mat = reminder("Prendre mon tapis", due: at(3, 16))
        let train = event("Train", at(3, 17), at(3, 19))
        #expect(await nextEvent(events: [train], reminders: [mat], at: at(3, 15)) == mat)
    }

    @Test("An event starting first comes before a reminder")
    func testEventBeforeReminder() async {
        let mat = reminder("Prendre mon tapis", due: at(3, 18))
        let train = event("Train", at(3, 17), at(3, 19))
        #expect(await nextEvent(events: [train], reminders: [mat], at: at(3, 15)) == train)
    }

    @Test("A reminder whose time has passed, or without a time, is not the Next Event")
    func testOverdueAndDateOnlyRemindersIgnored() async {
        let overdue = reminder("Overdue", due: at(3, 14))
        let dateOnly = reminder("Date only", due: at(3, 16), dateOnly: true)
        #expect(await nextEvent(reminders: [overdue, dateOnly], at: at(3, 15)) == nil)
    }

    @Test("Reminders show with calendar access refused, and events show with reminder access refused")
    func testAccessIsSeparate() async {
        let mat = reminder("Prendre mon tapis", due: at(3, 16))
        let train = event("Train", at(3, 17), at(3, 19))

        let withoutCalendars = await nextEvent(events: [train], reminders: [mat], at: at(3, 15)) { $0.status = .denied }
        #expect(withoutCalendars == mat)

        let withoutReminders = await nextEvent(events: [train], reminders: [mat], at: at(3, 15)) { $0.reminderStatus = .denied }
        #expect(withoutReminders == train)
    }

    @Test("Switching the widget on requests reminder access too, never at launch")
    func testSwitchingOnRequestsReminderAccess() async {
        let source = FixtureCalendarSource()
        source.reminderStatus = .notDetermined
        let (launched, _) = makeViewModel(
            service: makeService(source, clock: TestClock()),
            config: DockConfig(showCalendarWidget: true)
        )
        await launched.calendarWidgetService.refresh()
        #expect(source.reminderRequestCount == 0)

        let (viewModel, _) = makeViewModel(service: makeService(source, clock: TestClock()))
        await viewModel.setCalendarWidgetEnabled(true)
        #expect(source.reminderRequestCount == 1)
    }

    @Test("The preferences explain a missing reminder permission")
    func testAccessHelpForReminders() async {
        let source = FixtureCalendarSource()
        source.reminderStatus = .denied
        let (viewModel, _) = makeViewModel(service: makeService(source, clock: TestClock()))
        await viewModel.setCalendarWidgetEnabled(true)
        #expect(viewModel.showsCalendarAccessHelp == true)

        source.reminderStatus = .granted
        await viewModel.calendarWidgetService.refresh()
        #expect(viewModel.showsCalendarAccessHelp == false)
    }

    // MARK: - Three Next Events

    private func nextEvents(events: [CalendarEvent] = [], reminders: [CalendarEvent] = [], at date: Date) async -> [CalendarEvent] {
        let source = FixtureCalendarSource()
        source.events = events
        source.reminders = reminders
        let clock = TestClock()
        clock.now = date
        let service = makeService(source, clock: clock)
        await service.refresh()
        return service.state.nextEvents
    }

    @Test("The widget keeps the three soonest items, in order")
    func testThreeSoonestItems() async {
        let first = event("First", at(3, 10), at(3, 11))
        let second = event("Second", at(3, 12), at(3, 13))
        let third = event("Third", at(3, 14), at(3, 15))
        let fourth = event("Fourth", at(3, 16), at(3, 17))
        #expect(await nextEvents(events: [fourth, third, first, second], at: at(3, 9)) == [first, second, third])
    }

    @Test("An event in progress comes first, then a reminder falling during it stays visible")
    func testEventInProgressThenReminder() async {
        let meeting = event("Meeting", at(3, 9), at(3, 12))
        let mat = reminder("Prendre mon tapis", due: at(3, 11))
        let lunch = event("Lunch", at(3, 13), at(3, 14))
        #expect(await nextEvents(events: [lunch, meeting], reminders: [mat], at: at(3, 10)) == [meeting, mat, lunch])
    }

    @Test("A single qualifying item stays alone")
    func testSingleItem() async {
        let first = event("First", at(3, 10), at(3, 11))
        #expect(await nextEvents(events: [first], at: at(3, 9)) == [first])
    }

    // MARK: - All-day priority

    @Test("Today's all-day event comes before everything else")
    func testAllDayEventHasPriority() async {
        let birthday = event("Birthday", at(3, 0), at(4, 0), allDay: true)
        let meeting = event("Meeting", at(3, 9), at(3, 12))
        let lunch = event("Lunch", at(3, 13), at(3, 14))
        let train = event("Train", at(3, 15), at(3, 16))
        #expect(await nextEvents(events: [train, lunch, meeting, birthday], at: at(3, 10)) == [birthday, meeting, lunch])
    }

    @Test("Only one all-day event is shown, so the timed items keep their place")
    func testOneAllDayEventOnly() async {
        let birthday = event("Birthday", at(3, 0), at(4, 0), allDay: true)
        let holiday = event("Holiday", at(3, 0), at(4, 0), allDay: true)
        let lunch = event("Lunch", at(3, 13), at(3, 14))
        #expect(await nextEvents(events: [holiday, birthday, lunch], at: at(3, 10)) == [birthday, lunch])
    }

    @Test("Tomorrow's all-day event does not qualify")
    func testTomorrowAllDayEventIgnored() async {
        let trip = event("Trip", at(4, 0), at(5, 0), allDay: true)
        #expect(await nextEvents(events: [trip], at: at(3, 10)).isEmpty)
    }

    @Test("A reminder without a time never takes the all-day place")
    func testDateOnlyReminderIsNotAllDayPriority() async {
        let dateOnly = reminder("Date only", due: at(3, 16), dateOnly: true)
        let lunch = event("Lunch", at(3, 13), at(3, 14))
        #expect(await nextEvents(events: [lunch], reminders: [dateOnly], at: at(3, 10)) == [lunch])
    }
}
