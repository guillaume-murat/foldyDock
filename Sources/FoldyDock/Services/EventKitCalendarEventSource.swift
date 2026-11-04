import AppKit
import CoreFoundation
import EventKit
import Foundation

/// Production adapter of the event source seam.
public final class EventKitCalendarEventSource: CalendarEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var store: EKEventStore?
    private var storeSawAccess = false
    private var changeObserver: NSObjectProtocol?

    public init() {}

    public func accessStatus() -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        default: return .denied
        }
    }

    public func requestAccess() async {
        _ = try? await currentStore().requestFullAccessToEvents()
    }

    public func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard accessStatus() == .granted else { return [] }
        let store = currentStore()
        let hidden = Self.calendarIdentifiersHiddenInCalendarApp()
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map {
            CalendarEvent(
                title: $0.title ?? "",
                start: $0.startDate,
                end: $0.endDate,
                isAllDay: $0.isAllDay,
                color: Self.color(of: $0.calendar)
            )
        }
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        // No specific store: the observed one can be replaced when access is granted.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: nil
        ) { _ in handler() }
    }

    private static func color(of calendar: EKCalendar?) -> CalendarColor? {
        guard let cgColor = calendar?.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        return CalendarColor(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    /// A store created before access was granted keeps returning nothing, so it is replaced on the first
    /// read with access.
    private func currentStore() -> EKEventStore {
        lock.lock()
        defer { lock.unlock() }
        let hasAccess = accessStatus() == .granted
        if let store, hasAccess == storeSawAccess { return store }
        let fresh = EKEventStore()
        store = fresh
        storeSawAccess = hasAccess
        return fresh
    }

    /// EventKit does not expose which calendars are unticked in Calendar. Calendar keeps them in this
    /// undocumented preference; if it ever changes, every calendar is simply shown.
    private static func calendarIdentifiersHiddenInCalendarApp() -> Set<String> {
        let domain = "com.apple.iCal" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("DisabledCalendars" as CFString, domain)
        guard let windows = value as? [String: [String]] else { return [] }
        return Set(windows["MainWindow"] ?? [])
    }
}
