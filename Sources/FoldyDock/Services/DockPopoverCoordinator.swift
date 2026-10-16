import Foundation
import CoreGraphics

public enum ActiveDockPopover: Equatable, Sendable {
    case none
    case folder(DockItem)
    case windowPicker(item: DockItem, windows: [AppWindowInfo])
    case applicationsLauncher
}

/// Deep module governing mutually-exclusive popover state (`.none`, `.folder`, `.windowPicker`, `.applicationsLauncher`),
/// outside-click dismissal debouncing, and anchor rect calculation above the dock panel.
public struct DockPopoverCoordinator: Sendable {
    public private(set) var activePopover: ActiveDockPopover = .none
    private var lastClosedFolderId: UUID?
    private var lastClosedFolderTime: Date?
    private var lastClosedLauncherTime: Date?

    public init() {}

    public var hasActivePopover: Bool {
        activePopover != .none
    }

    public var activeFolder: DockItem? {
        if case .folder(let folder) = activePopover {
            return folder
        }
        return nil
    }

    public var activeWindowPickerItem: DockItem? {
        if case .windowPicker(let item, _) = activePopover {
            return item
        }
        return nil
    }

    public var activeWindowPickerList: [AppWindowInfo] {
        if case .windowPicker(_, let windows) = activePopover {
            return windows
        }
        return []
    }

    public var isApplicationsLauncherOpen: Bool {
        activePopover == .applicationsLauncher
    }

    // MARK: - Folder Popover Transitions

    public mutating func openFolder(_ folder: DockItem) {
        lastClosedFolderId = nil
        lastClosedFolderTime = nil
        activePopover = .folder(folder)
    }

    public mutating func toggleFolder(_ folder: DockItem, now: Date = Date()) {
        if let lastId = lastClosedFolderId,
           let lastTime = lastClosedFolderTime,
           lastId == folder.id,
           now.timeIntervalSince(lastTime) < 0.4 {
            lastClosedFolderId = nil
            lastClosedFolderTime = nil
            if case .folder = activePopover {
                activePopover = .none
            }
            return
        }

        lastClosedFolderId = nil
        lastClosedFolderTime = nil

        if activeFolder?.id == folder.id {
            closeFolder(now: now)
        } else {
            activePopover = .folder(folder)
        }
    }

    public mutating func closeFolder(recordDismissal: Bool = true, now: Date = Date()) {
        if case .folder(let current) = activePopover {
            if recordDismissal {
                lastClosedFolderId = current.id
                lastClosedFolderTime = now
            }
            activePopover = .none
        }
    }

    // MARK: - Window Picker Popover Transitions

    public mutating func openWindowPicker(item: DockItem, windows: [AppWindowInfo]) {
        // Do not interrupt an interactive Folder or Applications Launcher popover
        switch activePopover {
        case .folder, .applicationsLauncher:
            return
        case .none, .windowPicker:
            activePopover = .windowPicker(item: item, windows: windows)
        }
    }

    public mutating func closeWindowPicker() {
        if case .windowPicker = activePopover {
            activePopover = .none
        }
    }

    // MARK: - Applications Launcher Transitions

    @discardableResult
    public mutating func toggleApplicationsLauncher(now: Date = Date()) -> Bool {
        if let lastTime = lastClosedLauncherTime,
           now.timeIntervalSince(lastTime) < 0.4 {
            lastClosedLauncherTime = nil
            if case .applicationsLauncher = activePopover {
                activePopover = .none
            }
            return false
        }

        lastClosedLauncherTime = nil

        if activePopover == .applicationsLauncher {
            closeApplicationsLauncher(recordDismissal: false, now: now)
            return false
        } else {
            if case .folder(let current) = activePopover {
                lastClosedFolderId = current.id
                lastClosedFolderTime = now
            }
            activePopover = .applicationsLauncher
            return true
        }
    }

    public mutating func closeApplicationsLauncher(recordDismissal: Bool = false, now: Date = Date()) {
        if activePopover == .applicationsLauncher {
            if recordDismissal {
                lastClosedLauncherTime = now
            }
            activePopover = .none
        }
    }

    // MARK: - Anchor Geometry Resolution

    public static func anchorRect(
        for itemId: UUID,
        itemFrames: [UUID: CGRect],
        folderAnchorFrames: [UUID: CGRect] = [:],
        dockHeight: CGFloat,
        fallbackMidX: CGFloat
    ) -> CGRect {
        let topY = max(0, dockHeight - 2)
        if let exactFolderFrame = folderAnchorFrames[itemId] {
            return CGRect(x: exactFolderFrame.origin.x, y: topY, width: exactFolderFrame.width, height: 1)
        }
        if let frame = itemFrames[itemId] {
            return CGRect(x: frame.origin.x, y: topY, width: frame.width, height: 1)
        }
        return CGRect(x: fallbackMidX - 40, y: topY, width: 80, height: 1)
    }
}
