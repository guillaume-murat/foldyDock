import AppKit
import SwiftUI

public final class DockPanel: NSPanel {
    private var trackingArea: NSTrackingArea?
    private var hideTimer: Timer?
    private var inactivityTimer: Timer?
    public var autohideEnabled: Bool = true
    public var autohideDelay: TimeInterval = 0.3
    public var showDelay: TimeInterval = 0.0

    private var showTimer: Timer?
    private var pendingShowScreen: NSScreen?

    private(set) public var isHiddenState: Bool = false
    private var shownY: CGFloat = 18
    public let hotspotManager: HotspotManager
    public var onMiddleClickEvent: ((NSEvent) -> Void)?
    private var globalMouseMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var edgePollingTimer: Timer?

    public var currentScreen: NSScreen {
        didSet {
            // Keep shownY updated for current screen
            self.shownY = currentScreen.frame.origin.y + 18
        }
    }

    public var dockHeight: CGFloat = 92.0

    public init(contentView: NSView, initialDockHeight: CGFloat = 92.0) {
        self.dockHeight = initialDockHeight
        let initialScreen = NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
        self.currentScreen = initialScreen
        self.shownY = initialScreen.frame.origin.y + 18
        self.hotspotManager = HotspotManager()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: initialDockHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let trackingContainer = DockTrackingView(dockPanel: self)
        trackingContainer.wantsLayer = true
        trackingContainer.layer?.backgroundColor = .clear
        trackingContainer.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: trackingContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trackingContainer.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: trackingContainer.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: trackingContainer.bottomAnchor)
        ])

        self.contentView = trackingContainer

        hotspotManager.onCursorHitEdge = { [weak self] screen in
            guard let self = self else { return }
            self.requestShowDock(on: screen)
        }
        hotspotManager.onCursorLeaveEdge = { [weak self] in
            guard let self = self else { return }
            self.cancelPendingShow()
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if self.isHiddenState {
                    self.hotspotManager.handleSpaceChange()
                } else {
                    self.orderFrontRegardless()
                }
            }
        }

        reposition()
        startEdgeMonitoring()
    }

    deinit {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        stopEdgeMonitoring()
    }

    override public var canBecomeKey: Bool {
        return true
    }

    override public var canBecomeMain: Bool {
        return false
    }

    public func updateScreens() {
        hotspotManager.updateScreens()
        // If currentScreen is no longer valid, fallback to first available screen
        if !NSScreen.screens.contains(where: { $0.frame == currentScreen.frame }) {
            if let first = NSScreen.screens.first {
                self.currentScreen = first
            }
        }
        reposition()
    }

    public func reposition() {
        cancelPendingShow()
        let screen = currentScreen
        let screenFrame = screen.frame

        let width = self.frame.width > 0 ? self.frame.width : 500
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        self.shownY = screenFrame.origin.y + 18

        if isHiddenState {
            let hideTargetY = screenFrame.origin.y
            self.setFrame(NSRect(x: x, y: hideTargetY, width: width, height: dockHeight), display: true)
            self.alphaValue = 0.0
            self.ignoresMouseEvents = true
            self.orderOut(nil)
            hotspotManager.orderFrontAll()
        } else {
            self.setFrame(NSRect(x: x, y: shownY, width: width, height: dockHeight), display: true)
            self.alphaValue = 1.0
            self.ignoresMouseEvents = false
            self.orderFrontRegardless()
            hotspotManager.orderOutAll()
            if autohideEnabled {
                scheduleInactivityTimer()
            }
        }
    }

    public func updateDockWidth(_ width: CGFloat) {
        updateDockSize(width: width, height: self.dockHeight)
    }

    public func updateDockSize(width: CGFloat, height: CGFloat) {
        let screen = currentScreen
        let screenFrame = screen.frame
        if height > 0 {
            self.dockHeight = height
        }
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        self.shownY = screenFrame.origin.y + 18

        if isHiddenState {
            let hideTargetY = screenFrame.origin.y
            self.setFrame(NSRect(x: x, y: hideTargetY, width: width, height: dockHeight), display: true, animate: false)
        } else {
            if abs(self.frame.width - width) > 0.5 || abs(self.frame.height - dockHeight) > 0.5 || abs(self.frame.origin.x - x) > 0.5 || abs(self.frame.origin.y - shownY) > 0.5 {
                self.setFrame(NSRect(x: x, y: shownY, width: width, height: dockHeight), display: true, animate: false)
            }
        }
    }

    public func requestShowDock(on screen: NSScreen? = nil) {
        hideTimer?.invalidate()
        hideTimer = nil

        guard isHiddenState else { return }

        if showDelay <= 0.01 {
            showDock(on: screen, animated: true)
            return
        }

        if showTimer != nil {
            if let screen = screen {
                self.pendingShowScreen = screen
            }
            return
        }

        self.pendingShowScreen = screen
        showTimer = Timer.scheduledTimer(withTimeInterval: showDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isHiddenState else { return }
                let target = self.pendingShowScreen ?? self.currentScreen
                self.showDock(on: target, animated: true)
            }
        }
    }

    public func cancelPendingShow() {
        showTimer?.invalidate()
        showTimer = nil
        pendingShowScreen = nil
    }

    // MARK: - Mouse & Zone Detection

    /// Returns true if the cursor is within the dock or in the gap directly underneath it
    public func isMouseInDockZone(at loc: NSPoint) -> Bool {
        if self.frame.contains(loc) {
            return true
        }

        if !isHiddenState && self.isVisible {
            let screenFrame = currentScreen.frame
            let inBottomGapY = (loc.y >= screenFrame.origin.y && loc.y <= self.frame.minY)
            let inDockXRange = (loc.x >= (self.frame.minX - 16) && loc.x <= (self.frame.maxX + 16))
            if inBottomGapY && inDockXRange {
                return true
            }
        }

        return false
    }

    public func mouseDidEnter() {
        guard !ignoresMouseEvents else { return }
        hideTimer?.invalidate()
        hideTimer = nil
        inactivityTimer?.invalidate()
        inactivityTimer = nil

        if isHiddenState {
            requestShowDock(on: currentScreen)
        }
    }

    public var shouldPreventAutoHide: (() -> Bool)?

    public func mouseDidExit() {
        guard !ignoresMouseEvents else { return }
        cancelPendingShow()
        guard autohideEnabled else { return }
        if shouldPreventAutoHide?() == true {
            return
        }
        let mouseLoc = NSEvent.mouseLocation
        if isMouseInDockZone(at: mouseLoc) {
            return
        }
        scheduleHideTimer()
    }

    public func scheduleHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: autohideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.shouldPreventAutoHide?() != true else { return }
                let currentLoc = NSEvent.mouseLocation
                if self.isMouseInDockZone(at: currentLoc) {
                    return
                }
                self.hideDock(animated: true)
            }
        }
    }

    private func scheduleInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isHiddenState else { return }
                if self.shouldPreventAutoHide?() != true {
                    let mouseLoc = NSEvent.mouseLocation
                    if !self.isMouseInDockZone(at: mouseLoc) {
                        self.hideDock(animated: true)
                    }
                }
            }
        }
    }

    public func showDock(on screen: NSScreen? = nil, animated: Bool = true) {
        cancelPendingShow()
        hideTimer?.invalidate()
        hideTimer = nil
        inactivityTimer?.invalidate()
        inactivityTimer = nil

        let targetScreen = screen ?? self.currentScreen
        let isSwitchingScreen = (targetScreen != self.currentScreen)
        self.currentScreen = targetScreen
        self.isHiddenState = false
        self.ignoresMouseEvents = false
        hotspotManager.orderOutAll()

        let screenFrame = targetScreen.frame
        self.shownY = screenFrame.origin.y + 18

        let width = self.frame.width > 0 ? self.frame.width : 500
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let targetFrame = NSRect(
            x: x,
            y: shownY,
            width: width,
            height: dockHeight
        )

        scheduleInactivityTimer()

        if animated {
            // Position at bottom edge with opacity 0 before gliding up if hidden or switching screens
            if isSwitchingScreen || self.alphaValue < 0.05 || !self.isVisible {
                let startFrame = NSRect(
                    x: x,
                    y: screenFrame.origin.y,
                    width: width,
                    height: dockHeight
                )
                self.setFrame(startFrame, display: false)
                self.alphaValue = 0.0
                self.orderFrontRegardless()
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(targetFrame, display: true)
                self.animator().alphaValue = 1.0
            }
        } else {
            self.setFrame(targetFrame, display: true)
            self.alphaValue = 1.0
            self.orderFrontRegardless()
        }
    }

    public func hideDock(animated: Bool = true) {
        cancelPendingShow()
        hideTimer?.invalidate()
        hideTimer = nil
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        isHiddenState = true
        self.ignoresMouseEvents = true

        let screen = currentScreen
        let screenFrame = screen.frame
        let width = self.frame.width > 0 ? self.frame.width : 500
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2

        // Slide towards the bottom edge of the current screen
        let hideTargetY = screenFrame.origin.y
        let targetFrame = NSRect(
            x: x,
            y: hideTargetY,
            width: width,
            height: dockHeight
        )

        hotspotManager.orderFrontAll()

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().setFrame(targetFrame, display: true)
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                guard let self = self, self.isHiddenState else { return }
                self.alphaValue = 0.0
                self.orderOut(nil)
            })
        } else {
            self.setFrame(targetFrame, display: true)
            self.alphaValue = 0.0
            self.orderOut(nil)
        }
    }

    // MARK: - Multi-Monitor Bottom-Edge Detection

    public func screenForBottomEdge(at loc: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            let f = screen.frame
            // Check if cursor is within 8pt of the bottom edge of this screen
            let isAtBottom = loc.y >= (f.origin.y - 1.0) && loc.y <= (f.origin.y + 8.0)
                && loc.x >= (f.origin.x - 1.0) && loc.x <= (f.origin.x + f.width + 1.0)
            if isAtBottom {
                return screen
            }
        }
        return nil
    }

    public func startEdgeMonitoring() {
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.handleCursorMovement()
                }
            }
        }

        if edgePollingTimer == nil {
            edgePollingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.isHiddenState {
                        self.handleCursorMovement()
                    }
                }
            }
        }
    }

    public func stopEdgeMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        edgePollingTimer?.invalidate()
        edgePollingTimer = nil
    }

    private func handleCursorMovement() {
        let loc = NSEvent.mouseLocation

        if self.isHiddenState {
            if let targetScreen = self.screenForBottomEdge(at: loc) {
                self.requestShowDock(on: targetScreen)
            } else {
                self.cancelPendingShow()
            }
        } else {
            if self.isMouseInDockZone(at: loc) {
                if self.hideTimer != nil {
                    self.hideTimer?.invalidate()
                    self.hideTimer = nil
                }
            } else {
                if self.autohideEnabled && self.hideTimer == nil && self.shouldPreventAutoHide?() != true {
                    self.scheduleHideTimer()
                }
            }
        }
    }
}

private final class DockTrackingView: NSView {
    private weak var dockPanel: DockPanel?
    private var trackingArea: NSTrackingArea?

    init(dockPanel: DockPanel) {
        self.dockPanel = dockPanel
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        dockPanel?.mouseDidEnter()
    }

    override func mouseExited(with event: NSEvent) {
        dockPanel?.mouseDidExit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
