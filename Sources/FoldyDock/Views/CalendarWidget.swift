import SwiftUI

public struct CalendarWidget: View {
    @ObservedObject var viewModel: DockViewModel
    @ObservedObject var service: CalendarWidgetService
    public let iconSize: CGFloat
    public let dockHeight: CGFloat

    @State private var isHovered: Bool = false

    public init(viewModel: DockViewModel, service: CalendarWidgetService, iconSize: CGFloat, dockHeight: CGFloat) {
        self.viewModel = viewModel
        self.service = service
        self.iconSize = iconSize
        self.dockHeight = dockHeight
    }

    private var theme: DockTheme {
        viewModel.theme
    }

    private var dayNumberFontSize: CGFloat {
        iconSize * 0.42
    }

    private var titleFontSize: CGFloat {
        max(10.0, min(12.5, iconSize * 0.21))
    }

    private var captionFontSize: CGFloat {
        max(8.5, min(11.0, iconSize * 0.17))
    }

    private var labelFontSize: CGFloat {
        max(9.0, min(11.5, iconSize * 0.17))
    }

    public var body: some View {
        ZStack(alignment: .center) {
            Button(action: {
                viewModel.openCalendarApp()
            }) {
                HStack(spacing: 8) {
                    dateView

                    let events = displayedEvents
                    if events.count == 1 {
                        nextEventView(events[0])
                    } else if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                                compactEventRow(event)
                            }
                        }
                        .frame(maxWidth: iconSize * 3.2, alignment: .leading)
                    }
                }
                .padding(.horizontal, 7)
                .frame(minWidth: iconSize, minHeight: iconSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: iconSize)
            .background(
                RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                    .fill(theme.widgetBackground(isHovered: isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                    .stroke(theme.widgetStroke(isHovered: isHovered), lineWidth: 0.8)
            )

            if viewModel.config.showAppTitles {
                Text("Calendrier")
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(theme.labelColor(isHovered: isHovered))
                    .shadow(color: theme.labelShadowColor, radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .offset(y: -(iconSize / 2 + viewModel.config.labelDistance))
            }
        }
        // The dock takes its width from its content: without this the widget would shrink into
        // whatever width the dock already has instead of making it grow.
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: dockHeight, alignment: .center)
        .zIndex(isHovered ? 10 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
    }

    private func nextEventView(_ event: CalendarEvent) -> some View {
        let accent = accentColor(of: event)

        return VStack(alignment: .leading, spacing: 1) {
            if service.isTomorrow(event.start) {
                Text("DEMAIN")
                    .font(.system(size: captionFontSize, weight: .semibold))
                    .foregroundColor(theme.widgetArtistColor)
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                indicator(of: event, accent: accent)

                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundColor(theme.isDark && !event.isReminder ? accent : theme.widgetTitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(timeLabel(of: event))
                        .font(.system(size: captionFontSize, weight: .medium))
                        .foregroundColor(theme.isDark && !event.isReminder ? accent.opacity(0.8) : theme.widgetArtistColor)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            .padding(.leading, 3)
            .padding(.trailing, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(event.isReminder ? theme.widgetIdleIconBackground : accent.opacity(0.18))
            )
        }
        .frame(minWidth: iconSize * 1.4, maxWidth: iconSize * 2.8, alignment: .leading)
    }

    /// Three lines only fit from this icon size up.
    private var displayedEvents: [CalendarEvent] {
        Array(service.state.nextEvents.prefix(iconSize >= 44 ? 3 : 2))
    }

    /// One line per item, so several fit in the capsule's height. There is no room for an event's end time.
    private func compactEventRow(_ event: CalendarEvent) -> some View {
        let accent = accentColor(of: event)

        return HStack(spacing: 4) {
            indicator(of: event, accent: accent)

            if !event.isAllDay {
                Text(compactTimeLabel(of: event))
                    .font(.system(size: captionFontSize, weight: .medium))
                    .foregroundColor(theme.isDark && !event.isReminder ? accent.opacity(0.8) : theme.widgetArtistColor)
                    .lineLimit(1)
                    .fixedSize()
            }

            Text(event.title)
                .font(.system(size: captionFontSize, weight: .semibold))
                .foregroundColor(theme.isDark && !event.isReminder ? accent : theme.widgetTitleColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 1)
        .padding(.leading, 3)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: event.isAllDay ? titleFontSize : 4, style: .continuous)
                .fill(event.isReminder ? theme.widgetIdleIconBackground : accent.opacity(0.18))
        )
    }

    private func compactTimeLabel(of event: CalendarEvent) -> String {
        let start = event.start.formatted(date: .omitted, time: .shortened)
        return service.isTomorrow(event.start) ? "Demain \(start)" : start
    }

    private func accentColor(of event: CalendarEvent) -> Color {
        event.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.widgetArtistColor
    }

    @ViewBuilder
    private func indicator(of event: CalendarEvent, accent: Color) -> some View {
        if event.isAllDay {
            Image(systemName: "calendar")
                .font(.system(size: titleFontSize * 0.68, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: titleFontSize * 1.15, height: titleFontSize * 1.15)
                .background(Circle().fill(accent))
        } else if event.isReminder {
            Circle()
                .stroke(accent, lineWidth: 1.5)
                .frame(width: titleFontSize * 0.9, height: titleFontSize * 0.9)
                .padding(.leading, 2)
        } else {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accent)
                .frame(width: 3)
        }
    }

    /// An event shows its time range, a reminder its due time.
    private func timeLabel(of event: CalendarEvent) -> String {
        guard !event.isAllDay else { return "Toute la journée" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        guard !event.isReminder else { return start }
        return "\(start) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }

    private var dateView: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(service.state.today.formatted(.dateTime.weekday(.abbreviated)).capitalized)
                .font(.system(size: captionFontSize, weight: .semibold))
                .foregroundColor(theme.calendarWeekdayColor)
                .lineLimit(1)
                .fixedSize()

            Text(service.state.today.formatted(.dateTime.day()))
                .font(.system(size: dayNumberFontSize, weight: .regular))
                .foregroundColor(theme.widgetTitleColor)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
