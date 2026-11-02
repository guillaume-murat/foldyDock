import SwiftUI

/// The dock's single vertical separator look: a thin line fading at both ends, with a soft glow in dark mode.
public struct DockSeparatorView: View {
    public static let width: CGFloat = 1.5

    let height: CGFloat
    let theme: DockTheme

    public init(height: CGFloat, theme: DockTheme) {
        self.height = height
        self.theme = theme
    }

    public var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        theme.separatorEdgeColor,
                        theme.separatorCenterColor,
                        theme.separatorEdgeColor
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: Self.width, height: height)
            .shadow(color: theme.isDark ? Color.white.opacity(0.25) : Color.clear, radius: 1)
    }
}
