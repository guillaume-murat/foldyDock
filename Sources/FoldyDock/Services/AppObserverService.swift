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
    private var cyclingEngine = AppWindowCyclingEngine()

    /// Raw CGWindowList counts include helper windows (e.g. Chrome's full-screen toolbar), so each
    /// count is re-verified with the AX + Window menu list the Window Picker uses.
    private var rawWindowCounts: [String: Int] = [:]
    private var verifiedWindowCounts: [String: Int] = [:]
    private var verifiedAt: [String: Date] = [:]
    private var verificationsInFlight: Set<String> = []
    private static let verificationMaxAge: TimeInterval = 10

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
        let permission = AccessibilityPermissionService.shared
        permission.refresh()
        let trusted = permission.isTrusted
        if !trusted {
            permission.requestPermission()
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

        let now = Date()
        for (bid, raw) in counts {
            let isStale = now.timeIntervalSince(verifiedAt[bid] ?? .distantPast) > Self.verificationMaxAge
            if raw != rawWindowCounts[bid] || isStale {
                verifyWindowCount(for: bid)
            }
        }
        for bid in rawWindowCounts.keys where counts[bid] == nil {
            verifiedWindowCounts.removeValue(forKey: bid)
            verifiedAt.removeValue(forKey: bid)
        }
        rawWindowCounts = counts
        publishWindowCounts()
    }

    /// Prefers the verified count; falls back to the raw count when verification found nothing
    /// (no Accessibility permission, or an app without a Window menu whose windows are on another Space).
    nonisolated static func reconcileWindowCounts(raw: [String: Int], verified: [String: Int]) -> [String: Int] {
        raw.reduce(into: [:]) { result, pair in
            if let checked = verified[pair.key], checked > 0 {
                result[pair.key] = checked
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    private func publishWindowCounts() {
        let counts = Self.reconcileWindowCounts(raw: rawWindowCounts, verified: verifiedWindowCounts)
        if self.windowCountsByBundleId != counts {
            self.windowCountsByBundleId = counts
        }
    }

    private func verifyWindowCount(for bundleIdentifier: String) {
        guard !verificationsInFlight.contains(bundleIdentifier) else { return }
        verificationsInFlight.insert(bundleIdentifier)
        Task { [weak self] in
            let count = await Task.detached(priority: .utility) {
                Self.queryOpenWindows(for: bundleIdentifier).count
            }.value
            guard let self = self else { return }
            self.verificationsInFlight.remove(bundleIdentifier)
            guard self.rawWindowCounts[bundleIdentifier] != nil else { return }
            self.verifiedWindowCounts[bundleIdentifier] = count
            self.verifiedAt[bundleIdentifier] = Date()
            self.publishWindowCounts()
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
                self.cyclingEngine.removeState(for: app.processIdentifier)
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
                if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self?.activeAppBundleId = app.bundleIdentifier
                }
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

    /// Extracts Window menu sub-items and their normalized `WindowMenuEntry` metadata.
    nonisolated private static func inspectWindowMenu(appElem: AXUIElement) -> (elements: [AXUIElement], entries: [WindowMenuEntry]) {
        guard let subItems = findWindowMenuItems(appElem: appElem) else {
            return ([], [])
        }
        let entries: [WindowMenuEntry] = subItems.enumerated().map { (idx, sub) in
            let subTitle = (copyAXAttribute(sub, kAXTitleAttribute as String) as? String) ?? ""
            let mark = copyAXAttribute(sub, "AXMenuItemMarkChar") as? String
            let isMarked = mark != nil && !mark!.isEmpty
            return WindowMenuEntry(index: idx, title: subTitle, isSeparator: subTitle.isEmpty, isMarked: isMarked)
        }
        return (subItems, entries)
    }

    /// Extracts eligible standard user windows and their normalized `AXWindowEntry` metadata.
    nonisolated private static func inspectAXWindows(appElem: AXUIElement, bundleIdentifier: String) -> (allWindows: [AXUIElement], eligibleElements: [AXUIElement], entries: [AXWindowEntry]) {
        var winListRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef)
        let wins = (winListRef as? [AXUIElement]) ?? []

        var eligibleElements: [AXUIElement] = []
        var entries: [AXWindowEntry] = []

        for w in wins {
            let role = copyAXAttribute(w, kAXRoleAttribute as String) as? String
            let subrole = copyAXAttribute(w, kAXSubroleAttribute as String) as? String
            let title = (copyAXAttribute(w, kAXTitleAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard AppWindowCyclingEngine.isEligibleAXWindow(
                role: role,
                subrole: subrole,
                title: title,
                bundleIdentifier: bundleIdentifier
            ) else {
                continue
            }

            let isMin = (copyAXAttribute(w, kAXMinimizedAttribute as String) as? Bool) ?? false
            let isMain = (copyAXAttribute(w, kAXMainAttribute as String) as? Bool) ?? false
            let wid = windowID(for: w)

            eligibleElements.append(w)
            entries.append(AXWindowEntry(windowID: wid, title: title, isMinimized: isMin, isMain: isMain))
        }

        return (wins, eligibleElements, entries)
    }

    nonisolated private static func focusedWindowTitle(appElem: AXUIElement) -> String? {
        var focusedWinRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedWinRef) == .success,
           let focusedWin = focusedWinRef,
           CFGetTypeID(focusedWin) == AXUIElementGetTypeID() {
            return copyAXAttribute(focusedWin as! AXUIElement, kAXTitleAttribute as String) as? String
        }
        return nil
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

    private func yieldAndActivate(_ runningApp: NSRunningApplication, options: NSApplication.ActivationOptions = []) {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: runningApp)
            runningApp.activate(options: options)
        } else {
            runningApp.activate(options: options.union([.activateIgnoringOtherApps]))
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
        let axInspection = Self.inspectAXWindows(appElem: appElem, bundleIdentifier: bid)
        let menuInspection = Self.inspectWindowMenu(appElem: appElem)

        let decision = cyclingEngine.decideActivation(
            pid: pid,
            isFrontmost: isAlreadyFrontmost,
            isHidden: runningApp.isHidden,
            cgWindowCount: cgCount,
            axWindows: axInspection.entries,
            menuEntries: menuInspection.entries,
            focusedWindowTitle: Self.focusedWindowTitle(appElem: appElem)
        )

        self.activeAppBundleId = runningApp.bundleIdentifier

        switch decision {
        case .pressMenuIndex(let menuIndex, let matchingWindowID):
            if menuIndex < menuInspection.elements.count,
               AXUIElementPerformAction(menuInspection.elements[menuIndex], kAXPressAction as CFString) == .success {
                if let wid = matchingWindowID,
                   let matchIdx = axInspection.entries.firstIndex(where: { $0.windowID == wid }) {
                    Self.raiseWindow(axInspection.eligibleElements[matchIdx], appElement: appElem)
                }
                yieldAndActivate(runningApp)
                return
            }
            // Fallback to Strategy 2 (AX window raise) before Strategy 3 (keyboard shortcut)
            if let fallbackWID = cyclingEngine.nextAXWindowIDToRaise(pid: pid, axWindows: axInspection.entries),
               let matchIdx = axInspection.entries.firstIndex(where: { $0.windowID == fallbackWID }) {
                Self.raiseWindow(axInspection.eligibleElements[matchIdx], appElement: appElem)
                yieldAndActivate(runningApp)
                return
            }
            yieldAndActivate(runningApp)
            triggerWindowCycleKeyboardShortcut(for: pid)

        case .raiseWindowID(let targetWID):
            if let matchIdx = axInspection.entries.firstIndex(where: { $0.windowID == targetWID }) {
                Self.raiseWindow(axInspection.eligibleElements[matchIdx], appElement: appElem)
            }
            yieldAndActivate(runningApp)

        case .sendKeyboardShortcut:
            yieldAndActivate(runningApp)
            triggerWindowCycleKeyboardShortcut(for: pid)

        case .activateFirstWindow:
            if runningApp.isHidden {
                runningApp.unhide()
            }
            yieldAndActivate(runningApp, options: [.activateAllWindows])
            if let frontWindow = axInspection.eligibleElements.first ?? axInspection.allWindows.first {
                Self.raiseWindow(frontWindow, appElement: appElem)
            }
            executeAppleScript(bundleIdentifier: bundleIdentifier ?? runningApp.bundleIdentifier, command: "reopen\nactivate")
        }
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
            self.cyclingEngine.removeState(for: app.processIdentifier)
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

        let pid = runningApp.processIdentifier
        let appElem = AXUIElementCreateApplication(pid)
        let axInspection = inspectAXWindows(appElem: appElem, bundleIdentifier: bundleIdentifier)
        let menuInspection = inspectWindowMenu(appElem: appElem)

        return AppWindowCyclingEngine.buildWindowInfos(
            pid: pid,
            axWindows: axInspection.entries,
            menuEntries: menuInspection.entries
        )
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

        let pid = runningApp.processIdentifier
        let appElem = AXUIElementCreateApplication(pid)
        let axInspection = Self.inspectAXWindows(appElem: appElem, bundleIdentifier: bundleIdentifier)
        let menuInspection = Self.inspectWindowMenu(appElem: appElem)

        if runningApp.isHidden {
            runningApp.unhide()
        }

        self.activeAppBundleId = runningApp.bundleIdentifier
        let matchedMenuIdx = self.cyclingEngine.recordSelectedWindow(window, pid: pid, menuEntries: menuInspection.entries)
        yieldAndActivate(runningApp)

        // 1. Strategy 1: If Window menu item matches, perform kAXPressAction to switch Space and select the window
        var menuActionSucceeded = false
        if let itemIdx = matchedMenuIdx, itemIdx < menuInspection.elements.count {
            if AXUIElementPerformAction(menuInspection.elements[itemIdx], kAXPressAction as CFString) == .success {
                menuActionSucceeded = true
            }
        }

        // 2. Strategy 2: If the window is on the current Space, unminimize and raise directly
        var axRaised = false
        if let matchIdx = AppWindowCyclingEngine.resolveAXWindowIndex(for: window, in: axInspection.entries) {
            let matchingAXWindow = axInspection.eligibleElements[matchIdx]
            Self.unminimizeWindow(matchingAXWindow)
            Self.raiseWindow(matchingAXWindow, appElement: appElem)
            axRaised = true
        }

        // 3. Fallback only if neither Window menu nor direct AX window raise succeeded
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
