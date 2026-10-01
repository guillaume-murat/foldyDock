import SwiftUI
import AppKit

public struct ApplicationsPopoverView: View {
    @ObservedObject var viewModel: DockViewModel
    @ObservedObject var discoveryService = AppDiscoveryService.shared

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    private let appIconSize: CGFloat = 52.0
    private let columns = [
        GridItem(.adaptive(minimum: 84, maximum: 98), spacing: 14)
    ]

    public init(viewModel: DockViewModel) {
        self.viewModel = viewModel
    }

    private var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return discoveryService.installedApps
        }
        return discoveryService.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Logo, Title, Count, Search bar, and Actions
            HStack(spacing: 10) {
                Image(nsImage: LogoProvider.shared.logoImage(size: 24))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text("Applications")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(filteredApps.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.16)))

                Spacer()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("Rechercher…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if let firstApp = filteredApps.first {
                                viewModel.launchInstalledApp(firstApp)
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .frame(width: 140)
                .contentShape(Rectangle())
                .onTapGesture {
                    isSearchFocused = true
                }

                // Open Applications folder in Finder
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                    viewModel.closeApplicationsLauncher()
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Ouvrir le dossier Applications dans le Finder")

                // Close button
                Button(action: {
                    viewModel.closeApplicationsLauncher()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Fermer")
            }
            .padding(.horizontal, 4)

            Divider()
                .background(Color.white.opacity(0.15))

            // Grid of installed applications
            if discoveryService.isLoading && discoveryService.installedApps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Chargement des applications…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Aucune application trouvée")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredApps) { app in
                            appGridItemView(app)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(width: 520, height: 490)
        .background(
            ZStack {
                VisualEffectBackground(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    cornerRadius: 16
                )

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
        .background(FirstResponderFocusHelper())
        .onAppear {
            discoveryService.refreshApps(force: false)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                isSearchFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isSearchFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSearchFocused = true
            }
        }
    }

    @ViewBuilder
    private func appGridItemView(_ app: InstalledApp) -> some View {
        let isRunning = viewModel.isAppRunning(bundleIdentifier: app.bundleIdentifier)

        AppGridItemCell(
            app: app,
            iconSize: appIconSize,
            isRunning: isRunning,
            onLaunch: {
                viewModel.launchInstalledApp(app)
            },
            onPin: {
                viewModel.pinInstalledApp(app)
            }
        )
    }
}

private struct AppGridItemCell: View {
    let app: InstalledApp
    let iconSize: CGFloat
    let isRunning: Bool
    let onLaunch: () -> Void
    let onPin: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Image(nsImage: IconProvider.shared.icon(forPath: app.path, size: iconSize * 1.2))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 4 : 2, x: 0, y: isHovered ? 2 : 1)

                if isRunning {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: Color.white.opacity(0.9), radius: 3)
                        .offset(y: 6)
                }
            }
            .scaleEffect(isHovered ? 1.10 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)

            Text(app.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(isHovered ? .white : Color.white.opacity(0.92))
                .shadow(color: Color.black.opacity(0.8), radius: 1.5, x: 0, y: 1)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(maxWidth: 82)
                .frame(height: 28, alignment: .top)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onLaunch()
        }
        .contextMenu {
            Button {
                onLaunch()
            } label: {
                Label("Ouvrir", systemImage: "arrow.up.forward.app")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Label("Afficher dans le Finder", systemImage: "folder")
            }

            Divider()

            Button {
                onPin()
            } label: {
                Label("Épingler à FoldyDock", systemImage: "pin")
            }
        }
    }
}


// MARK: - Auto-Focus & Position Clamping Helper
private struct FirstResponderFocusHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusTriggerView {
        FocusTriggerView()
    }

    func updateNSView(_ nsView: FocusTriggerView, context: Context) {}

    final class FocusTriggerView: NSView {
        private var resizeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }

            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()

            self.adjustPosition(window: window)

            for delay in [0.01, 0.05, 0.12, 0.25] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                    guard let self = self, let window = window else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKey()
                    self.adjustPosition(window: window)
                    self.focusSearchField(in: window.contentView)
                }
            }

            if resizeObserver == nil {
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self = self, let window = window else { return }
                    self.adjustPosition(window: window)
                }
            }
        }

        private func adjustPosition(window: NSWindow) {
            guard let dockWindow = NSApp.windows.first(where: { $0 is DockPanel }) else { return }
            let targetMinY = dockWindow.frame.maxY + 4
            if window.frame.minY < targetMinY {
                var f = window.frame
                f.origin.y = targetMinY
                window.setFrame(f, display: true)
            }
        }

        private func focusSearchField(in view: NSView?) {
            guard let view = view else { return }
            if let textField = view as? NSTextField, textField.isEditable {
                self.window?.makeFirstResponder(textField)
                return
            }
            for subview in view.subviews {
                focusSearchField(in: subview)
            }
        }

        deinit {
            if let observer = resizeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}