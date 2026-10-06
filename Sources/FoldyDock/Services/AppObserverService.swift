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

    /// Brings an already-open application to focus, unhiding, unminimizing, and switching Spaces if necessary.
    public func activateRunningApp(_ runningApp: NSRunningApplication, bundleIdentifier: String?, item: DockItem? = nil) {
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

        // 3. Unminimize and raise windows via Accessibility API to trigger Space switch
        let appElem = AXUIElementCreateApplication(runningApp.processIdentifier)
        var winListRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winListRef) == .success,
           let wins = winListRef as? [AXUIElement], !wins.isEmpty {
            for w in wins.reversed() {
                var minVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minVal) == .success,
                   let isMin = minVal as? Bool, isMin {
                    AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
            if let frontWindow = wins.first {
                AXUIElementPerformAction(frontWindow, kAXRaiseAction as CFString)
            }
        }

        // 4. Send AppleScript reopen & activate to ensure macOS Mission Control switches to the Space of the open window
        let targetBid = (bundleIdentifier ?? runningApp.bundleIdentifier)?
            .replacingOccurrences(of: "\"", with: "")
        if let safeBid = targetBid, !safeBid.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                tell application id "\(safeBid)"
                    reopen
                    activate
                end tell
                """
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
            }
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
