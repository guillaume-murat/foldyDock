import SwiftUI
import AppKit

public struct DockItemView: View {
    @ObservedObject var viewModel: DockViewModel
    public let item: DockItem
    public let iconSize: CGFloat
    public let dockHeight: CGFloat

    @State private var isHovered: Bool = false

    private var dropPlacement: DropPlacement? {
        if viewModel.activeDropTargetId == item.id {
            return viewModel.activeDropPlacement
        }
        return nil
    }

    public init(viewModel: DockViewModel, item: DockItem, iconSize: CGFloat = 52.0, dockHeight: CGFloat? = nil) {
        self.viewModel = viewModel
        self.item = item
        self.iconSize = iconSize
        self.dockHeight = dockHeight ?? (iconSize + 40)
    }

    private var isRunning: Bool {
        viewModel.isItemRunning(item)
    }

    private var windowCount: Int {
        viewModel.windowCount(for: item)
    }

    private var runningSubItems: [DockItem] {
        guard item.type == .folder else { return [] }
        return viewModel.runningSubItems(for: item)
    }

    private var isExpandedFolder: Bool {
        item.type == .folder && !runningSubItems.isEmpty
    }

    private var itemWidth: CGFloat {
        if item.type == .separator {
            return 14.0
        }
        if isExpandedFolder {
            let terminatingCount = runningSubItems.filter { viewModel.terminatingItemIds.contains($0.id) }.count
            let activeCount = max(0, runningSubItems.count - terminatingCount)
            if activeCount > 0 {
                return ExpandedFolderBubbleView.capsuleWidth(iconSize: iconSize, activeCount: activeCount)
            }
        }
        return iconSize
    }

    private var folderFontSize: CGFloat {
        max(9.0, min(11.5, iconSize * 0.17))
    }

    private var isTerminating: Bool {
        viewModel.terminatingItemIds.contains(item.id)
    }

