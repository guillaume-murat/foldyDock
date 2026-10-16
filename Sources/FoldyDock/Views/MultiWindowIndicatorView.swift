import SwiftUI

public struct MiniPlusShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let thickness = max(0.7, size * 0.30)
        let corner = thickness * 0.35

        // Horizontal bar
        let hRect = CGRect(
            x: rect.midX - size / 2,
            y: rect.midY - thickness / 2,
            width: size,
            height: thickness
        )
        path.addRoundedRect(in: hRect, cornerSize: CGSize(width: corner, height: corner))

        // Vertical bar
        let vRect = CGRect(
            x: rect.midX - thickness / 2,
            y: rect.midY - size / 2,
            width: thickness,
            height: size
        )
        path.addRoundedRect(in: vRect, cornerSize: CGSize(width: corner, height: corner))

        return path
    }
}

public struct MultiWindowIndicatorView: View {
    public let windowCount: Int
    public let dotSize: CGFloat
    public let spacing: CGFloat
    public let color: Color
    public let shadowColor: Color

    public init(
        windowCount: Int,
        dotSize: CGFloat = 4.0,
        spacing: CGFloat = 3.0,
        color: Color = Color.white.opacity(0.95),
        shadowColor: Color = Color.white.opacity(0.8)
    ) {
        self.windowCount = windowCount
        self.dotSize = dotSize
        self.spacing = spacing
        self.color = color
        self.shadowColor = shadowColor
    }

    public var body: some View {
        HStack(spacing: spacing) {
            if windowCount >= 4 {
                // Au-delà de 3 fenêtres : 2 pastilles côte à côte et une petite icône +
                Circle()
                    .fill(color)
                    .frame(width: dotSize * 0.88, height: dotSize * 0.88)
                    .shadow(color: shadowColor, radius: dotSize * 0.4)

                Circle()
                    .fill(color)
                    .frame(width: dotSize * 0.88, height: dotSize * 0.88)
                    .shadow(color: shadowColor, radius: dotSize * 0.4)

                MiniPlusShape()
                    .fill(color)
                    .frame(width: dotSize * 0.88, height: dotSize * 0.88)
                    .shadow(color: shadowColor, radius: dotSize * 0.4)
            } else if windowCount == 3 {
                // 3 fenêtres : 3 pastilles côte à côte
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(color)
                        .frame(width: dotSize * 0.88, height: dotSize * 0.88)
                        .shadow(color: shadowColor, radius: dotSize * 0.4)
                }
            } else if windowCount == 2 {
                // 2 fenêtres : 2 pastilles côte à côte
                ForEach(0..<2, id: \.self) { _ in
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: shadowColor, radius: dotSize * 0.5)
                }
            } else {
                // 1 fenêtre (ou sans fenêtre ouverte) : 1 pastille
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: shadowColor, radius: dotSize * 0.5)
            }
        }
        .frame(height: dotSize, alignment: .center)
    }
}
