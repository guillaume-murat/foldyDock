import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dockPanel: DockPanel?
    private var viewModel: DockViewModel?
    private var statusItem: NSStatusItem?
    private var hostingView: NSView?
    private var folderPopover: NSPopover?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app: no icon in standard macOS Dock
        NSApp.setActivationPolicy(.accessory)

        let vm = DockViewModel()
        self.viewModel = vm

        let initialDockHeight = vm.dockHeight
        var pendingDockSize: CGSize?

        let containerView = DockContainerView(viewModel: vm) { [weak self] newSize in
            if let panel = self?.dockPanel {
                let adjustedWidth = max(ceil(newSize.width), 200)
                panel.updateDockSize(width: adjustedWidth, height: newSize.height)
            } else {
                pendingDockSize = newSize
            }
        }

        let hostingView = ClickThroughHostingView(rootView: containerView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.hostingView = hostingView

        vm.onActiveFolderChanged = { [weak self, weak vm] folder in
            guard let self = self, let vm = vm else { return }
            if let folder = folder {
                self.showFolderPopover(for: folder, viewModel: vm)
            } else {
                self.closeFolderPopover()
            }
        }

        let panel = DockPanel(contentView: hostingView, initialDockHeight: initialDockHeight)
        panel.autohideEnabled = vm.config.autohideEnabled
        panel.autohideDelay = vm.config.autohideDelay
        panel.showDelay = vm.config.showDelay

        vm.onAutohideToggled = { [weak panel, weak self] enabled in
            panel?.autohideEnabled = enabled
            self?.updateMenuBarAutohideState(enabled)
        }
        vm.onConfigUpdated = { [weak panel] updatedConfig in
            panel?.autohideDelay = updatedConfig.autohideDelay
            panel?.showDelay = updatedConfig.showDelay
        }
        vm.onResetDock = { [weak panel] in
            panel?.reposition()
        }

        vm.onOpenSettingsWindow = { [weak self] in
            self?.openSettingsAction()
        }

        setupMouseMonitors(hostingView: hostingView)
        panel.shouldPreventAutoHide = { [weak vm] in
            guard let vm = vm else { return false }
            if NSEvent.pressedMouseButtons == 0 && vm.dragSourceId != nil {
                vm.clearDropState()
            }
            return vm.activeFolder != nil || vm.isApplicationsLauncherOpen || vm.dragSourceId != nil || vm.activeDropTargetId != nil || vm.isResizing
        }

        self.dockPanel = panel

        if let size = pendingDockSize {
            let adjustedWidth = max(ceil(size.width), 200)
            panel.updateDockSize(width: adjustedWidth, height: size.height)
        }

        panel.orderFront(nil)
        panel.reposition()

        setupMenuBarStatusItem()
        setupScreenChangeObserver()
        NSApp.applicationIconImage = LogoProvider.shared.logoImage(size: 512)
    }

    private func showFolderPopover(for folder: DockItem, viewModel: DockViewModel) {
        closeFolderPopover()
        guard let panel = self.dockPanel, let anchorView = panel.contentView else { return }

        let dockHeight = panel.frame.height
        let itemRect: CGRect
        if let frame = viewModel.itemFrames[folder.id] {
            let runningSubItems = viewModel.runningSubItems(for: folder)
            let folderX: CGFloat
            let folderWidth: CGFloat
            if !runningSubItems.isEmpty {
                folderWidth = max(32.0, viewModel.config.iconSize * 0.72)
                folderX = frame.origin.x + 8.0
            } else {
                folderWidth = frame.width
                folderX = frame.origin.x
            }
            itemRect = CGRect(x: folderX, y: dockHeight - 2, width: folderWidth, height: 1)
        } else {
            itemRect = CGRect(x: anchorView.bounds.midX - 40, y: dockHeight - 2, width: 80, height: 1)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let popoverView = FolderPopoverView(viewModel: viewModel, folder: folder)
        let hostingController = NSHostingController(rootView: popoverView)
        popover.contentViewController = hostingController
        popover.delegate = self
        popover.show(relativeTo: itemRect, of: anchorView, preferredEdge: .maxY)
        self.folderPopover = popover

        // Ensure popover window never overlaps the dock bar vertically
        DispatchQueue.main.async {
            for w in NSApp.windows where NSStringFromClass(type(of: w)).contains("Popover") {
                let targetMinY = panel.frame.maxY
                if w.frame.minY < targetMinY {
                    var f = w.frame
                    f.origin.y = targetMinY
                    w.setFrame(f, display: true)
                }
            }
        }
    }

    private func closeFolderPopover() {
        if let popover = folderPopover {
            popover.close()
            folderPopover = nil
        }
    }

    private func setupMenuBarStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = LogoProvider.shared.menuBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "FoldyDock"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "FoldyDock v1.0.1", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Paramètres FoldyDock…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let showItem = NSMenuItem(title: "Afficher le Dock", action: #selector(showDockAction), keyEquivalent: "d")
        showItem.target = self
        menu.addItem(showItem)

        let toggleAutohide = NSMenuItem(title: "Masquage automatique (Autohide)", action: #selector(toggleAutohideAction), keyEquivalent: "")
        toggleAutohide.target = self
        toggleAutohide.state = (viewModel?.config.autohideEnabled ?? true) ? .on : .off
        menu.addItem(toggleAutohide)

        menu.addItem(NSMenuItem.separator())

        let resetItem = NSMenuItem(title: "Réinitialiser les applications par défaut", action: #selector(resetDockAction), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter FoldyDock", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openSettingsAction() {
        guard let vm = viewModel else { return }
        SettingsWindowController.shared.show(viewModel: vm)
    }

    @objc private func showDockAction() {
        dockPanel?.showDock(animated: true)
    }

    @objc private func toggleAutohideAction(_ sender: NSMenuItem) {
        guard let vm = viewModel, let panel = dockPanel else { return }
        vm.config.autohideEnabled.toggle()
        panel.autohideEnabled = vm.config.autohideEnabled
        sender.state = vm.config.autohideEnabled ? .on : .off
        DockPersistenceService.shared.saveConfig(vm.config)
    }

    @objc private func resetDockAction() {
        guard let vm = viewModel else { return }
        vm.config = DockConfig.defaultConfig
        vm.items = vm.config.items
        DockPersistenceService.shared.saveConfig(vm.config)
        dockPanel?.reposition()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func updateMenuBarAutohideState(_ enabled: Bool) {
        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleAutohideAction) {
                item.state = enabled ? .on : .off
            }
        }
    }

    private func setupMouseMonitors(hostingView: NSView) {
        NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .rightMouseDown]) { [weak self, weak hostingView] event in
            guard let self = self else { return event }

            if event.type == .rightMouseDown {
                if event.window == self.dockPanel, let hosting = hostingView {
                    let pointInView = hosting.convert(event.locationInWindow, from: nil)
                    self.viewModel?.lastRightClickLocation = pointInView
                }
                return event
            }

            if event.type == .otherMouseDown && event.buttonNumber == 2, let window = event.window {
                // Case 1: Middle-click on main dock panel
                if window == self.dockPanel, let hosting = hostingView {
                    let pointInView = hosting.convert(event.locationInWindow, from: nil)
                    self.viewModel?.handleMiddleClick(at: pointInView)
                    return nil
                }

                // Case 2: Middle-click on a folder popover window
                if let vm = self.viewModel, vm.activeFolder != nil, let contentView = window.contentView {
                    let hosting = self.findHostingView(in: contentView) ?? contentView
                    let pointInView = hosting.convert(event.locationInWindow, from: nil)
                    vm.handleFolderMiddleClick(at: pointInView)
                    return nil
                }
            }

            return event
        }
    }

    private func findHostingView(in view: NSView) -> NSView? {
        if NSStringFromClass(type(of: view)).contains("NSHostingView") {
            return view
        }
        for subview in view.subviews {
            if let found = findHostingView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dockPanel?.updateScreens()
            }
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        if let popover = notification.object as? NSPopover, popover == self.folderPopover {
            self.folderPopover = nil
            self.viewModel?.closeFolderPopover()
        }
    }
}

public final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    public var onRightMouseDown: ((CGPoint) -> Void)?

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override public func rightMouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        onRightMouseDown?(loc)
        super.rightMouseDown(with: event)
    }
}
