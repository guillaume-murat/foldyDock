import AppKit

public final class HotspotPanel: NSPanel {
    public var onCursorHitEdge: (() -> Void)?
    public var onCursorLeaveEdge: (() -> Void)?

    public init(screen: NSScreen) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = HotspotView()
        view.onMouseEnter = { [weak self] in
            self?.onCursorHitEdge?()
        }
        view.onMouseLeave = { [weak self] in
            self?.onCursorLeaveEdge?()
        }
        self.contentView = view
        updatePosition(screen: screen)
    }

    public func updatePosition(screen: NSScreen) {
        let screenFrame = screen.frame
        let height: CGFloat = 8.0
        let frame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width,
            height: height
        )
        self.setFrame(frame, display: true)
    }
}

public final class HotspotManager {
    private var panels: [HotspotPanel] = []
    public var onCursorHitEdge: ((NSScreen) -> Void)?
    public var onCursorLeaveEdge: (() -> Void)?

    public init() {
        updateScreens()
    }

    public func updateScreens() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()

        for screen in NSScreen.screens {
            let panel = HotspotPanel(screen: screen)
            panel.onCursorHitEdge = { [weak self] in
                self?.onCursorHitEdge?(screen)
            }
            panel.onCursorLeaveEdge = { [weak self] in
                self?.onCursorLeaveEdge?()
            }
            panels.append(panel)
        }
    }

    public func orderFrontAll() {
        panels.forEach {
            $0.orderFrontRegardless()
            ($0.contentView as? HotspotView)?.refreshTracking()
        }
    }

    public func orderOutAll() {
        panels.forEach { $0.orderOut(nil) }
    }

    public func handleSpaceChange() {
        for panel in panels {
            panel.orderFrontRegardless()
            (panel.contentView as? HotspotView)?.refreshTracking()
        }
    }
}

private final class HotspotView: NSView {
    var onMouseEnter: (() -> Void)?
    var onMouseLeave: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        // Subtle almost-zero alpha fill guarantees hit-testing works without visible pixels
        NSColor(white: 0.0, alpha: 0.001).setFill()
        dirtyRect.fill()
    }

    public func refreshTracking() {
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
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
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseLeave?()
    }
}
