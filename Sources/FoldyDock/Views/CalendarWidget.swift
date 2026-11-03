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

    private var weekdayFontSize: CGFloat {
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
                dateView
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

    private var dateView: some View {
        VStack(spacing: 0) {
            Text(service.state.today.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: weekdayFontSize, weight: .semibold))
                .foregroundColor(.red)
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
