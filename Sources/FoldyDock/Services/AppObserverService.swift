import AppKit
import ApplicationServices
import Combine

@MainActor
public final class AppObserverService: ObservableObject {
    public static let shared = AppObserverService()

    @Published public private(set) var runningBundleIds: Set<String> = []
    @Published public private(set) var activeAppBundleId: String?
    @Published public private(set) var windowCountsByBundleId: [String: Int] = [:]
    @Published public private(set) var hiddenAppBundleIds: Set<String> = []

    /// Callbacks for ViewModel to react to unpinned apps
    public var onAppLaunched: ((NSRunningApplication) -> Void)?
    public var onAppTerminated: ((String) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    private var stableWindowOrderPerPid: [pid_t: [CGWindowID]] = [:]
    private var lastCycledIndexPerPid: [pid_t: Int] = [:]

    @_silgen_name("_AXUIElementGetWindow")
    private static func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

    public init() {
        refreshRunningApps()
        setupNotificationObservers()
        startPeriodicSync()
    }

    deinit {
        syncTimer?.invalidate()
    }

    /// Refresh the list of currently running regular applications and their window counts
    public func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningBundleIds = Set(apps.compactMap(\.bundleIdentifier))
        self.activeAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        self.refreshWindowCounts()
        self.refreshHiddenApps()
    }

    /// Counts open user windows for all regular applications
    public func refreshWindowCounts() {
        let opts: CGWindowListOption = [.excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        var pidToBundle: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, app.activationPolicy == .regular {
                pidToBundle[app.processIdentifier] = bid
            }
        }

        var counts: [String: Int] = [:]
        for win in list {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = win[kCGWindowOwnerPID as String] as? pid_t,
                  let bid = pidToBundle[pid],
                  let bounds = win[kCGWindowBounds as String] as? [String: Any],
                  let w = bounds["Width"] as? Double,
                  let h = bounds["Height"] as? Double,
                  let alpha = win[kCGWindowAlpha as String] as? Double, alpha > 0.05,
                  w >= 150 && h >= 150 else {
                continue
            }

            let title = (win[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Exclude macOS system 500x500 empty-titled offscreen helper windows
            if w == 500 && h == 500 && title.isEmpty {
                continue
            }

            counts[bid, default: 0] += 1
        }

        if self.windowCountsByBundleId != counts {
            self.windowCountsByBundleId = counts
        }
    }

    /// Refreshes the set of applications that are hidden (via ⌘H/Masquer or with all windows minimized via yellow button)
    public func refreshHiddenApps() {
        var hiddenBids: Set<String> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier else { continue }
            if app.isHidden {
                hiddenBids.insert(bid)
                continue
            }

            // Check if all windows are minimized (yellow traffic light button)
            let appElem = AXUIElementCreateApplication(app.processIdentifier)
            var winListRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef) == .success,
               let wins = winListRef as? [AXUIElement], !wins.isEmpty {
                var minCount = 0
                for w in wins {
                    var val: CFTypeRef?
                    if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &val) == .success,
                       let b = val as? Bool, b {
                        minCount += 1
                    }
                }
                if minCount > 0 && minCount == wins.count {
                    hiddenBids.insert(bid)
                }
            }
        }

