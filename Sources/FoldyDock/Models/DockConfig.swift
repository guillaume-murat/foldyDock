import Foundation

public struct DockConfig: Codable, Equatable, Sendable {
    public var autohideEnabled: Bool
    public var autohideDelay: Double // In seconds (default: 0.3) - hide delay
    public var showDelay: Double // In seconds (default: 0.0) - show delay
    public var iconSize: Double // In points (default: 52)
    public var items: [DockItem]
    public var showTrash: Bool // In dock (default: true)
    public var horizontalPadding: Double // Horizontal dock padding (default: 12.0)
    public var verticalPadding: Double // Vertical dock padding per side (default: 12.0)
    public var showAppTitles: Bool // Show titles above app icons (default: true)
    public var showFolderTitles: Bool // Show titles above folder icons (default: true)
    public var labelDistance: Double // Fixed distance in points between icon and title/indicator (default: 10.0)
    public var showAppLauncher: Bool // Show FoldyDock Applications launcher at far left (default: true)
    public var hiddenAppOpacity: Double // Opacity of hidden/minimized apps (default: 0.5)
    public var launchAtLogin: Bool // Launch FoldyDock at macOS startup (default: false)
    public var itemSpacing: Double // Spacing between dock items in points (default: 12.0)

    public var hideDelay: Double {
        get { autohideDelay }
        set { autohideDelay = newValue }
    }

    public var dockHeight: Double {
        iconSize + verticalPadding * 2
    }

    enum CodingKeys: String, CodingKey {
        case autohideEnabled
        case autohideDelay
        case showDelay
        case iconSize
        case items
        case showTrash
        case horizontalPadding
        case verticalPadding
        case showAppTitles
        case showFolderTitles
        case labelDistance
        case showAppLauncher
        case hiddenAppOpacity
        case launchAtLogin
        case itemSpacing
    }

    public init(
        autohideEnabled: Bool = true,
        autohideDelay: Double = 0.3,
        showDelay: Double = 0.0,
        iconSize: Double = 52.0,
        items: [DockItem] = [],
        showTrash: Bool = true,
        horizontalPadding: Double = 12.0,
        verticalPadding: Double = 12.0,
        showAppTitles: Bool = true,
        showFolderTitles: Bool = true,
        labelDistance: Double = 10.0,
        showAppLauncher: Bool = true,
        hiddenAppOpacity: Double = 0.5,
        launchAtLogin: Bool = false,
        itemSpacing: Double = 12.0
    ) {
        self.autohideEnabled = autohideEnabled
        self.autohideDelay = autohideDelay
        self.showDelay = showDelay
        self.iconSize = iconSize
        self.items = items
        self.showTrash = showTrash
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.showAppTitles = showAppTitles
        self.showFolderTitles = showFolderTitles
        self.labelDistance = labelDistance
        self.showAppLauncher = showAppLauncher
        self.hiddenAppOpacity = hiddenAppOpacity
        self.launchAtLogin = launchAtLogin
        self.itemSpacing = itemSpacing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.autohideEnabled = try container.decodeIfPresent(Bool.self, forKey: .autohideEnabled) ?? true
        self.autohideDelay = try container.decodeIfPresent(Double.self, forKey: .autohideDelay) ?? 0.3
        self.showDelay = try container.decodeIfPresent(Double.self, forKey: .showDelay) ?? 0.0
        self.iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? 52.0
        self.items = try container.decodeIfPresent([DockItem].self, forKey: .items) ?? []
        self.showTrash = try container.decodeIfPresent(Bool.self, forKey: .showTrash) ?? true
        self.horizontalPadding = try container.decodeIfPresent(Double.self, forKey: .horizontalPadding) ?? 12.0
        self.verticalPadding = try container.decodeIfPresent(Double.self, forKey: .verticalPadding) ?? 12.0
        self.showAppTitles = try container.decodeIfPresent(Bool.self, forKey: .showAppTitles) ?? true
        self.showFolderTitles = try container.decodeIfPresent(Bool.self, forKey: .showFolderTitles) ?? true
        self.labelDistance = try container.decodeIfPresent(Double.self, forKey: .labelDistance) ?? 10.0
        self.showAppLauncher = try container.decodeIfPresent(Bool.self, forKey: .showAppLauncher) ?? true
        self.hiddenAppOpacity = try container.decodeIfPresent(Double.self, forKey: .hiddenAppOpacity) ?? 0.5
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.itemSpacing = try container.decodeIfPresent(Double.self, forKey: .itemSpacing) ?? 12.0
    }

    /// Default dock configuration with standard macOS applications and an example folder.
    public static var defaultConfig: DockConfig {
        let finder = DockItem(
            type: .app,
            title: "Finder",
            bundleIdentifier: "com.apple.finder",
            appPath: "/System/Library/CoreServices/Finder.app",
            isPinned: true
        )

        let safari = DockItem(
            type: .app,
            title: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appPath: "/Applications/Safari.app",
            isPinned: true
        )

        let messages = DockItem(
            type: .app,
            title: "Messages",
            bundleIdentifier: "com.apple.MobileSMS",
            appPath: "/System/Applications/Messages.app",
            isPinned: true
        )

        let mail = DockItem(
            type: .app,
            title: "Mail",
            bundleIdentifier: "com.apple.mail",
            appPath: "/System/Applications/Mail.app",
            isPinned: true
        )

        let commFolder = DockItem(
            type: .folder,
            title: "COMMUNICATION",
            isPinned: true,
            subItems: [messages, mail]
        )

        let terminal = DockItem(
            type: .app,
            title: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            appPath: "/System/Applications/Utilities/Terminal.app",
            isPinned: true
        )

        let settings = DockItem(
            type: .app,
            title: "Réglages",
            bundleIdentifier: "com.apple.systempreferences",
            appPath: "/System/Applications/System Settings.app",
            isPinned: true
        )

        return DockConfig(
            autohideEnabled: true,
            autohideDelay: 0.3,
            showDelay: 0.0,
            iconSize: 52.0,
            items: [finder, safari, commFolder, terminal, settings],
            labelDistance: 10.0,
            launchAtLogin: false
        )
    }
}
