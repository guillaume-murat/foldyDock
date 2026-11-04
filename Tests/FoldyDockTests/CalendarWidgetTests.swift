import Testing
import Foundation
@testable import FoldyDock

/// Fixture adapter: a permission status and a list of events, with no EventKit involved.
final class FixtureCalendarSource: CalendarEventSource, @unchecked Sendable {
    var status: CalendarAccessStatus = .granted
    var statusAfterRequest: CalendarAccessStatus = .granted
    var events: [CalendarEvent] = []
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
    CalendarEvent(title: title, start: start, end: end, isAllDay: allDay, color: color)
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
        return service.state.nextEvent
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

    @Test("All-day events never qualify")
    func testAllDayEventsIgnored() async {
        let birthday = event("Birthday", at(3, 0), at(4, 0), allDay: true)
        #expect(await nextEvent(among: [birthday], at: at(3, 10)) == nil)
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
        #expect(service.state.nextEvent == nil)
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
        #expect(viewModel.calendarWidgetService.state.nextEvent == standup)
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
        #expect(service.state.nextEvent == standup)

        clock.now = at(3, 11)
        await service.refresh()
        #expect(service.state.nextEvent == lunch)

        clock.now = at(3, 13)
        await service.refresh()
        #expect(service.state.nextEvent == nil)
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
        #expect(service.state.nextEvent == nil)

        clock.now = at(3, 12, 1)
        await service.refresh()
        #expect(service.state.nextEvent == trip)
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
        #expect(service.state.nextEvent == nil)

        let standup = event("Standup", at(3, 10), at(3, 11))
        source.events = [standup]
        source.notifyChange()
        for _ in 0..<100 where service.state.nextEvent == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(service.state.nextEvent == standup)
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

        #expect(service.state.nextEvent == nil)
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
        #expect(service.state.nextEvent == nil)

        source.status = .granted
        await service.refresh()
        #expect(service.state.nextEvent == standup)
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
}
