import AppKit
import ApplicationServices

/// Production adapter for `AppWindowSource`: reads CGWindowList and the Accessibility tree.
/// Also resolves the live AX elements that window activation acts on.
public struct SystemAppWindowSource: AppWindowSource {
    public init() {}

    public func cgWindowRows() -> [CGWindowRow] {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { win in
            guard let pid = win[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = win[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else {
                return nil
            }
            return CGWindowRow(
                ownerPID: pid,
                layer: win[kCGWindowLayer as String] as? Int ?? 0,
                width: width,
                height: height,
                alpha: win[kCGWindowAlpha as String] as? Double ?? 0,
                title: (win[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }

    public func axWindows(pid: pid_t) -> [AXWindowReading] {
        Self.axWindowElements(pid: pid).map { element in
            AXWindowReading(
                windowID: Self.windowID(for: element),
                role: Self.copyAXAttribute(element, kAXRoleAttribute as String) as? String,
                subrole: Self.copyAXAttribute(element, kAXSubroleAttribute as String) as? String,
                title: (Self.copyAXAttribute(element, kAXTitleAttribute as String) as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                isMinimized: (Self.copyAXAttribute(element, kAXMinimizedAttribute as String) as? Bool) ?? false,
                isMain: (Self.copyAXAttribute(element, kAXMainAttribute as String) as? Bool) ?? false
            )
        }
    }

    public func windowMenuEntries(pid: pid_t) -> [WindowMenuEntry] {
        Self.windowMenuItemElements(pid: pid).enumerated().map { idx, item in
            let title = (Self.copyAXAttribute(item, kAXTitleAttribute as String) as? String) ?? ""
            let mark = Self.copyAXAttribute(item, "AXMenuItemMarkChar") as? String
            return WindowMenuEntry(index: idx, title: title, isSeparator: title.isEmpty, isMarked: !(mark ?? "").isEmpty)
        }
    }

    // MARK: - Live elements for activation

    static func axWindowElements(pid: pid_t) -> [AXUIElement] {
        let appElem = AXUIElementCreateApplication(pid)
        return (copyAXAttribute(appElem, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    static func axWindowElement(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        axWindowElements(pid: pid).first { self.windowID(for: $0) == windowID }
    }

    /// Items of the application's Window menu, in the same order as `windowMenuEntries(pid:)`.
    static func windowMenuItemElements(pid: pid_t) -> [AXUIElement] {
        let appElem = AXUIElementCreateApplication(pid)
        guard let menuBarRef = copyAXAttribute(appElem, kAXMenuBarAttribute as String),
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID(),
              let menuBarItems = copyAXAttribute(menuBarRef as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return []
        }

        for (idx, item) in menuBarItems.enumerated() {
            let title = (copyAXAttribute(item, kAXTitleAttribute as String) as? String) ?? ""
            guard WindowCycleHelper.isWindowMenu(title: title, index: idx, totalMenuItems: menuBarItems.count),
                  let menus = copyAXAttribute(item, kAXChildrenAttribute as String) as? [AXUIElement],
                  let menu = menus.first,
                  let subItems = copyAXAttribute(menu, kAXChildrenAttribute as String) as? [AXUIElement] else {
                continue
            }
            return subItems
        }
        return []
    }

    @_silgen_name("_AXUIElementGetWindow")
    private static func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

    static func windowID(for element: AXUIElement) -> CGWindowID {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(element, &wid) == .success, wid > 0 {
            return wid
        }
        return CGWindowID(bitPattern: Int32(truncatingIfNeeded: CFHash(element)))
    }

    static func copyAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute as CFString, &val) == .success {
            return val
        }
        return nil
    }
}
