import SwiftUI
import AppKit

public struct VisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var cornerRadius: CGFloat
    public var isDark: Bool?

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        cornerRadius: CGFloat = 24.0,
        isDark: Bool? = nil
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.cornerRadius = cornerRadius
        self.isDark = isDark
    }

    public func makeNSView(context: Context) -> MaskedVisualEffectView {
        let view = MaskedVisualEffectView(cornerRadius: cornerRadius)
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        if let isDark {
            view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
        return view
    }

    public func updateNSView(_ nsView: MaskedVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.cornerRadius = cornerRadius
        if let isDark {
            nsView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        } else {
            nsView.appearance = nil
        }
    }
}

public final class MaskedVisualEffectView: NSVisualEffectView {
    public var cornerRadius: CGFloat {
        didSet {
            if oldValue != cornerRadius {
                layer?.cornerRadius = cornerRadius
                updateMask()
            }
        }
    }

    public init(cornerRadius: CGFloat = 24.0) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        setupLayer()
    }

    override public init(frame frameRect: NSRect) {
        self.cornerRadius = 24.0
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        self.cornerRadius = 24.0
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }

    override public func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let currentSize = bounds.size
        let radius = cornerRadius

        // Generate a 1:1 pixel mask image matching the exact view bounds
        let mask = NSImage(size: currentSize, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        self.maskImage = mask
    }
}
