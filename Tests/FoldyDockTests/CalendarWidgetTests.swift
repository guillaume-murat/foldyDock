import Testing
import Foundation
@testable import FoldyDock

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

@MainActor
private func makeViewModel(service: CalendarWidgetService, config: DockConfig = DockConfig()) -> (DockViewModel, DockPersistenceService) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let persistence = DockPersistenceService(customDirectoryURL: directory)
    persistence.saveConfig(config)
    let viewModel = DockViewModel(persistenceService: persistence, appObserver: .shared, calendarWidget: service)
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
        let service = CalendarWidgetService(now: { clock.now }, calendar: utcCalendar)
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
        let (viewModel, persistence) = makeViewModel(service: CalendarWidgetService())
        await viewModel.setCalendarWidgetEnabled(true)

        #expect(viewModel.config.showCalendarWidget == true)
        #expect(persistence.loadConfig().showCalendarWidget == true)
    }
}
