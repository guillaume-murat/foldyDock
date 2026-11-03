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
        .frame(height: dockHeight, alignment: .center)
        .zIndex(isHovered ? 10 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
    }

    private func nextEventView(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundColor(theme.widgetTitleColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(timeLabel(for: event))
                .font(.system(size: captionFontSize, weight: .medium))
                .foregroundColor(theme.widgetArtistColor)
                .lineLimit(1)
        }
        .frame(minWidth: iconSize * 1.1, maxWidth: iconSize * 2.2, alignment: .leading)
    }

    /// The weekday tells an event tomorrow morning apart from one today at the same time.
    private func timeLabel(for event: CalendarEvent) -> String {
        if service.isToday(event.start) {
            return event.start.formatted(date: .omitted, time: .shortened)
        }
        return event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var dateView: some View {
        VStack(spacing: 0) {
            Text(service.state.today.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: captionFontSize, weight: .semibold))
                .foregroundColor(theme.widgetArtistColor)
                .lineLimit(1)
                .fixedSize()

            Text(service.state.today.formatted(.dateTime.day()))
                .font(.system(size: dayNumberFontSize, weight: .medium, design: .rounded))
                .foregroundColor(theme.widgetTitleColor)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
