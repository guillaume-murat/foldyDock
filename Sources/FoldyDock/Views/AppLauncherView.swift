import SwiftUI
import AppKit

public struct AppLauncherView: View {
    @ObservedObject var viewModel: DockViewModel
    public let iconSize: CGFloat
    public let dockHeight: CGFloat

    @State private var isHovered: Bool = false

    public init(viewModel: DockViewModel, iconSize: CGFloat, dockHeight: CGFloat) {
        self.viewModel = viewModel
        self.iconSize = iconSize
        self.dockHeight = dockHeight
    }

    private var itemWidth: CGFloat {
        max(iconSize + 12, iconSize * 1.22 + 4)
    }

    private var labelFontSize: CGFloat {
        max(9.0, min(11.5, iconSize * 0.17))
    }

    public var body: some View {
        ZStack(alignment: .center) {
            // 1. FoldyDock Logo Icon
            ZStack(alignment: .center) {
                Image(nsImage: LogoProvider.shared.logoImage(size: iconSize * 1.05))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(
                        color: Color.black.opacity(isHovered ? 0.35 : 0.2),
                        radius: isHovered ? 5 : 2.5,
                        x: 0,
                        y: isHovered ? 3 : 1.5
                    )
            }
            .frame(width: iconSize, height: iconSize)
            .scaleEffect(isHovered ? 1.12 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)

            // 2. Title "Foldy" above the icon at fixed distance
            if viewModel.config.showAppTitles {
                Text("Foldy")
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
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
        .help("Foldy")
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            viewModel.toggleApplicationsLauncher()
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            } label: {
                Label("Ouvrir le dossier Applications", systemImage: "folder")
            }

            Divider()

            Button {
                viewModel.openSettingsWindow()
            } label: {
                Label("Paramètres FoldyDock…", systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quitter FoldyDock", systemImage: "power")
            }
        }
        .popover(
            isPresented: Binding(
                get: { viewModel.isApplicationsLauncherOpen },
                set: { isPresented in
                    if !isPresented {
                        viewModel.closeApplicationsLauncher(recordDismissal: true)
                    }
                }
            ),
            attachmentAnchor: .point(.top),
            arrowEdge: .top
        ) {
            ApplicationsPopoverView(viewModel: viewModel)
        }
    }
}
