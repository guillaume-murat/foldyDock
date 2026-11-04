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

                    if let event = service.state.nextEvent {
                        nextEventView(event)
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
        let accent = event.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.widgetArtistColor

        return VStack(alignment: .leading, spacing: 1) {
            if service.isTomorrow(event.start) {
                Text("DEMAIN")
                    .font(.system(size: captionFontSize, weight: .semibold))
                    .foregroundColor(theme.widgetArtistColor)
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundColor(theme.isDark ? accent : theme.widgetTitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(timeRange(of: event))
                        .font(.system(size: captionFontSize, weight: .medium))
                        .foregroundColor(theme.isDark ? accent.opacity(0.8) : theme.widgetArtistColor)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            .padding(.leading, 3)
            .padding(.trailing, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(accent.opacity(0.18))
            )
        }
        .frame(minWidth: iconSize * 1.4, maxWidth: iconSize * 2.8, alignment: .leading)
    }

    private func timeRange(of event: CalendarEvent) -> String {
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var dateView: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(service.state.today.formatted(.dateTime.weekday(.wide)).uppercased())
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
