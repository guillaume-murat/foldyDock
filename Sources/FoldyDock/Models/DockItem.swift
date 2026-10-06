import Foundation

public enum DockItemType: String, Codable, Sendable {
    case app
    case folder
    case separator
    case settings
}

public enum DropPlacement: Sendable {
    case before
    case after
    case merge
}

public struct DockItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var type: DockItemType
    public var title: String
    public var bundleIdentifier: String?
    public var appPath: String?
    public var isPinned: Bool
    public var subItems: [DockItem]?

    public init(
        id: UUID = UUID(),
        type: DockItemType,
        title: String = "",
        bundleIdentifier: String? = nil,
        appPath: String? = nil,
        isPinned: Bool = true,
        subItems: [DockItem]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.isPinned = isPinned
        self.subItems = subItems
    }

    /// Returns true if this is an app and its bundleIdentifier matches, or if it is a folder containing a matching app.
    public func matches(bundleIdentifier: String) -> Bool {
        if type == .app {
            return self.bundleIdentifier == bundleIdentifier
        } else if let subItems = subItems {
            return subItems.contains(where: { $0.bundleIdentifier == bundleIdentifier })
        }
        return false
    }

    /// Returns true if this item represents the macOS Finder application.
    public var isFinder: Bool {
        type == .app && (bundleIdentifier == "com.apple.finder" || title.lowercased() == "finder")
    }

    /// All bundle identifiers contained within this item (itself if app, or its children if folder).
    public var allBundleIdentifiers: [String] {
        if type == .app, let bid = bundleIdentifier {
            return [bid]
        }
        return subItems?.compactMap(\.bundleIdentifier) ?? []
    }

    /// Checks if any app within this item is currently running.
    public func isRunning(in runningBundleIds: Set<String>) -> Bool {
        for bid in allBundleIdentifiers {
            if runningBundleIds.contains(bid) {
                return true
            }
        }
        return false
    }
}
