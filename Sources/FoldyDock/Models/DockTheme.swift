import SwiftUI
import AppKit

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var localizedTitle: String {
        switch self {
        case .system:
            return "Système (Auto)"
        case .light:
            return "Clair"
        case .dark:
            return "Sombre"
        }
    }
}

public struct DockTheme: Equatable, Sendable {
    public let isDark: Bool

    public init(isDark: Bool) {
        self.isDark = isDark
    }

    public static func resolve(mode: AppearanceMode, isSystemDark: Bool) -> DockTheme {
        switch mode {
        case .system:
            return DockTheme(isDark: isSystemDark)
        case .light:
            return DockTheme(isDark: false)
        case .dark:
            return DockTheme(isDark: true)
        }
    }

    public static func currentSystemIsDark() -> Bool {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    public var nsAppearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    // MARK: - Dock Container & Separators

    public var dockBorderTop: Color {
        isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.14)
    }

    public var dockBorderBottom: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.24)
    }

    public var separatorColor: Color {
        isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.20)
    }

    public var separatorEdgeColor: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    public var separatorCenterColor: Color {
        isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.30)
    }

    // MARK: - Labels & Running Indicators

    public func labelColor(isHovered: Bool) -> Color {
        if isDark {
            return isHovered ? .white : Color.white.opacity(0.92)
        } else {
            return isHovered ? Color.black : Color(white: 0.12).opacity(0.92)
        }
    }

    public var labelShadowColor: Color {
        isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.85)
    }

    public var indicatorDotColor: Color {
        isDark ? Color.white.opacity(0.95) : Color(white: 0.18).opacity(0.90)
    }

    public var indicatorDotShadowColor: Color {
        isDark ? Color.white.opacity(0.8) : Color.black.opacity(0.25)
    }

    // MARK: - Folder & Capsule Surfaces

    public var folderSurfaceTop: Color {
        isDark ? Color(white: 0.22).opacity(0.72) : Color.black.opacity(0.08)
    }

    public var folderSurfaceBottom: Color {
        isDark ? Color(white: 0.14).opacity(0.65) : Color.black.opacity(0.13)
    }

    public var folderStrokeTop: Color {
        isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.14)
    }

    public var folderStrokeBottom: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.22)
    }

    public var emptyFolderIconTop: Color {
        isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    public var emptyFolderIconBottom: Color {
        isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.32)
    }

    // MARK: - Now Playing Widget

    public func widgetBackground(isHovered: Bool) -> Color {
        if isDark {
            return Color.white.opacity(isHovered ? 0.08 : 0.04)
        } else {
            return Color.black.opacity(isHovered ? 0.09 : 0.05)
        }
    }

    public func widgetStroke(isHovered: Bool) -> Color {
        if isDark {
            return Color.white.opacity(isHovered ? 0.20 : 0.10)
        } else {
            return Color.black.opacity(isHovered ? 0.22 : 0.12)
        }
    }

    public var widgetIdleIconColor: Color {
        isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.45)
    }

    public var widgetIdleIconBackground: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.07)
    }

    public var widgetIdleTextColor: Color {
        isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.50)
    }

    public var widgetTitleColor: Color {
        isDark ? Color.white.opacity(0.95) : Color(white: 0.10)
    }

    public var widgetArtistColor: Color {
        isDark ? Color.white.opacity(0.55) : Color(white: 0.35)
    }

    public var widgetTransportSecondaryColor: Color {
        isDark ? Color.white.opacity(0.80) : Color(white: 0.20)
    }

    public var widgetPlayIconColor: Color {
        isDark ? Color.white : Color(white: 0.10)
    }

    public var widgetPlayCircleBackground: Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    // MARK: - Popovers (Folder Popover & Applications Popover)

    public var popoverPrimaryText: Color {
        isDark ? Color.white : Color(white: 0.10)
    }

    public var popoverSecondaryText: Color {
        isDark ? Color.white.opacity(0.65) : Color(white: 0.38)
    }

    public var popoverControlFill: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)
    }

    public var popoverDivider: Color {
        isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
    }

    public var folderPopoverBackground: Color {
        isDark ? Color(white: 0.14).opacity(0.35) : Color.white.opacity(0.45)
    }
}