        if self.hiddenAppBundleIds != hiddenBids {
            self.hiddenAppBundleIds = hiddenBids
        }
    }

    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let previousBids = self.runningBundleIds
                self.refreshRunningApps()
                let removedBids = previousBids.subtracting(self.runningBundleIds)
                for bid in removedBids {
                    self.onAppTerminated?(bid)
                }
            }
        }
    }

    private func setupNotificationObservers() {
        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.activationPolicy == .regular }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                guard let self = self, let bid = app.bundleIdentifier else { return }
                self.runningBundleIds.insert(bid)
                self.refreshWindowCounts()
                self.refreshHiddenApps()
                self.onAppLaunched?(app)
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                guard let self = self, let bid = app.bundleIdentifier else { return }
                self.stableWindowOrderPerPid.removeValue(forKey: app.processIdentifier)
                self.lastCycledIndexPerPid.removeValue(forKey: app.processIdentifier)
                self.runningBundleIds.remove(bid)
                self.refreshWindowCounts()
                self.refreshHiddenApps()
                self.onAppTerminated?(bid)
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.activeAppBundleId = app.bundleIdentifier
                self?.refreshWindowCounts()
                self?.refreshHiddenApps()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowCounts()
                self?.refreshHiddenApps()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didHideApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowCounts()
                self?.refreshHiddenApps()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowCounts()
                self?.refreshHiddenApps()
            }
            .store(in: &cancellables)
    }

    /// Launches or brings to front an application, focusing its windows and switching virtual desktops (Spaces) if needed.
    public func launchApp(item: DockItem) {
        let bid = item.bundleIdentifier

        // 1. If already running, activate directly, unhide, yield activation, and raise windows to switch Spaces.
        let matchingApps: [NSRunningApplication] = {
            if let bid = bid {
                return NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            } else if let path = item.appPath {
                return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
            }
            return []
        }()

        if let runningApp = matchingApps.first(where: { $0.activationPolicy == .regular }) ?? matchingApps.first {
            activateRunningApp(runningApp, bundleIdentifier: bid, item: item)
            return
        }

        // 2. Otherwise, launch the application via NSWorkspace
        var appURL: URL?
        if let path = item.appPath, FileManager.default.fileExists(atPath: path) {
            appURL = URL(fileURLWithPath: path)
        } else if let bid = bid {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        }

        guard let targetURL = appURL else {
            print("[AppObserverService] Cannot find application for: \(item.title)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(at: targetURL, configuration: config) { _, error in
            if let error = error {
                print("[AppObserverService] Failed to open \(item.title): \(error.localizedDescription)")
            }
        }
    }

    private func windowID(for element: AXUIElement) -> CGWindowID {
        var wid: CGWindowID = 0
        if Self._AXUIElementGetWindow(element, &wid) == .success, wid > 0 {
            return wid
        }
        return CGWindowID(bitPattern: Int32(truncatingIfNeeded: CFHash(element)))
    }

    private func unminimizeWindow(_ window: AXUIElement) {
        var minVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minVal) == .success,
           let isMin = minVal as? Bool, isMin {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    private func raiseWindow(_ window: AXUIElement, appElement: AXUIElement) {
        unminimizeWindow(window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
    }

    private func copyAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute as CFString, &val) == .success {
            return val
        }
        return nil
    }

    /// Cycles through open windows using the application's native Window menu.
    /// This is the most reliable native macOS mechanism: it cleanly shifts focus across different virtual desktops (Spaces),
    /// restores minimized windows, raises occluded windows, and works consistently for browsers (Firefox, Chrome, Safari) and standard apps.
    private func cycleViaWindowMenu(appElem: AXUIElement, pid: pid_t, eligibleWindows: [AXUIElement]) -> Bool {
        guard let menuBarRef = copyAXAttribute(appElem, kAXMenuBarAttribute as String),
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() else {
            return false
        }
        let menuBar = menuBarRef as! AXUIElement
        guard let menuBarItems = copyAXAttribute(menuBar, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return false
        }

        for (idx, item) in menuBarItems.enumerated() {
            let title = (copyAXAttribute(item, kAXTitleAttribute as String) as? String) ?? ""
            guard WindowCycleHelper.isWindowMenu(title: title, index: idx, totalMenuItems: menuBarItems.count) else {
                continue
            }

            guard let menus = copyAXAttribute(item, kAXChildrenAttribute as String) as? [AXUIElement],
                  let menu = menus.first,
                  let subItems = copyAXAttribute(menu, kAXChildrenAttribute as String) as? [AXUIElement] else {
                continue
            }

            let menuTuples: [(title: String, isSeparator: Bool, isMarked: Bool)] = subItems.map { sub in
                let subTitle = (copyAXAttribute(sub, kAXTitleAttribute as String) as? String) ?? ""
                let mark = copyAXAttribute(sub, "AXMenuItemMarkChar") as? String
                let isMarked = mark != nil && !mark!.isEmpty
                return (title: subTitle, isSeparator: subTitle.isEmpty, isMarked: isMarked)
            }

            let candidateIndices = WindowCycleHelper.candidateWindowIndices(items: menuTuples)
            guard candidateIndices.count > 1 else { continue }

            // 1. Detect current window index via checkmark (✓)
            var currentRelativeIndex: Int? = nil
            for (relIdx, itemIdx) in candidateIndices.enumerated() {
                if menuTuples[itemIdx].isMarked {
                    currentRelativeIndex = relIdx
                    break
                }
            }

            // 2. If checkmark is missing or pending async update, detect via focused window title
            if currentRelativeIndex == nil {
                var focusedWinRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedWinRef) == .success,
                   let focusedWin = focusedWinRef,
                   CFGetTypeID(focusedWin) == AXUIElementGetTypeID() {
                    let focusedTitle = (copyAXAttribute(focusedWin as! AXUIElement, kAXTitleAttribute as String) as? String) ?? ""
                    if !focusedTitle.isEmpty {
                        for (relIdx, itemIdx) in candidateIndices.enumerated() {
                            let itemTitle = menuTuples[itemIdx].title
                            if itemTitle == focusedTitle || itemTitle.contains(focusedTitle) || focusedTitle.contains(itemTitle) {
                                currentRelativeIndex = relIdx
                                break
                            }
                        }
                    }
                }
            }

            // 3. If still unknown, fall back to lastCycledIndexPerPid
            let fallbackIndex = lastCycledIndexPerPid[pid]
            let effectiveIndex = currentRelativeIndex ?? fallbackIndex

            // Calculate next index in rotation
            let nextRelativeIndex = WindowCycleHelper.nextWindowIndex(currentIndex: effectiveIndex, windowCount: candidateIndices.count)
            lastCycledIndexPerPid[pid] = nextRelativeIndex

            let targetMenuIndex = candidateIndices[nextRelativeIndex]
            let targetItem = subItems[targetMenuIndex]
            let targetTitle = menuTuples[targetMenuIndex].title

            let err = AXUIElementPerformAction(targetItem, kAXPressAction as CFString)
            if err == .success {
                // If a matching window exists on the current Space, raise it immediately for zero-lag response
                if let matchingWin = eligibleWindows.first(where: {
                    let wTitle = (self.copyAXAttribute($0, kAXTitleAttribute as String) as? String) ?? ""
                    return !wTitle.isEmpty && (wTitle == targetTitle || targetTitle.contains(wTitle) || wTitle.contains(targetTitle))
                }) {
                    self.raiseWindow(matchingWin, appElement: appElem)
                }
                return true
            }
        }
        return false
    }

    /// Triggers the native macOS window cycle keyboard shortcut (Cmd + `) directly to the target application PID.
    private func triggerWindowCycleKeyboardShortcut(for pid: pid_t) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 50, keyDown: true)
        down?.flags = .maskCommand
        down?.postToPid(pid)

        let up = CGEvent(keyboardEventSource: src, virtualKey: 50, keyDown: false)
        up?.flags = .maskCommand
        up?.postToPid(pid)
    }

    private func executeAppleScript(bundleIdentifier: String?, command: String) {
        guard let bid = bundleIdentifier?.replacingOccurrences(of: "\"", with: ""), !bid.isEmpty else { return }
        // Exclude Firefox or other apps known to hang or ignore AppleEvents
        if bid == "org.mozilla.firefox" || bid.contains("firefox") { return }
        Task.detached(priority: .userInitiated) {
            let script = """
            with timeout of 1 seconds
                tell application id "\(bid)"
                    \(command)
                end tell
            end timeout
            """
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }

    /// Brings an already-open application to focus, unhiding, unminimizing, and switching Spaces if necessary.
    /// When the application is already the frontmost active application and has multiple open windows,
    /// cycles focus sequentially through each window in round-robin order without ping-ponging.
    public func activateRunningApp(_ runningApp: NSRunningApplication, bundleIdentifier: String?, item: DockItem? = nil) {
        let isAlreadyFrontmost = (runningApp.isActive ||
                                  NSWorkspace.shared.frontmostApplication?.processIdentifier == runningApp.processIdentifier ||
                                  self.activeAppBundleId == runningApp.bundleIdentifier) && !runningApp.isHidden

        let appElem = AXUIElementCreateApplication(runningApp.processIdentifier)
        var winListRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef)
        let wins = (winListRef as? [AXUIElement]) ?? []

        // Filter strictly for eligible standard user windows (standard document windows or dialogs)
        let eligibleWindows = wins.filter { w in
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String, role == (kAXWindowRole as String) else {
                return false
            }
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String {
                return subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String)
            }
            return false
        }

        let bid = bundleIdentifier ?? runningApp.bundleIdentifier ?? ""
        let knownWindowCount = max(windowCountsByBundleId[bid] ?? 0, eligibleWindows.count)

        // Window Cycling: When already frontmost and multi-window, cycle to the next window
        if WindowCycleHelper.shouldCycleWindows(isFrontmost: isAlreadyFrontmost, isHidden: runningApp.isHidden, eligibleWindowCount: knownWindowCount) {
            // Strategy 1: Attempt cycling via the application's Window menu.
            // This is the most robust native macOS mechanism: it handles windows across different Spaces,
            // unminimizes minimized windows, raises occluded windows, and preserves application state.
            if cycleViaWindowMenu(appElem: appElem, pid: runningApp.processIdentifier, eligibleWindows: eligibleWindows) {
                if #available(macOS 14.0, *) {
                    NSApp.yieldActivation(to: runningApp)
                }
                return
            }

            // Strategy 2: If Window menu is not available, perform AXUIElement round-robin raising
            // for windows on the current Space.
            if eligibleWindows.count >= 2 {
                let winMap: [CGWindowID: AXUIElement] = Dictionary(uniqueKeysWithValues: eligibleWindows.map { (windowID(for: $0), $0) })
                let currentWindowIDs = eligibleWindows.map { windowID(for: $0) }

                let previousOrder = stableWindowOrderPerPid[runningApp.processIdentifier] ?? []
                let stableOrder = WindowCycleHelper.reconcileStableOrder(existingOrder: previousOrder, currentWindowIDs: currentWindowIDs)
                stableWindowOrderPerPid[runningApp.processIdentifier] = stableOrder

                var focusedWinRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedWinRef)

                var focusedID: CGWindowID? = nil
                if let focused = focusedWinRef, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                    focusedID = windowID(for: focused as! AXUIElement)
                }

                let currentIndex = focusedID.flatMap { stableOrder.firstIndex(of: $0) }
                let nextIndex = WindowCycleHelper.nextWindowIndex(currentIndex: currentIndex, windowCount: stableOrder.count)
                let targetID = stableOrder[nextIndex]

                if let targetWindow = winMap[targetID] {
                    raiseWindow(targetWindow, appElement: appElem)
                }

                if #available(macOS 14.0, *) {
                    NSApp.yieldActivation(to: runningApp)
                }
                return
            }

            // Strategy 3: Standard macOS window cycling shortcut (Cmd + `)
            triggerWindowCycleKeyboardShortcut(for: runningApp.processIdentifier)
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: runningApp)
            }
            return
        }

        // Standard 1st-click activation: bring application to foreground
        self.activeAppBundleId = runningApp.bundleIdentifier

        // 1. Unhide if hidden
        if runningApp.isHidden {
            runningApp.unhide()
        }

        // 2. Cooperative activation for macOS 14+ (crucial for LSUIElement background docks)
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: runningApp)
            runningApp.activate(options: [.activateAllWindows])
        } else {
            runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        // 3. Raise the frontmost window (restoring it if it was minimized).
        // Other minimized windows remain safely in dock until their turn in rotation (Q3: Option B).
        if let frontWindow = eligibleWindows.first ?? wins.first {
            raiseWindow(frontWindow, appElement: appElem)
        }

        // 4. Send AppleScript reopen & activate to ensure macOS Mission Control switches to the Space of the open window
        executeAppleScript(bundleIdentifier: bundleIdentifier ?? runningApp.bundleIdentifier, command: "reopen\nactivate")
    }

    /// Terminates an application by bundle identifier (used on middle-click or context menu)
    public func terminateApp(bundleIdentifier: String) {
        let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if matchingApps.isEmpty {
            // Already dead: immediately clean up tracking
            self.runningBundleIds.remove(bundleIdentifier)
            self.onAppTerminated?(bundleIdentifier)
            return
        }

        for app in matchingApps {
            self.stableWindowOrderPerPid.removeValue(forKey: app.processIdentifier)
            self.lastCycledIndexPerPid.removeValue(forKey: app.processIdentifier)
            let initiated = app.terminate()
            // If graceful terminate failed or app is stubborn (e.g. background continuity app), force terminate
            if !initiated || !app.isTerminated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if !app.isTerminated {
                        app.forceTerminate()
                    }
                }
            }
        }

        // Clean up from tracking set immediately so UI reflects termination
        self.runningBundleIds.remove(bundleIdentifier)
        self.onAppTerminated?(bundleIdentifier)
    }

    /// Checks if a given bundle ID is running
    public func isRunning(bundleIdentifier: String?) -> Bool {
        guard let bid = bundleIdentifier else { return false }
        return runningBundleIds.contains(bid)
    }

    #if DEBUG
    public func setWindowCountsForTesting(_ counts: [String: Int]) {
        self.windowCountsByBundleId = counts
    }

    public func setRunningBundleIdsForTesting(_ bids: Set<String>) {
        self.runningBundleIds = bids
    }

    public func setHiddenAppBundleIdsForTesting(_ bids: Set<String>) {
        self.hiddenAppBundleIds = bids
    }
    #endif
}
