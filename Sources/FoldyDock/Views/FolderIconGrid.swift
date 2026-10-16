import SwiftUI
import AppKit

public struct FolderIconGrid: View {
    public let item: DockItem
    public let size: CGFloat
    public var isHighlighted: Bool
    public var showBackground: Bool
    public var bouncingSubItemIds: Set<UUID>
    public var runningSubItemIds: Set<UUID>
    public var subItemWindowCounts: [UUID: Int]
    public var hiddenSubItemIds: Set<UUID>
    public var hiddenAppOpacity: Double
    public var theme: DockTheme

    public init(
        item: DockItem,
        size: CGFloat = 52.0,
        isHighlighted: Bool = false,
        showBackground: Bool = true,
        bouncingSubItemIds: Set<UUID> = [],
        runningSubItemIds: Set<UUID> = [],
        subItemWindowCounts: [UUID: Int] = [:],
        hiddenSubItemIds: Set<UUID> = [],
        hiddenAppOpacity: Double = 0.5,
        theme: DockTheme = DockTheme(isDark: true)
    ) {
        self.item = item
        self.size = size
        self.isHighlighted = isHighlighted
        self.showBackground = showBackground
        self.bouncingSubItemIds = bouncingSubItemIds
        self.runningSubItemIds = runningSubItemIds
        self.subItemWindowCounts = subItemWindowCounts
        self.hiddenSubItemIds = hiddenSubItemIds
        self.hiddenAppOpacity = hiddenAppOpacity
        self.theme = theme
    }

    private var subItems: [DockItem] {
        item.subItems ?? []
    }

