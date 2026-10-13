import SwiftUI
import AppKit

public struct WindowPickerPopoverView: View {
    @ObservedObject var viewModel: DockViewModel
    let item: DockItem

    @State private var hoveredWindowId: String? = nil

    public init(viewModel: DockViewModel, item: DockItem) {
        self.viewModel = viewModel
        self.item = item
    }

    private var windows: [AppWindowInfo] {
        viewModel.activeWindowPickerList
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: App Icon & Title
            HStack(spacing: 7) {
                Image(nsImage: IconProvider.shared.icon(for: item, size: 18))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)

                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 2)

            Divider()
                .padding(.horizontal, 6)

            // Window list
            VStack(spacing: 3) {
                ForEach(windows) { win in
                    let isRowHovered = hoveredWindowId == win.id
                    Button(action: {
                        viewModel.selectWindow(win, for: item)
                    }) {
                        HStack(spacing: 9) {
                            // Status indicator: Blue for active, Orange for minimized, neutral for other
                            ZStack {
                                if win.isMain {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 7, height: 7)
                                        .shadow(color: Color.blue.opacity(0.6), radius: 3)
                                } else if win.isMinimized {
                                    Circle()
                                        .fill(Color.orange.opacity(0.9))
                                        .frame(width: 7, height: 7)
                                } else {
                                    Circle()
                                        .fill(Color.secondary.opacity(0.35))
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(width: 10)

                            // Window title
                            Text(win.title)
                                .font(.system(size: 12, weight: win.isMain ? .medium : .regular))
                                .foregroundStyle(win.isMain ? .primary : (isRowHovered ? .primary : .secondary))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isRowHovered ? Color.primary.opacity(0.08) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            hoveredWindowId = win.id
                        } else if hoveredWindowId == win.id {
                            hoveredWindowId = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 220, maxWidth: 320)
        .onHover { hovering in
            if hovering {
                viewModel.handleWindowPickerHoverStart()
            } else {
                viewModel.handleWindowPickerHoverEnd()
            }
        }
    }
}