    public var body: some View {
        ZStack(alignment: .center) {
            if isExpandedFolder {
                ExpandedFolderBubbleView(
                    viewModel: viewModel,
                    folder: item,
                    runningSubItems: runningSubItems,
                    iconSize: iconSize,
                    dockHeight: dockHeight,
                    folderFontSize: folderFontSize,
                    isMergeTarget: dropPlacement == .merge,
                    dropPlacement: dropPlacement,
                    onFolderTap: {
                        viewModel.toggleFolderPopover(item)
                    },
                    contextMenuItems: AnyView(contextMenuItems)
                )
            } else {
                // 1. Main Icon (App or Folder) - perfectly vertically centered
            ZStack(alignment: .center) {
                // Insertion bar indicator on the left
                if dropPlacement == .before {
                    HStack {
                        InsertionBar(height: iconSize * 0.85)
                            .offset(x: -(viewModel.config.itemSpacing / 2 + 1))
                        Spacer()
                    }
                }

                // Insertion bar indicator on the right
                if dropPlacement == .after {
                    HStack {
                        Spacer()
                        InsertionBar(height: iconSize * 0.85)
                            .offset(x: viewModel.config.itemSpacing / 2 + 1)
                    }
                }

                // Glowing highlight halo when targeted for folder addition or merge
                if dropPlacement == .merge {
                    let haloSize = iconSize + 8
                    RoundedRectangle(cornerRadius: haloSize * 0.25, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(red: 0.25, green: 0.65, blue: 1.0),
                                    Color.cyan,
                                    Color.white.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3.0
                        )
                        .frame(width: haloSize, height: haloSize)
                        .shadow(color: Color.blue.opacity(0.95), radius: 12)
                        .shadow(color: Color.cyan.opacity(0.8), radius: 6)
                        .shadow(color: Color.white.opacity(0.85), radius: 3)
                        .transition(.scale.combined(with: .opacity))
                }

                // Main Icon (App, Folder, Separator, or Settings)
                ZStack(alignment: .center) {
                    switch item.type {
                    case .folder:
                        FolderIconGrid(
                            item: item,
                            size: iconSize,
                            isHighlighted: dropPlacement == .merge,
                            bouncingSubItemIds: viewModel.bouncingItemIds,
                            runningSubItemIds: viewModel.runningSubItemIds(for: item),
                            subItemWindowCounts: viewModel.subItemWindowCounts(for: item),
                            hiddenSubItemIds: viewModel.hiddenSubItemIds(for: item),
                            hiddenAppOpacity: viewModel.config.hiddenAppOpacity
                        )
                    case .separator:
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.40),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1.5, height: iconSize * 0.65)
                            .shadow(color: Color.white.opacity(0.25), radius: 1)
                    case .settings:
                        EmptyView()
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: Color.black.opacity(0.2), radius: 2.5, x: 0, y: 1.5)
                    case .app:
                        let appIconScale: CGFloat = 1.22
                        let isAppHidden = isRunning && viewModel.isItemHidden(item)
                        let effectiveOpacity = isTerminating ? 0.0 : (isAppHidden ? (isHovered ? min(1.0, viewModel.config.hiddenAppOpacity + 0.25) : viewModel.config.hiddenAppOpacity) : 1.0)
                        Image(nsImage: IconProvider.shared.icon(for: item, size: iconSize * appIconScale))
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize * appIconScale, height: iconSize * appIconScale)
                            .opacity(effectiveOpacity)
                            .scaleEffect(isTerminating ? 0.05 : 1.0)
                            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isTerminating)
                            .animation(.easeInOut(duration: 0.25), value: isAppHidden)
                            .overlay(
                                Group {
                                    if dropPlacement == .merge {
                                        RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                                            .stroke(Color.white.opacity(0.95), lineWidth: 2.0)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                                                    .fill(Color.blue.opacity(0.3))
                                            )
                                    }
                                }
                            )
                            .shadow(color: Color.black.opacity(isAppHidden ? 0.1 : 0.2), radius: 2.5, x: 0, y: 1.5)
                    }
                }
                .frame(width: item.type == .separator ? 14 : iconSize, height: iconSize)
                .dockBounce(isBouncing: viewModel.isItemBouncing(item))
            }
            .frame(width: item.type == .separator ? 14 : iconSize, height: iconSize)
            .scaleEffect(item.type == .separator ? 1.0 : (dropPlacement == .merge ? 1.15 : (isHovered ? 1.12 : 1.0)))
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: dropPlacement)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    viewModel.hoveredItemId = item.id
                    viewModel.refreshWindowCounts()
                } else if viewModel.hoveredItemId == item.id {
                    viewModel.hoveredItemId = nil
                }
            }
            .onTapGesture {
                if item.type == .separator {
                    // Separator is non-clickable for launch
                } else {
                    viewModel.launch(item: item)
                }
            }
            .contextMenu {
                contextMenuItems
            }

            // 2. Title (apps & folders) positioned above the icon at fixed distance
            if item.type == .folder && viewModel.config.showFolderTitles {
                Text(item.title.uppercased())
                    .font(.system(size: folderFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(isHovered ? .white : Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.8), radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: max(itemWidth + 18, 92))
                    .offset(y: -(iconSize / 2 + viewModel.config.labelDistance))
            } else if item.type == .app && viewModel.config.showAppTitles {
                Text(item.title)
                    .font(.system(size: folderFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(isHovered ? .white : Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.8), radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: max(itemWidth + 18, 92))
                    .offset(y: -(iconSize / 2 + viewModel.config.labelDistance))
            }

            // 3. Running indicator dot(s) positioned below the icon in the bottom margin
            if isRunning && !isTerminating {
                runningIndicatorView
            }
            }
        }
        .frame(width: isTerminating && !item.isPinned ? 0 : itemWidth, height: dockHeight, alignment: .center)
        .clipped()
        .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isTerminating)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isExpandedFolder)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: runningSubItems.count)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: viewModel.terminatingItemIds)
        .help(isTerminating ? "" : item.title)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemFramesPreferenceKey.self,
                    value: isTerminating ? [:] : [item.id: geo.frame(in: .named("dockContainer"))]
                )
            }
        )
        // Drag source
        .onDrag {
            print("[DOCK_EVENT] onDrag started for: \(item.title) (id: \(item.id))")
            viewModel.dragSourceId = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        // Drop destination
        .onDrop(of: [.plainText, .utf8PlainText, .text], delegate: DockItemDropDelegate(
            targetItem: item,
            viewModel: viewModel,
            itemWidth: itemWidth
        ))

    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch item.type {
        case .separator:
            Button("Supprimer le séparateur") {
                viewModel.removeItem(itemId: item.id)
            }
        case .settings:
            EmptyView()
        case .folder:
            Button("Ouvrir le dossier") {
                viewModel.toggleFolderPopover(item)
            }

            Button("Renommer le dossier...") {
                showRenameDialog()
            }

            Button("Dissocier le dossier") {
                viewModel.dissolveFolder(folderId: item.id)
            }

            Divider()

            Button("Supprimer du dock") {
                viewModel.removeItem(itemId: item.id)
            }
        case .app:
            if item.isFinder {
                Button("Nouvelle fenêtre du Finder") {
                    viewModel.openNewFinderWindow()
                }

                Divider()
            } else if isRunning {
                Button("Quitter l'application") {
                    viewModel.terminate(item: item)
                }

                Divider()
            }

            Button(item.isPinned ? "Détacher du dock" : "Conserver dans le dock") {
                viewModel.togglePin(itemId: item.id)
            }
        }
    }

    @ViewBuilder
    private var runningIndicatorView: some View {
        let indicatorOffset = iconSize / 2 + viewModel.config.labelDistance
        if item.type == .folder {
            // Sous les dossiers sur le dock, une simple pastille suffit
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 4, height: 4)
                .shadow(color: Color.white.opacity(0.8), radius: 2)
                .offset(y: indicatorOffset)
        } else {
            MultiWindowIndicatorView(windowCount: windowCount, dotSize: 4.0, spacing: 3.0)
                .offset(y: indicatorOffset)
        }
    }

    private func showRenameDialog() {
        let alert = NSAlert()
        alert.messageText = "Renommer le dossier"
        alert.informativeText = "Entrez le nouveau nom pour ce dossier :"
        alert.addButton(withTitle: "Enregistrer")
        alert.addButton(withTitle: "Annuler")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = item.title
        alert.accessoryView = input
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.renameFolder(folderId: item.id, newTitle: input.stringValue)
        }
    }
}