    public var body: some View {
        ZStack {
            if showBackground {
                // iOS-style squircle background with highlight state
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    isHighlighted
                        ? LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.52, blue: 1.0).opacity(0.85),
                                Color(red: 0.08, green: 0.36, blue: 0.92).opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                theme.folderSurfaceTop,
                                theme.folderSurfaceBottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
                .overlay(
                    Group {
                        if isHighlighted {
                            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                                .fill(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.38), Color.clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: size * 0.55
                                    )
                                )
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(
                            isHighlighted
                                ? LinearGradient(
                                    colors: [Color.white, Color.cyan.opacity(0.95), Color.white.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [theme.folderStrokeTop, theme.folderStrokeBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: isHighlighted ? 2.5 : 1.0
                        )
                )
                .shadow(
                    color: isHighlighted ? Color.blue.opacity(0.95) : Color.black.opacity(theme.isDark ? 0.2 : 0.10),
                    radius: isHighlighted ? 12 : 3,
                    x: 0,
                    y: isHighlighted ? 0 : 1.5
                )
                .shadow(
                    color: isHighlighted ? Color.cyan.opacity(0.8) : Color.clear,
                    radius: isHighlighted ? 6 : 0,
                    x: 0,
                    y: 0
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHighlighted)
            }

            // Content: dynamic scalable mini icons
            if subItems.isEmpty {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.emptyFolderIconTop, theme.emptyFolderIconBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                let layout = DynamicGridLayout(itemCount: subItems.count, containerSize: size)
                VStack(alignment: .leading, spacing: layout.verticalSpacing) {
                    ForEach(0..<layout.rows, id: \.self) { row in
                        HStack(alignment: .top, spacing: layout.horizontalSpacing) {
                            ForEach(0..<layout.cols, id: \.self) { col in
                                let index = row * layout.cols + col
                                miniIconView(at: index, layout: layout)
                            }
                        }
                    }
                }
                .padding(layout.outerPadding)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func miniIconView(at index: Int, layout: DynamicGridLayout) -> some View {
        let cellHeight = layout.iconSize + layout.dotSpacing + layout.dotSize

        if index < subItems.count {
            let sub = subItems[index]
            let isBouncing = bouncingSubItemIds.contains(sub.id)
            let isRunning = runningSubItemIds.contains(sub.id)
            let isHidden = hiddenSubItemIds.contains(sub.id)
            let wCount = subItemWindowCounts[sub.id] ?? (isRunning ? 1 : 0)

            VStack(spacing: layout.dotSpacing) {
                Image(nsImage: IconProvider.shared.icon(for: sub, size: layout.iconSize))
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.iconSize, height: layout.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                    .opacity(isHidden ? hiddenAppOpacity : 1.0)
                    .dockBounce(isBouncing: isBouncing, height: layout.bounceHeight)

                // Multi-pastilles sous la mini app ouverte
                ZStack(alignment: .center) {
                    if isRunning {
                        MultiWindowIndicatorView(
                            windowCount: wCount,
                            dotSize: layout.dotSize,
                            spacing: max(0.6, layout.dotSpacing * 0.8),
                            color: theme.indicatorDotColor,
                            shadowColor: theme.indicatorDotShadowColor
                        )
                    }
                }
                .frame(width: layout.iconSize, height: layout.dotSize)
            }
            .frame(width: layout.iconSize, height: cellHeight, alignment: .top)
        } else {
            Color.clear
                .frame(width: layout.iconSize, height: cellHeight)
        }
    }
}

// MARK: - Dynamic Grid Layout Calculation

private struct DynamicGridLayout {
    let cols: Int
    let rows: Int
    let iconSize: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let dotSize: CGFloat
    let dotSpacing: CGFloat
    let bounceHeight: CGFloat
    let cornerRadius: CGFloat
    let outerPadding: CGFloat

    init(itemCount: Int, containerSize: CGFloat) {
        let c: Int
        if itemCount <= 1 {
            c = 1
        } else if itemCount <= 4 {
            c = 2
        } else if itemCount <= 9 {
            c = 3
        } else if itemCount <= 16 {
            c = 4
        } else if itemCount <= 25 {
            c = 5
        } else {
            c = Int(ceil(sqrt(Double(itemCount))))
        }
        let r = max(1, Int(ceil(Double(itemCount) / Double(c))))
        self.cols = c
        self.rows = r

        let scale = containerSize / 52.0

        switch c {
        case 1:
            self.iconSize = 26.0 * scale
            self.horizontalSpacing = 0
            self.verticalSpacing = 0
            self.dotSize = 3.2 * scale
            self.dotSpacing = 1.6 * scale
            self.bounceHeight = 4.0 * scale
            self.cornerRadius = 26.0 * 0.22 * scale
            self.outerPadding = 0
        case 2:
            if r == 1 {
                // Exactement 2 applications : 1 ligne de 2 icônes centrée verticalement et horizontalement
                self.iconSize = 18.5 * scale
                self.horizontalSpacing = 3.5 * scale
                self.verticalSpacing = 0
                self.dotSize = 2.6 * scale
                self.dotSpacing = 1.2 * scale
                self.bounceHeight = 3.5 * scale
                self.cornerRadius = 18.5 * 0.22 * scale
                self.outerPadding = 0
            } else {
                // 3 ou 4 applications (2 colonnes x 2 lignes)
                self.iconSize = 17.5 * scale
                self.horizontalSpacing = 3.0 * scale
                self.verticalSpacing = 1.5 * scale
                self.dotSize = 2.6 * scale
                self.dotSpacing = 1.2 * scale
                self.bounceHeight = 3.5 * scale
                self.cornerRadius = 17.5 * 0.22 * scale
                self.outerPadding = 3.5 * scale
            }
        case 3:
            if r == 2 {
                // Grille à 6 applications (3 colonnes x 2 lignes) : padding réduit et applications plus grandes
                self.iconSize = 13.5 * scale
                self.horizontalSpacing = 2.0 * scale
                self.verticalSpacing = 2.2 * scale
                self.dotSize = 2.2 * scale
                self.dotSpacing = 0.9 * scale
                self.bounceHeight = 2.6 * scale
                self.cornerRadius = 13.5 * 0.22 * scale
                self.outerPadding = 2.2 * scale
            } else {
                // Grille à 7..9 applications (3 colonnes x 3 lignes)
                self.iconSize = 11.2 * scale
                self.horizontalSpacing = 2.0 * scale
                self.verticalSpacing = 1.0 * scale
                self.dotSize = 1.9 * scale
                self.dotSpacing = 0.8 * scale
                self.bounceHeight = 2.2 * scale
                self.cornerRadius = 11.2 * 0.22 * scale
                self.outerPadding = 2.0 * scale
            }
        case 4:
            self.iconSize = 8.2 * scale
            self.horizontalSpacing = 1.5 * scale
            self.verticalSpacing = 1.1 * scale
            self.dotSize = 1.6 * scale
            self.dotSpacing = 0.6 * scale
            self.bounceHeight = 1.8 * scale
            self.cornerRadius = 8.2 * 0.22 * scale
            self.outerPadding = 3.0 * scale
        case 5:
            self.iconSize = 6.4 * scale
            self.horizontalSpacing = 1.2 * scale
            self.verticalSpacing = 0.9 * scale
            self.dotSize = 1.3 * scale
            self.dotSpacing = 0.5 * scale
            self.bounceHeight = 1.4 * scale
            self.cornerRadius = 6.4 * 0.22 * scale
            self.outerPadding = 2.5 * scale
        default:
            let hSpacing = max(0.8, 1.2 - CGFloat(c - 5) * 0.08) * scale
            let totalHSpacing = CGFloat(c - 1) * hSpacing
            let availW = containerSize - 12.0 * scale
            let w = max(3.0 * scale, (availW - totalHSpacing) / CGFloat(c))
            self.iconSize = w
            self.horizontalSpacing = hSpacing
            self.verticalSpacing = max(0.6 * scale, hSpacing * 0.8)
            self.dotSize = max(0.9 * scale, w * 0.18)
            self.dotSpacing = max(0.3 * scale, w * 0.08)
            self.bounceHeight = max(1.0 * scale, w * 0.2)
            self.cornerRadius = max(0.6 * scale, w * 0.22)
            self.outerPadding = 2.0 * scale
        }
    }
}
