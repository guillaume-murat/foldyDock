import SwiftUI
import AppKit

public struct ExpandedFolderBubbleView: View {
    @ObservedObject var viewModel: DockViewModel
    public let folder: DockItem
    public let runningSubItems: [DockItem]
    public let iconSize: CGFloat
    public let dockHeight: CGFloat
    public let folderFontSize: CGFloat
    public let isMergeTarget: Bool
    public let dropPlacement: DropPlacement?
    public let onFolderTap: () -> Void
    public let contextMenuItems: AnyView

    public init(
        viewModel: DockViewModel,
        folder: DockItem,
        runningSubItems: [DockItem],
        iconSize: CGFloat = 52.0,
        dockHeight: CGFloat,
        folderFontSize: CGFloat,
        isMergeTarget: Bool = false,
        dropPlacement: DropPlacement? = nil,
        onFolderTap: @escaping () -> Void,
        contextMenuItems: AnyView
    ) {
        self.viewModel = viewModel
        self.folder = folder
        self.runningSubItems = runningSubItems
        self.iconSize = iconSize
        self.dockHeight = dockHeight
        self.folderFontSize = folderFontSize
        self.isMergeTarget = isMergeTarget
        self.dropPlacement = dropPlacement
        self.onFolderTap = onFolderTap
        self.contextMenuItems = contextMenuItems
    }

    private var bubbleHeight: CGFloat {
        iconSize
    }

    private var bubbleCornerRadius: CGFloat {
        iconSize * 0.22
    }

    private var folderSize: CGFloat {
        iconSize
    }

    private var subAppIconSize: CGFloat {
        iconSize * 0.50
    }

    private var subAppSlotWidth: CGFloat {
        max(39.0, iconSize * 0.74)
    }

    private var subAppSpacing: CGFloat {
        3.5
    }

    private var dividerSpacing: CGFloat {
        5.5
    }

    private var capsuleHorizontalPadding: CGFloat {
        5.5
    }

    private var activeCount: Int {
        let terminatingCount = runningSubItems.filter { viewModel.terminatingItemIds.contains($0.id) }.count
        return max(0, runningSubItems.count - terminatingCount)
    }

    public static func capsuleWidth(iconSize: CGFloat, activeCount: Int) -> CGFloat {
        let folderSize = iconSize
        let subAppSlotWidth = max(39.0, iconSize * 0.74)
        let subAppSpacing: CGFloat = 3.5
        let dividerSpacing: CGFloat = 5.5
        let capsuleHorizontalPadding: CGFloat = 5.5
        if activeCount <= 0 {
            return folderSize + capsuleHorizontalPadding * 2
        }
        let totalRunningWidth = CGFloat(activeCount) * subAppSlotWidth + CGFloat(max(0, activeCount - 1)) * subAppSpacing
        let dividerAndPadding: CGFloat = dividerSpacing + 1.2 + dividerSpacing + capsuleHorizontalPadding * 2
        return folderSize + dividerAndPadding + totalRunningWidth
    }

    private var capsuleWidth: CGFloat {
        Self.capsuleWidth(iconSize: iconSize, activeCount: activeCount)
    }

    @State private var isCapsuleHovered: Bool = false
    @State private var isFolderHovered: Bool = false

    public var body: some View {
        ZStack(alignment: .center) {
            // Insertion bar indicator on the left
            if dropPlacement == .before {
                HStack {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3.5, height: iconSize * 0.85)
                        .shadow(color: Color.blue.opacity(0.85), radius: 5)
                        .shadow(color: Color.white.opacity(0.7), radius: 2)
                        .offset(x: -6)
                    Spacer()
                }
            }

            // Insertion bar indicator on the right
            if dropPlacement == .after {
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3.5, height: iconSize * 0.85)
                        .shadow(color: Color.blue.opacity(0.85), radius: 5)
                        .shadow(color: Color.white.opacity(0.7), radius: 2)
                        .offset(x: 6)
                }
            }

            // Capsule Content
            HStack(spacing: dividerSpacing) {
                // 1. Folder Miniature Block (bordure supprimée, applications miniatures directement sur le fond de capsule)
                ZStack(alignment: .center) {
                    FolderIconGrid(
                        item: folder,
                        size: folderSize,
                        isHighlighted: isMergeTarget,
                        showBackground: false,
                        bouncingSubItemIds: viewModel.bouncingItemIds,
                        runningSubItemIds: viewModel.runningSubItemIds(for: folder),
                        subItemWindowCounts: viewModel.subItemWindowCounts(for: folder),
                        hiddenSubItemIds: viewModel.hiddenSubItemIds(for: folder),
                        hiddenAppOpacity: viewModel.config.hiddenAppOpacity
                    )
                    .dockBounce(isBouncing: viewModel.isItemBouncing(folder))
                }
                .frame(width: folderSize, height: folderSize)
                .scaleEffect(isFolderHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isFolderHovered)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isFolderHovered = hovering
                }
                .onTapGesture {
                    onFolderTap()
                }
                .contextMenu {
                    contextMenuItems
                }

                // 2. Subtle Vertical Divider
                if activeCount > 0 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1.2, height: bubbleHeight * 0.70)
                        .transition(.opacity)
                }

                // 3. Running Sub-Applications
                HStack(spacing: subAppSpacing) {
                    ForEach(runningSubItems) { subApp in
                        RunningSubAppItemView(
                            viewModel: viewModel,
                            folder: folder,
                            subApp: subApp,
                            iconSize: iconSize,
                            bubbleHeight: bubbleHeight,
                            subIconSize: subAppIconSize,
                            subAppSlotWidth: subAppSlotWidth
                        )
                    }
                }
            }
            .padding(.horizontal, capsuleHorizontalPadding)
            .frame(height: bubbleHeight)
            .background(
                RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                    .fill(
                        isMergeTarget
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
                                    Color(white: 0.22).opacity(0.72),
                                    Color(white: 0.14).opacity(0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                            .stroke(
                                isMergeTarget
                                    ? LinearGradient(
                                        colors: [Color.white, Color.cyan.opacity(0.95), Color.white.opacity(0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.14)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                lineWidth: isMergeTarget ? 2.5 : 1.0
                            )
                    )
                    .shadow(
                        color: isMergeTarget ? Color.blue.opacity(0.95) : Color.black.opacity(0.2),
                        radius: isMergeTarget ? 12 : 3,
                        x: 0,
                        y: isMergeTarget ? 0 : 1.5
                    )
                    .shadow(
                        color: isMergeTarget ? Color.cyan.opacity(0.8) : Color.clear,
                        radius: isMergeTarget ? 6 : 0,
                        x: 0,
                        y: 0
                    )
            )
            .onHover { hovering in
                isCapsuleHovered = hovering
            }

            // 4. Folder Title centré sur toute la longueur de la capsule
            if viewModel.config.showFolderTitles {
                Text(folder.title.uppercased())
                    .font(.system(size: folderFontSize, weight: .medium, design: .rounded))
                    .foregroundColor((isCapsuleHovered || isFolderHovered) ? .white : Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.8), radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: max(40, capsuleWidth - 8))
                    .offset(y: -(iconSize / 2 + viewModel.config.labelDistance))
            }

            // 5. Pastille d'activité centrée sous toute la capsule
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 4, height: 4)
                .shadow(color: Color.white.opacity(0.8), radius: 2)
                .offset(y: iconSize / 2 + viewModel.config.labelDistance)
        }
    }
}