// MARK: - Insertion Bar Visual Indicator

private struct InsertionBar: View {
    var height: CGFloat = 48

    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 3.5, height: height)
            .shadow(color: Color.blue.opacity(0.85), radius: 5)
            .shadow(color: Color.white.opacity(0.7), radius: 2)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Drop Delegate for Reordering & Folder Merge

private struct DockItemDropDelegate: DropDelegate {
    let targetItem: DockItem
    let viewModel: DockViewModel
    let itemWidth: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.plainText, .utf8PlainText, .text])
    }

    func dropEntered(info: DropInfo) {
        updatePlacement(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePlacement(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if viewModel.activeDropTargetId == targetItem.id {
            viewModel.clearDropTarget()
        }
    }

    private func updatePlacement(info: DropInfo) {
        guard let sourceId = viewModel.dragSourceId, sourceId != targetItem.id else {
            return
        }

        let edgeThreshold = targetItem.type == .folder ? itemWidth * 0.16 : itemWidth * 0.28
        let x = info.location.x

        let placement: DropPlacement
        if targetItem.type == .separator {
            placement = x < (itemWidth / 2) ? .before : .after
        } else if x < edgeThreshold {
            placement = .before
        } else if x > (itemWidth - edgeThreshold) {
            placement = .after
        } else {
            placement = .merge
        }

        viewModel.setDropTarget(itemId: targetItem.id, placement: placement)
    }

    func performDrop(info: DropInfo) -> Bool {
        let edgeThreshold = targetItem.type == .folder ? itemWidth * 0.16 : itemWidth * 0.28
        let x = info.location.x

        let placement: DropPlacement
        if let active = viewModel.activeDropPlacement, viewModel.activeDropTargetId == targetItem.id {
            placement = active
        } else if targetItem.type == .separator {
            placement = x < (itemWidth / 2) ? .before : .after
        } else if x < edgeThreshold {
            placement = .before
        } else if x > (itemWidth - edgeThreshold) {
            placement = .after
        } else {
            placement = .merge
        }

        defer {
            viewModel.clearDropState()
        }

        // 1. Direct sourceId from ViewModel
        if let sourceId = viewModel.dragSourceId, sourceId != targetItem.id {
            applyDrop(sourceId: sourceId, placement: placement)
            return true
        }

        // 2. Fallback via NSItemProvider
        let providers = info.itemProviders(for: [.plainText, .utf8PlainText, .text])
        if let provider = providers.first {
            _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                if let uuidString = string as? String, let sourceId = UUID(uuidString: uuidString) {
                    DispatchQueue.main.async {
                        self.applyDrop(sourceId: sourceId, placement: placement)
                    }
                }
            }
            return true
        }

        return false
    }

    private func applyDrop(sourceId: UUID, placement: DropPlacement) {
        guard sourceId != targetItem.id else { return }
        print("[DOCK_EVENT] applyDrop called! sourceId: \(sourceId), target: \(targetItem.title), placement: \(placement)")

        switch placement {
        case .merge:
            viewModel.mergeIntoFolder(sourceId: sourceId, targetId: targetItem.id)
        case .before, .after:
            viewModel.moveItem(sourceId: sourceId, targetId: targetItem.id, placement: placement)
        }
    }
}
