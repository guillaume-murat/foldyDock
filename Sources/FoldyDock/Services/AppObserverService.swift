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

    private let windowInventory = AppWindowInventory(source: SystemAppWindowSource())
    private var inventoryRefreshTask: Task<Void, Never>?
    private var inventoryRefreshPending = false
    private var allMinimizedBundleIds: Set<String> = []
    #if DEBUG
    private var windowStateOverriddenForTesting = false
    #endif

    public init() {
        refreshRunningApps()
        setupNotificationObservers()
        startPeriodicSync()
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

    /// Refresh the list of currently running regular applications and their window state
    public func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningBundleIds = Set(apps.compactMap(\.bundleIdentifier))
        if let frontBid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontBid != Bundle.main.bundleIdentifier {
            self.activeAppBundleId = frontBid
        }
        self.refreshWindowCounts()
    }

    /// Refreshes window dots and hidden state from the App Window Inventory (off the main thread, coalesced).
    public func refreshWindowCounts() {
        publishHiddenApps()
        guard inventoryRefreshTask == nil else {
            inventoryRefreshPending = true
            return
        }
        let apps = Self.regularRunningApps()
        let inventory = windowInventory
        inventoryRefreshTask = Task { [weak self] in
            let summary = await inventory.refresh(apps: apps)
            guard let self = self else { return }
            self.apply(summary)
            self.inventoryRefreshTask = nil
            if self.inventoryRefreshPending {
                self.inventoryRefreshPending = false
                self.refreshWindowCounts()
            }
        }
    }

    /// Hidden = hidden with ⌘H, or every User Window minimized (yellow button).
    public func refreshHiddenApps() {
        refreshWindowCounts()
    }

    private func apply(_ summary: AppWindowSummary) {
        #if DEBUG
        if windowStateOverriddenForTesting { return }
        #endif
        allMinimizedBundleIds = summary.allMinimizedBundleIds
        if self.windowCountsByBundleId != summary.windowCounts {
            self.windowCountsByBundleId = summary.windowCounts
        }
        publishHiddenApps()
    }

    private func publishHiddenApps() {
        #if DEBUG
        if windowStateOverriddenForTesting { return }
        #endif
        let hiddenWithCommandH = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.isHidden }
            .compactMap(\.bundleIdentifier)
        let hidden = Set(hiddenWithCommandH).union(allMinimizedBundleIds.intersection(runningBundleIds))
        if self.hiddenAppBundleIds != hidden {
            self.hiddenAppBundleIds = hidden
        }
    }

    nonisolated private static func regularRunningApps() -> [RunningAppRef] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bid = app.bundleIdentifier else { return nil }
            return RunningAppRef(pid: app.processIdentifier, bundleIdentifier: bid)
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
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowCounts()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didHideApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowCounts()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowCounts()
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
        let dockWindowCount = windowCountsByBundleId[bid] ?? 0
        if dockWindowCount > 1 && !AccessibilityPermissionService.shared.isTrusted {
            requestAccessibilityPermissionIfNeeded()
        }

        let appElem = AXUIElementCreateApplication(pid)
        let snapshot = windowInventory.snapshot(for: RunningAppRef(pid: pid, bundleIdentifier: bid))
        let decision = cyclingEngine.decideActivation(
            pid: pid,
            isFrontmost: isAlreadyFrontmost,
            isHidden: runningApp.isHidden,
            snapshot: snapshot,
            fallbackWindowCount: dockWindowCount
        )

        self.activeAppBundleId = runningApp.bundleIdentifier

        let raise = { (windowID: CGWindowID) in
            if let element = SystemAppWindowSource.axWindowElement(pid: pid, windowID: windowID) {
                Self.raiseWindow(element, appElement: appElem)
            }
        }

        switch decision {
        case .pressMenuIndex(let menuIndex, let matchingWindowID):
            let menuItems = SystemAppWindowSource.windowMenuItemElements(pid: pid)
            if menuIndex < menuItems.count,
               AXUIElementPerformAction(menuItems[menuIndex], kAXPressAction as CFString) == .success {
                if let wid = matchingWindowID {
                    raise(wid)
                }
                yieldAndActivate(runningApp)
                return
            }
            // Fallback to Strategy 2 (AX window raise) before Strategy 3 (keyboard shortcut)
            if let fallbackWID = cyclingEngine.nextAXWindowIDToRaise(pid: pid, axWindows: snapshot.axWindows) {
                raise(fallbackWID)
                yieldAndActivate(runningApp)
                return
            }
            yieldAndActivate(runningApp)
            triggerWindowCycleKeyboardShortcut(for: pid)

        case .raiseWindowID(let targetWID):
            raise(targetWID)
            yieldAndActivate(runningApp)

        case .sendKeyboardShortcut:
            yieldAndActivate(runningApp)
            triggerWindowCycleKeyboardShortcut(for: pid)

        case .activateFirstWindow:
            if runningApp.isHidden {
                runningApp.unhide()
            }
            yieldAndActivate(runningApp, options: [.activateAllWindows])
            let frontWindow = snapshot.axWindows.first
                .flatMap { SystemAppWindowSource.axWindowElement(pid: pid, windowID: $0.windowID) }
                ?? SystemAppWindowSource.axWindowElements(pid: pid).first
            if let frontWindow = frontWindow {
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

    /// Fresh App Window Inventory of a running application (empty if not running).
    nonisolated private func openWindows(for bundleIdentifier: String) -> [AppWindowInfo] {
        guard let app = Self.runningApp(bundleIdentifier: bundleIdentifier) else { return [] }
        return windowInventory.snapshot(for: RunningAppRef(pid: app.processIdentifier, bundleIdentifier: bundleIdentifier)).windows
    }

    nonisolated private static func runningApp(bundleIdentifier: String) -> NSRunningApplication? {
        let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return matchingApps.first(where: { $0.activationPolicy == .regular }) ?? matchingApps.first
    }

    /// Asynchronously fetches the User Windows of an application off the main thread to avoid UI hitches.
    public func fetchOpenWindowsAsync(for bundleIdentifier: String) async -> [AppWindowInfo] {
        await Task.detached(priority: .userInitiated) { [self] in
            self.openWindows(for: bundleIdentifier)
        }.value
    }

    /// Selects and brings a specific window to the foreground.
    /// Handles unminimization, Mission Control virtual Space switching, and cooperative application activation.
    public func selectWindow(_ window: AppWindowInfo, for bundleIdentifier: String) {
        guard let runningApp = Self.runningApp(bundleIdentifier: bundleIdentifier) else { return }

        let pid = runningApp.processIdentifier
        let appElem = AXUIElementCreateApplication(pid)
        let snapshot = windowInventory.snapshot(for: RunningAppRef(pid: pid, bundleIdentifier: bundleIdentifier))

        if runningApp.isHidden {
            runningApp.unhide()
        }

        self.activeAppBundleId = runningApp.bundleIdentifier
        let matchedMenuIdx = self.cyclingEngine.recordSelectedWindow(window, pid: pid, menuEntries: snapshot.menuEntries)
        yieldAndActivate(runningApp)

        // 1. Strategy 1: If Window menu item matches, perform kAXPressAction to switch Space and select the window
        var menuActionSucceeded = false
        if let itemIdx = matchedMenuIdx {
            let menuItems = SystemAppWindowSource.windowMenuItemElements(pid: pid)
            if itemIdx < menuItems.count,
               AXUIElementPerformAction(menuItems[itemIdx], kAXPressAction as CFString) == .success {
                menuActionSucceeded = true
            }
        }

        // 2. Strategy 2: If the window is on the current Space, unminimize and raise directly
        var axRaised = false
        if let matchIdx = AppWindowCyclingEngine.resolveAXWindowIndex(for: window, in: snapshot.axWindows),
           let element = SystemAppWindowSource.axWindowElement(pid: pid, windowID: snapshot.axWindows[matchIdx].windowID) {
            Self.unminimizeWindow(element)
            Self.raiseWindow(element, appElement: appElem)
            axRaised = true
        }

        // 3. Fallback only if neither Window menu nor direct AX window raise succeeded
        if !menuActionSucceeded && !axRaised {
            executeAppleScript(bundleIdentifier: bundleIdentifier, command: "reopen\nactivate")
        }
    }

    #if DEBUG
    public func setWindowCountsForTesting(_ counts: [String: Int]) {
        windowStateOverriddenForTesting = true
        self.windowCountsByBundleId = counts
    }

    public func setRunningBundleIdsForTesting(_ bids: Set<String>) {
        self.runningBundleIds = bids
    }

    public func setHiddenAppBundleIdsForTesting(_ bids: Set<String>) {
        windowStateOverriddenForTesting = true
        self.hiddenAppBundleIds = bids
    }
    #endif
}
