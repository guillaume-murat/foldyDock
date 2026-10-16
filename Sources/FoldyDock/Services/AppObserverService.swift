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
    private var stableWindowKeysPerPid: [pid_t: [String]] = [:]
    private var lastCycledKeyPerPid: [pid_t: String] = [:]
    private var lastCycledIndexPerPid: [pid_t: Int] = [:]

    @_silgen_name("_AXUIElementGetWindow")
    nonisolated private static func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

    public init() {
        refreshRunningApps()
        setupNotificationObservers()
        startPeriodicSync()
    }

    /// Returns true if the application has macOS Accessibility (AX) permission.
    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission in System Settings if not already granted.
    @discardableResult
    public func requestAccessibilityPermissionIfNeeded() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        return trusted
    }

    deinit {
        syncTimer?.invalidate()
    }

    /// Refresh the list of currently running regular applications and their window counts
    public func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningBundleIds = Set(apps.compactMap(\.bundleIdentifier))
        if let frontBid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontBid != Bundle.main.bundleIdentifier {
            self.activeAppBundleId = frontBid
        }
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
                self.stableWindowKeysPerPid.removeValue(forKey: app.processIdentifier)
                self.lastCycledKeyPerPid.removeValue(forKey: app.processIdentifier)
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

    nonisolated private static func windowID(for element: AXUIElement) -> CGWindowID {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(element, &wid) == .success, wid > 0 {
            return wid
        }
        return CGWindowID(bitPattern: Int32(truncatingIfNeeded: CFHash(element)))
    }

    nonisolated private static func unminimizeWindow(_ window: AXUIElement) {
        var minVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minVal) == .success,
           let isMin = minVal as? Bool, isMin {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    nonisolated private static func raiseWindow(_ window: AXUIElement, appElement: AXUIElement) {
        unminimizeWindow(window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
    }

    nonisolated private static func copyAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute as CFString, &val) == .success {
            return val
        }
        return nil
    }

    /// Locates the Window menu element and its child menu items if present.
    nonisolated private static func findWindowMenuItems(appElem: AXUIElement) -> [AXUIElement]? {
        guard let menuBarRef = copyAXAttribute(appElem, kAXMenuBarAttribute as String),
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let menuBar = menuBarRef as! AXUIElement
        guard let menuBarItems = copyAXAttribute(menuBar, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return nil
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
            return subItems
        }
        return nil
    }

    /// Cycles through open windows using the application's native Window menu.
    /// This is the most reliable native macOS mechanism: it cleanly shifts focus across different virtual desktops (Spaces),
    /// restores minimized windows, raises occluded windows, and works consistently for browsers (Firefox, Chrome, Safari) and standard apps.
    private func cycleViaWindowMenu(appElem: AXUIElement, pid: pid_t, eligibleWindows: [AXUIElement]) -> Bool {
        guard let subItems = Self.findWindowMenuItems(appElem: appElem) else {
            return false
        }

        let menuTuples: [(title: String, isSeparator: Bool, isMarked: Bool)] = subItems.map { sub in
            let subTitle = (Self.copyAXAttribute(sub, kAXTitleAttribute as String) as? String) ?? ""
            let mark = Self.copyAXAttribute(sub, "AXMenuItemMarkChar") as? String
            let isMarked = mark != nil && !mark!.isEmpty
            return (title: subTitle, isSeparator: subTitle.isEmpty, isMarked: isMarked)
        }

        let candidateIndices = WindowCycleHelper.candidateWindowIndices(items: menuTuples)
        guard candidateIndices.count > 1 else { return false }

        // Detect current window index via checkmark (✓) or focused window title
        var checkedRelativeIndex: Int? = nil
        for (relIdx, itemIdx) in candidateIndices.enumerated() {
            if menuTuples[itemIdx].isMarked {
                checkedRelativeIndex = relIdx
                break
            }
        }

        if checkedRelativeIndex == nil {
            var focusedWinRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedWinRef) == .success,
               let focusedWin = focusedWinRef,
               CFGetTypeID(focusedWin) == AXUIElementGetTypeID() {
                let focusedTitle = (Self.copyAXAttribute(focusedWin as! AXUIElement, kAXTitleAttribute as String) as? String) ?? ""
                if !focusedTitle.isEmpty {
                    for (relIdx, itemIdx) in candidateIndices.enumerated() {
                        let itemTitle = menuTuples[itemIdx].title
                        if itemTitle == focusedTitle || itemTitle.contains(focusedTitle) || focusedTitle.contains(itemTitle) {
                            checkedRelativeIndex = relIdx
                            break
                        }
                    }
                }
            }
        }

        // Prefer lastCycledIndexPerPid when valid so async checkmark updates in Firefox/Gecko never cause a stall or repeat
        let effectiveIndex: Int?
        if let lastIdx = lastCycledIndexPerPid[pid], lastIdx >= 0, lastIdx < candidateIndices.count {
            effectiveIndex = lastIdx
        } else {
            effectiveIndex = checkedRelativeIndex ?? 0
        }

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
                let wTitle = (Self.copyAXAttribute($0, kAXTitleAttribute as String) as? String) ?? ""
                return !wTitle.isEmpty && (wTitle == targetTitle || targetTitle.contains(wTitle) || wTitle.contains(targetTitle))
            }) {
                Self.raiseWindow(matchingWin, appElement: appElem)
            }
            return true
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

        let pid = runningApp.processIdentifier
        let bid = bundleIdentifier ?? runningApp.bundleIdentifier ?? ""

        // Ensure Accessibility permission is checked/prompted when multi-window cycling is needed
        let cgCount = windowCountsByBundleId[bid] ?? 0
        if cgCount > 1 && !AXIsProcessTrusted() {
            requestAccessibilityPermissionIfNeeded()
        }

        let appElem = AXUIElementCreateApplication(pid)
        var winListRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef)
        let wins = (winListRef as? [AXUIElement]) ?? []

        // Filter for standard user windows, allowing empty/missing subrole as standard window
        let eligibleWindows = wins.filter { w in
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String, role == (kAXWindowRole as String) else {
                return false
            }
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String, !subrole.isEmpty {
                guard subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String) else {
                    return false
                }
            }
            if bid == "com.apple.finder" {
                let title = (Self.copyAXAttribute(w, kAXTitleAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if title.isEmpty { return false }
            }
            return true
        }

        let openWindowInfos = Self.queryOpenWindows(for: bid)
        let knownWindowCount = max(cgCount, max(eligibleWindows.count, openWindowInfos.count))

        // Window Cycling: When already frontmost and multi-window, cycle to the next window
        if WindowCycleHelper.shouldCycleWindows(isFrontmost: isAlreadyFrontmost, isHidden: runningApp.isHidden, eligibleWindowCount: knownWindowCount) {
            self.activeAppBundleId = runningApp.bundleIdentifier

            // Strategy 1: Attempt cycling via the application's Window menu first.
            // Works across Spaces, unminimizes windows, and works reliably for Firefox, Chrome, Safari, and Finder.
            if cycleViaWindowMenu(appElem: appElem, pid: pid, eligibleWindows: eligibleWindows) {
                if #available(macOS 14.0, *) {
                    NSApp.yieldActivation(to: runningApp)
                    runningApp.activate(options: [])
                } else {
                    runningApp.activate(options: [.activateIgnoringOtherApps])
                }
                return
            }

            // Strategy 2: If Window menu is unavailable or failed, cycle through openWindowInfos in stable order.
            if openWindowInfos.count >= 2 {
                func stableKey(for info: AppWindowInfo, index: Int) -> String {
                    if let wid = info.windowID, wid > 0 {
                        return "wid-\(wid)"
                    }
                    return "title-\(info.menuTitle ?? info.title)-\(index)"
                }

                let keyedInfos = openWindowInfos.enumerated().map { (idx, info) in
                    (key: stableKey(for: info, index: idx), info: info)
                }
                let currentKeys = keyedInfos.map(\.key)
                let existingKeys = stableWindowKeysPerPid[pid] ?? []
                let orderedKeys = WindowCycleHelper.reconcileStableKeys(existingKeys: existingKeys, currentKeys: currentKeys)
                stableWindowKeysPerPid[pid] = orderedKeys

                let infoByKey: [String: AppWindowInfo] = Dictionary(
                    keyedInfos,
                    uniquingKeysWith: { first, _ in first }
                )
                let orderedInfos = orderedKeys.compactMap { infoByKey[$0] }

                if orderedInfos.count >= 2 {
                    let currentIndex: Int?
                    if let lastKey = lastCycledKeyPerPid[pid], let idx = orderedKeys.firstIndex(of: lastKey) {
                        currentIndex = idx
                    } else if let mainPair = keyedInfos.first(where: { $0.info.isMain }),
                              let idx = orderedKeys.firstIndex(of: mainPair.key) {
                        currentIndex = idx
                    } else {
                        currentIndex = 0
                    }

                    let nextIndex = WindowCycleHelper.nextWindowIndex(currentIndex: currentIndex, windowCount: orderedInfos.count)
                    let targetKey = orderedKeys[nextIndex]
                    let targetInfo = orderedInfos[nextIndex]
                    lastCycledKeyPerPid[pid] = targetKey
                    lastCycledIndexPerPid[pid] = nextIndex
                    selectWindow(targetInfo, for: bid)
                    return
                }
            }

            // Strategy 3: Standard macOS window cycling shortcut (Cmd + `)
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: runningApp)
                runningApp.activate(options: [])
            } else {
                runningApp.activate(options: [.activateIgnoringOtherApps])
            }
            triggerWindowCycleKeyboardShortcut(for: pid)
            return
        }

        // Standard 1st-click activation: bring application to foreground
        self.activeAppBundleId = runningApp.bundleIdentifier
        self.lastCycledKeyPerPid.removeValue(forKey: pid)
        self.lastCycledIndexPerPid.removeValue(forKey: pid)

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
            Self.raiseWindow(frontWindow, appElement: appElem)
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

    /// Internal query implementation that runs AX queries safely across background or main threads.
    nonisolated private static func queryOpenWindows(for bundleIdentifier: String) -> [AppWindowInfo] {
        let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let runningApp = matchingApps.first(where: { $0.activationPolicy == .regular }) ?? matchingApps.first else {
            return []
        }

        let appElem = AXUIElementCreateApplication(runningApp.processIdentifier)
        var winListRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef)
        let wins = (winListRef as? [AXUIElement]) ?? []

        // 1. Collect standard user windows from AXUIElement
        var windowInfos: [AppWindowInfo] = []
        var seenTitles = Set<String>()

        for (idx, w) in wins.enumerated() {
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String, role == (kAXWindowRole as String) else {
                continue
            }

            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String, !subrole.isEmpty {
                guard subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String) else {
                    continue
                }
            }

            let title = (copyAXAttribute(w, kAXTitleAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Filter out empty background desktop windows in Finder
            if title.isEmpty && bundleIdentifier == "com.apple.finder" {
                continue
            }

            var minRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minRef)
            let isMin = (minRef as? Bool) ?? false

            var mainRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(w, kAXMainAttribute as CFString, &mainRef)
            let isMain = (mainRef as? Bool) ?? false

            let wid = windowID(for: w)
            let displayTitle = title.isEmpty ? "Fenêtre \(idx + 1)" : title
            seenTitles.insert(displayTitle)

            windowInfos.append(AppWindowInfo(
                id: "\(runningApp.processIdentifier)-\(wid)-\(idx)",
                title: displayTitle,
                isMinimized: isMin,
                isMain: isMain,
                windowID: wid,
                menuTitle: title.isEmpty ? nil : title
            ))
        }

        // 2. Query Window menu for any windows on other Spaces or minimized items not in kAXWindowsAttribute
        if let subItems = findWindowMenuItems(appElem: appElem) {
            let menuTuples: [(title: String, isSeparator: Bool, isMarked: Bool)] = subItems.map { sub in
                let subTitle = (copyAXAttribute(sub, kAXTitleAttribute as String) as? String) ?? ""
                let mark = copyAXAttribute(sub, "AXMenuItemMarkChar") as? String
                let isMarked = mark != nil && !mark!.isEmpty
                return (title: subTitle, isSeparator: subTitle.isEmpty, isMarked: isMarked)
            }

            let candidateIndices = WindowCycleHelper.candidateWindowIndices(items: menuTuples)
            for (cIdx, itemIdx) in candidateIndices.enumerated() {
                let candidateTitle = menuTuples[itemIdx].title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidateTitle.isEmpty else { continue }
                let isMarked = menuTuples[itemIdx].isMarked

                if !seenTitles.contains(candidateTitle) {
                    seenTitles.insert(candidateTitle)
                    windowInfos.append(AppWindowInfo(
                        id: "\(runningApp.processIdentifier)-menu-\(itemIdx)-\(cIdx)",
                        title: candidateTitle,
                        isMinimized: false,
                        isMain: isMarked,
                        windowID: nil,
                        menuTitle: candidateTitle
                    ))
                } else if isMarked {
                    if let foundIndex = windowInfos.firstIndex(where: { $0.title == candidateTitle }) {
                        let existing = windowInfos[foundIndex]
                        windowInfos[foundIndex] = AppWindowInfo(
                            id: existing.id,
                            title: existing.title,
                            isMinimized: existing.isMinimized,
                            isMain: true,
                            windowID: existing.windowID,
                            menuTitle: existing.menuTitle
                        )
                    }
                }
            }
        }

        return windowInfos
    }

    /// Synchronously fetches open standard user document windows for an application.
    public func fetchOpenWindows(for bundleIdentifier: String) -> [AppWindowInfo] {
        Self.queryOpenWindows(for: bundleIdentifier)
    }

    /// Asynchronously fetches open standard user document windows off the main thread to avoid UI hitches.
    public func fetchOpenWindowsAsync(for bundleIdentifier: String) async -> [AppWindowInfo] {
        await Task.detached(priority: .userInitiated) {
            Self.queryOpenWindows(for: bundleIdentifier)
        }.value
    }

    /// Selects and brings a specific window to the foreground.
    /// Handles unminimization, Mission Control virtual Space switching, and cooperative application activation.
    public func selectWindow(_ window: AppWindowInfo, for bundleIdentifier: String) {
        let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let runningApp = matchingApps.first(where: { $0.activationPolicy == .regular }) ?? matchingApps.first else {
            return
        }

        let appElem = AXUIElementCreateApplication(runningApp.processIdentifier)
        var winListRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef)
        let wins = (winListRef as? [AXUIElement]) ?? []

        // 1. Unhide if hidden
        if runningApp.isHidden {
            runningApp.unhide()
        }

        // 2. Cooperative activation for macOS 14+ (crucial for LSUIElement background docks)
        self.activeAppBundleId = runningApp.bundleIdentifier
        let pid = runningApp.processIdentifier
        let selectedKey = (window.windowID ?? 0) > 0 ? "wid-\(window.windowID!)" : "title-\(window.menuTitle ?? window.title)"
        self.lastCycledKeyPerPid[pid] = selectedKey
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: runningApp)
            runningApp.activate(options: [])
        } else {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }

        // 3. Strategy 1: If Window menu item matches, perform kAXPressAction to switch Space and select the window
        var menuActionSucceeded = false
        let targetMenuTitle = window.menuTitle ?? (window.title.isEmpty ? nil : window.title)
        if let target = targetMenuTitle, let subItems = Self.findWindowMenuItems(appElem: appElem) {
            let menuTuples: [(title: String, isSeparator: Bool, isMarked: Bool)] = subItems.map { sub in
                let subTitle = (Self.copyAXAttribute(sub, kAXTitleAttribute as String) as? String) ?? ""
                let mark = Self.copyAXAttribute(sub, "AXMenuItemMarkChar") as? String
                let isMarked = mark != nil && !mark!.isEmpty
                return (title: subTitle, isSeparator: subTitle.isEmpty, isMarked: isMarked)
            }
            let candidateIndices = WindowCycleHelper.candidateWindowIndices(items: menuTuples)
            for (relIdx, itemIdx) in candidateIndices.enumerated() {
                let sTitle = menuTuples[itemIdx].title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sTitle.isEmpty && (sTitle == target || sTitle.hasPrefix(target) || target.hasPrefix(sTitle)) {
                    if AXUIElementPerformAction(subItems[itemIdx], kAXPressAction as CFString) == .success {
                        self.lastCycledIndexPerPid[pid] = relIdx
                        menuActionSucceeded = true
                        break
                    }
                }
            }
        }

        // 4. Strategy 2: If the window is on the current Space, unminimize and raise directly
        var axRaised = false
        if let matchingAXWindow = wins.first(where: { w in
            if let wid = window.windowID, Self.windowID(for: w) == wid { return true }
            let t = (Self.copyAXAttribute(w, kAXTitleAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !t.isEmpty && (t == window.title || t.hasPrefix(window.title) || window.title.hasPrefix(t))
        }) {
            Self.unminimizeWindow(matchingAXWindow)
            Self.raiseWindow(matchingAXWindow, appElement: appElem)
            axRaised = true
        }

        // 5. Fallback only if neither Window menu nor direct AX window raise succeeded
        if !menuActionSucceeded && !axRaised {
            executeAppleScript(bundleIdentifier: bundleIdentifier, command: "reopen\nactivate")
        }
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
