import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct TrashItemView: View {
    @ObservedObject var viewModel: DockViewModel
    public let iconSize: CGFloat
    public let dockHeight: CGFloat

    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false

    public init(viewModel: DockViewModel, iconSize: CGFloat, dockHeight: CGFloat) {
        self.viewModel = viewModel
        self.iconSize = iconSize
        self.dockHeight = dockHeight
    }

    private static let emptyTrashPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns"
    private static let fullTrashPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns"
    private static let dockEmptyTrashPath = "/System/Library/CoreServices/Dock.app/Contents/Resources/trashempty@2x.png"
    private static let dockFullTrashPath = "/System/Library/CoreServices/Dock.app/Contents/Resources/trashfull@2x.png"

    private var itemWidth: CGFloat {
        max(iconSize + 12, iconSize * 1.22 + 4)
    }

    private var folderFontSize: CGFloat {
        max(9.0, min(11.5, iconSize * 0.17))
    }

    private var trashIcon: NSImage {
        let isFull = !viewModel.isTrashEmpty

        let bufferSize = iconSize * 2.5
        // 1. Official macOS UTType icon for trash-empty / trash-full
        let typeIdentifier = isFull ? "com.apple.trash-full" : "com.apple.trash-empty"
        if let utType = UTType(typeIdentifier) {
            let icon = NSWorkspace.shared.icon(for: utType)
            icon.size = NSSize(width: bufferSize, height: bufferSize)
            return icon
        }

        // 2. Fallback to CoreTypes.bundle .icns
        let preferredPath = isFull ? Self.fullTrashPath : Self.emptyTrashPath
        if let icon = NSImage(contentsOfFile: preferredPath) {
            icon.size = NSSize(width: bufferSize, height: bufferSize)
            return icon
        }

        // 3. Fallback to Dock.app bundled images
        let fallbackDockPath = isFull ? Self.dockFullTrashPath : Self.dockEmptyTrashPath
        if let dockIcon = NSImage(contentsOfFile: fallbackDockPath) {
            dockIcon.size = NSSize(width: bufferSize, height: bufferSize)
            return dockIcon
        }

        // 4. Fallback to SF Symbol
        if let sfSymbol = NSImage(systemSymbolName: isFull ? "trash.fill" : "trash", accessibilityDescription: "Corbeille") {
            return sfSymbol
        }

        return NSImage()
    }

    public var body: some View {
        let trashIconScale: CGFloat = 1.18
        let renderedTrashSize = iconSize * trashIconScale

        ZStack(alignment: .center) {
            // 1. Main trash icon - centered vertically
            ZStack(alignment: .center) {
                if isDropTargeted {
                    Circle()
                        .fill(Color.red.opacity(0.35))
                        .frame(width: renderedTrashSize * 1.15, height: renderedTrashSize * 1.15)
                        .blur(radius: 4)
                }

                Image(nsImage: trashIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: renderedTrashSize, height: renderedTrashSize)
                    .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 5 : 2.5, x: 0, y: isHovered ? 3 : 1.5)
            }
            .frame(width: iconSize, height: iconSize)
            .scaleEffect(isDropTargeted ? 1.25 : (isHovered ? 1.12 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isDropTargeted)

            // 2. Title "Corbeille" positioned above the icon at fixed distance
            if viewModel.config.showAppTitles {
                Text("Corbeille")
                    .font(.system(size: folderFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(isHovered ? .white : Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.8), radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: itemWidth + 8)
                    .offset(y: -(iconSize / 2 + viewModel.config.labelDistance))
            }
        }
        .frame(width: itemWidth, height: dockHeight, alignment: .center)
        .contentShape(Rectangle())
        .help("Corbeille")
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                viewModel.updateTrashStatus()
            }
        }
        .onTapGesture {
            viewModel.openTrash()
        }
        .contextMenu {
            Button("Ouvrir la corbeille") {
                viewModel.openTrash()
            }

            Button("Vider la corbeille") {
                viewModel.emptyTrash()
            }
            .disabled(viewModel.isTrashEmpty)

            Divider()

            Button("Masquer la corbeille") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    viewModel.toggleTrash()
                }
            }
        }
        .onDrop(of: [.plainText, .utf8PlainText, .text], isTargeted: $isDropTargeted) { _ in
            defer {
                viewModel.clearDropState()
            }
            if let sourceId = viewModel.dragSourceId {
                viewModel.dropOnTrash(sourceId: sourceId)
                return true
            }
            return false
        }
    }
}