// MARK: - Running Sub-App Item View

private struct RunningSubAppItemView: View {
    @ObservedObject var viewModel: DockViewModel
    let folder: DockItem
    let subApp: DockItem
    let iconSize: CGFloat
    let bubbleHeight: CGFloat
    let subIconSize: CGFloat
    let subAppSlotWidth: CGFloat

    @State private var isHovered: Bool = false

    private var subFontSize: CGFloat {
        max(7.5, min(8.8, iconSize * 0.125))
    }

    private var isTerminating: Bool {
        viewModel.terminatingItemIds.contains(subApp.id)
    }

    private var isAppHidden: Bool {
        viewModel.isItemHidden(subApp)
    }

    private var effectiveOpacity: Double {
        if isTerminating {
            return 0.0
        }
        if isAppHidden {
            return isHovered ? min(1.0, viewModel.config.hiddenAppOpacity + 0.25) : viewModel.config.hiddenAppOpacity
        }
        return 1.0
    }

    private var windowCount: Int {
        viewModel.windowCount(for: subApp)
    }

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 1)

            // Sub-App Title (en haut, à l'intérieur de la capsule)
            if viewModel.config.showAppTitles {
                Text(subApp.title)
                    .font(.system(size: subFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(isHovered ? .white : Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.8), radius: 1.0, x: 0, y: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
                    .frame(maxWidth: subAppSlotWidth)
                    .opacity(isTerminating ? 0.0 : 1.0)
            }

            // Icon (au milieu)
            Image(nsImage: IconProvider.shared.icon(for: subApp, size: subIconSize))
                .resizable()
                .scaledToFit()
                .frame(width: subIconSize, height: subIconSize)
                .clipShape(RoundedRectangle(cornerRadius: subIconSize * 0.22, style: .continuous))
                .opacity(effectiveOpacity)
                .shadow(color: Color.black.opacity(isAppHidden ? 0.1 : 0.25), radius: 2, x: 0, y: 1)
                .scaleEffect(isTerminating ? 0.05 : (isHovered ? 1.08 : 1.0))
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isTerminating)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)
                .dockBounce(isBouncing: viewModel.isItemBouncing(subApp))

            // Multi-window Activity Indicator (en bas, à l'intérieur de la capsule)
            MultiWindowIndicatorView(
                windowCount: windowCount,
                dotSize: 2.3,
                spacing: 1.6
            )
            .opacity(isTerminating ? 0.0 : 1.0)

            Spacer(minLength: 1)
        }
        .frame(width: isTerminating ? 0 : subAppSlotWidth, height: bubbleHeight)
        .clipped()
        .contentShape(Rectangle())
        .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isTerminating)
        .onHover { hovering in
            guard !isTerminating else { return }
            isHovered = hovering
            if hovering {
                viewModel.hoveredItemId = subApp.id
                viewModel.refreshWindowCounts()
            } else if viewModel.hoveredItemId == subApp.id {
                viewModel.hoveredItemId = nil
            }
        }
        .onTapGesture {
            guard !isTerminating else { return }
            viewModel.launch(item: subApp)
        }
        .contextMenu {
            if subApp.isFinder {
                Button("Nouvelle fenêtre du Finder") {
                    viewModel.openNewFinderWindow()
                }
            } else {
                Button("Ouvrir") {
                    viewModel.launch(item: subApp)
                }

                Button("Quitter l'application") {
                    viewModel.terminate(item: subApp)
                }
            }

            Divider()

            Button("Ouvrir le dossier « \(folder.title) »") {
                viewModel.toggleFolderPopover(folder)
            }
        }
        .help(isTerminating ? "" : subApp.title)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemFramesPreferenceKey.self,
                    value: isTerminating ? [:] : [subApp.id: geo.frame(in: .named("dockContainer"))]
                )
            }
        )
    }
}
