import Foundation
import Combine
import AppKit


@MainActor
public final class DockViewModel: ObservableObject {
    @Published public var config: DockConfig
    @Published public var items: [DockItem] = [] {
        didSet {
            if hierarchyEngine.items != items {
                hierarchyEngine.items = items
            }
        }
    }
    public private(set) var hierarchyEngine: DockHierarchyEngine = DockHierarchyEngine()
    @Published public var unpinnedRunningItems: [DockItem] = []

    public var onActiveFolderChanged: ((DockItem?) -> Void)?
    @Published public var activeFolder: DockItem? {
        didSet {
            onActiveFolderChanged?(activeFolder)
        }
    }
    @Published public var isApplicationsLauncherOpen: Bool = false
    @Published public var hoveredItemId: UUID?
    @Published public var dragSourceId: UUID?
    @Published public var activeDropTargetId: UUID?
    @Published public var activeDropPlacement: DropPlacement?
    @Published public var itemFrames: [UUID: CGRect] = [:]
    public var folderItemFrames: [UUID: CGRect] = [:]
    @Published public var bouncingItemIds: Set<UUID> = []
    @Published public var terminatingItemIds: Set<UUID> = []
    private var lastMiddleClickTime: Date = .distantPast
    private var bounceTimers: [UUID: DispatchWorkItem] = [:]

    @Published public var lastRightClickLocation: CGPoint?
    public var onAutohideToggled: ((Bool) -> Void)?
    public var onResetDock: (() -> Void)?
    public var onOpenSettingsWindow: (() -> Void)?
    public var onConfigUpdated: ((DockConfig) -> Void)?

    public func openSettingsWindow() {
        onOpenSettingsWindow?()
    }

    public var dockHeight: CGFloat {
        CGFloat(config.dockHeight)
    }

    @Published public var isResizing: Bool = false
    @Published public var isTrashEmpty: Bool = true
    public static let minIconSize: Double = 32.0
    public static let maxIconSize: Double = 96.0
    private var initialDragIconSize: Double?

    private let persistenceService: DockPersistenceService
    private let appObserver: AppObserverService
    public let launchAtLoginService: LaunchAtLoginProviding
    private var cancellables = Set<AnyCancellable>()

    public convenience init() {
        self.init(persistenceService: .shared, appObserver: .shared, launchAtLoginService: SMAppLaunchAtLoginProvider())
    }

    public convenience init(persistenceService: DockPersistenceService) {
        self.init(persistenceService: persistenceService, appObserver: .shared, launchAtLoginService: SMAppLaunchAtLoginProvider())
    }

    public init(
        persistenceService: DockPersistenceService,
        appObserver: AppObserverService,
        launchAtLoginService: LaunchAtLoginProviding = SMAppLaunchAtLoginProvider()
    ) {
        self.persistenceService = persistenceService
        self.appObserver = appObserver
        self.launchAtLoginService = launchAtLoginService
        self.config = persistenceService.loadConfig()
        self.config.launchAtLogin = launchAtLoginService.isEnabled
        self.items = self.config.items.filter { $0.type != .settings }

        setupAppObserverCallbacks()
        synchronizeRunningUnpinnedApps()
        updateTrashStatus()
        setupTrashTimer()
    }

    private func setupAppObserverCallbacks() {
        appObserver.onAppLaunched = { [weak self] runningApp in
            guard let self = self else { return }
            self.handleAppLaunched(runningApp)
        }

        appObserver.onAppTerminated = { [weak self] bundleId in
            guard let self = self else { return }
            self.handleAppTerminated(bundleId)
        }

        // Forward changes from appObserver to trigger UI re-renders for running status dots
        // and keep unpinnedRunningItems strictly synchronized with runningBundleIds
        appObserver.$runningBundleIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] runningBids in
                guard let self = self else { return }
                self.unpinnedRunningItems.removeAll { item in
                    guard let bid = item.bundleIdentifier else { return false }
                    return !runningBids.contains(bid)
                }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        appObserver.$windowCountsByBundleId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        appObserver.$hiddenAppBundleIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - App Observer Sync

    private func synchronizeRunningUnpinnedApps() {
        let allPinnedBids = Set(items.flatMap(\.allBundleIdentifiers))

        var unpinned: [DockItem] = []
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        for app in runningApps {
            guard let bid = app.bundleIdentifier, !allPinnedBids.contains(bid) else { continue }
            if !unpinned.contains(where: { $0.bundleIdentifier == bid }) {
                let name = app.localizedName ?? bid
                let item = DockItem(
                    type: .app,
                    title: name,
                    bundleIdentifier: bid,
                    appPath: app.bundleURL?.path,
                    isPinned: false
                )
                unpinned.append(item)
            }
        }
        self.unpinnedRunningItems = unpinned
    }

    private func handleAppLaunched(_ runningApp: NSRunningApplication) {
        guard let bid = runningApp.bundleIdentifier else { return }
        let allPinnedBids = Set(items.flatMap(\.allBundleIdentifiers))
        if allPinnedBids.contains(bid) {
            // Already present in pinned items or inside a folder
            return
        }

        if !unpinnedRunningItems.contains(where: { $0.bundleIdentifier == bid }) {
            let name = runningApp.localizedName ?? bid
            let newItem = DockItem(
                type: .app,
                title: name,
                bundleIdentifier: bid,
                appPath: runningApp.bundleURL?.path,
                isPinned: false
            )
            unpinnedRunningItems.append(newItem)
        }
    }

    private func handleAppTerminated(_ bundleId: String) {
        unpinnedRunningItems.removeAll { $0.bundleIdentifier == bundleId }
    }

    // MARK: - Actions

    public func launch(item: DockItem) {
        if item.type == .folder {
            toggleFolderPopover(item)
        } else {
            triggerBounce(for: item)
            appObserver.launchApp(item: item)
        }
    }

    public func isItemBouncing(_ item: DockItem) -> Bool {
        bouncingItemIds.contains(item.id)
    }

    public func triggerBounce(for item: DockItem) {
        // 1. Mark the item itself as bouncing
        bouncingItemIds.insert(item.id)

        // 2. If the item is inside a folder, also mark the parent folder as bouncing on the dock
        var parentFolderId: UUID?
        for folder in items where folder.type == .folder {
            if let subItems = folder.subItems, subItems.contains(where: { $0.id == item.id }) {
                parentFolderId = folder.id
                bouncingItemIds.insert(folder.id)
                break
            }
        }

        // Cancel any pending timer for this item
        bounceTimers[item.id]?.cancel()

        // 3. Schedule completion of bounce animation (3 gentle cycles, ~0.95s)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.bouncingItemIds.remove(item.id)
            if let pId = parentFolderId {
                let hasOtherBouncingChild = self.items
                    .first(where: { $0.id == pId })?
                    .subItems?
                    .contains(where: { self.bouncingItemIds.contains($0.id) }) ?? false
                if !hasOtherBouncingChild {
                    self.bouncingItemIds.remove(pId)
                }
            }
            self.bounceTimers.removeValue(forKey: item.id)
        }

        bounceTimers[item.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: workItem)
    }

    public func terminate(item: DockItem, animated: Bool = true) {
        guard item.type == .app else { return }
        guard !terminatingItemIds.contains(item.id) else { return }

        let isTesting = NSClassFromString("XCTestCase") != nil
        if animated && !isTesting {
            terminatingItemIds.insert(item.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self = self else { return }
                for bid in item.allBundleIdentifiers {
                    self.appObserver.terminateApp(bundleIdentifier: bid)
                }
                if !item.isPinned {
                    self.unpinnedRunningItems.removeAll { $0.id == item.id }
                }
                self.terminatingItemIds.remove(item.id)
            }
        } else {
            for bid in item.allBundleIdentifiers {
                appObserver.terminateApp(bundleIdentifier: bid)
            }
            if !item.isPinned {
                unpinnedRunningItems.removeAll { $0.id == item.id }
            }
        }
    }

    public var runningBundleIds: Set<String> {
        appObserver.runningBundleIds
    }

    public func isItemRunning(_ item: DockItem) -> Bool {
        item.isRunning(in: appObserver.runningBundleIds)
    }

    public func isAppRunning(bundleIdentifier: String?) -> Bool {
        guard let bid = bundleIdentifier else { return false }
        return appObserver.runningBundleIds.contains(bid)
    }

    public func runningSubItemIds(for folder: DockItem) -> Set<UUID> {
        guard let subs = folder.subItems else { return [] }
        return Set(subs.filter { isItemRunning($0) }.map(\.id))
    }

    public func runningSubItems(for folder: DockItem) -> [DockItem] {
        guard let subs = folder.subItems else { return [] }
        return subs.filter { isItemRunning($0) }
    }

    public func windowCount(for item: DockItem) -> Int {
        if item.type == .app {
            guard let bid = item.bundleIdentifier, isItemRunning(item) else { return 0 }
            let count = appObserver.windowCountsByBundleId[bid] ?? 0
            return max(1, count)
        } else if item.type == .folder {
            // Sous les dossiers, une simple pastille suffit si une ou plusieurs apps sont ouvertes
            return isItemRunning(item) ? 1 : 0
        }
        return 0
    }

    public func subItemWindowCounts(for folder: DockItem) -> [UUID: Int] {
        guard let subs = folder.subItems else { return [:] }
        var result: [UUID: Int] = [:]
        for sub in subs {
            if isItemRunning(sub) {
                result[sub.id] = windowCount(for: sub)
            }
        }
        return result
    }

    public func isItemHidden(_ item: DockItem) -> Bool {
        if item.type == .app {
            return item.allBundleIdentifiers.contains { appObserver.hiddenAppBundleIds.contains($0) }
        } else if item.type == .folder {
            let runningSubs = item.subItems?.filter { isItemRunning($0) } ?? []
            guard !runningSubs.isEmpty else { return false }
            return runningSubs.allSatisfy { isItemHidden($0) }
        }
        return false
    }

    public func isAppHidden(bundleIdentifier: String?) -> Bool {
        guard let bid = bundleIdentifier else { return false }
        return appObserver.hiddenAppBundleIds.contains(bid)
    }

    public func hiddenSubItemIds(for folder: DockItem) -> Set<UUID> {
        guard let subs = folder.subItems else { return [] }
        return Set(subs.filter { isItemRunning($0) && isItemHidden($0) }.map(\.id))
    }

    public func refreshHiddenApps() {
        appObserver.refreshHiddenApps()
    }

    public func refreshWindowCounts() {
        appObserver.refreshWindowCounts()
        appObserver.refreshHiddenApps()
    }

    private var lastClosedFolderId: UUID?
    private var lastClosedFolderTime: Date?
    private var lastClosedLauncherTime: Date?

    public func toggleFolderPopover(_ item: DockItem) {
        if isApplicationsLauncherOpen {
            closeApplicationsLauncher()
        }

        // If this exact folder was closed just now (e.g. by the popover outside-click dismiss),
        // the click was intended to close it, so do not immediately re-open it.
        if let lastId = lastClosedFolderId,
           let lastTime = lastClosedFolderTime,
           lastId == item.id,
           Date().timeIntervalSince(lastTime) < 0.4 {
            lastClosedFolderId = nil
            lastClosedFolderTime = nil
            activeFolder = nil
            return
        }

        lastClosedFolderId = nil
        lastClosedFolderTime = nil

        if activeFolder?.id == item.id {
            closeFolderPopover()
        } else {
            activeFolder = item
        }
    }

    public func closeFolderPopover() {
        if let current = activeFolder {
            lastClosedFolderId = current.id
            lastClosedFolderTime = Date()
        }
        activeFolder = nil
    }

    public func toggleApplicationsLauncher() {
        if let lastTime = lastClosedLauncherTime,
           Date().timeIntervalSince(lastTime) < 0.4 {
            lastClosedLauncherTime = nil
            isApplicationsLauncherOpen = false
            return
        }

        lastClosedLauncherTime = nil

        if isApplicationsLauncherOpen {
            closeApplicationsLauncher()
        } else {
            closeFolderPopover()
            isApplicationsLauncherOpen = true
            AppDiscoveryService.shared.refreshApps(force: false)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func closeApplicationsLauncher(recordDismissal: Bool = false) {
        if recordDismissal && isApplicationsLauncherOpen {
            lastClosedLauncherTime = Date()
        }
        isApplicationsLauncherOpen = false
    }

    public func launchInstalledApp(_ app: InstalledApp) {
        closeApplicationsLauncher()
        if let matchingItem = items.first(where: { $0.matches(bundleIdentifier: app.bundleIdentifier ?? "") || $0.appPath == app.path }) {
            triggerBounce(for: matchingItem)
        }
        NSWorkspace.shared.open(app.url)
    }

    public func pinInstalledApp(_ app: InstalledApp) {
        let newItem = DockItem(
            id: UUID(),
            type: .app,
            title: app.name,
            bundleIdentifier: app.bundleIdentifier,
            appPath: app.path,
            isPinned: true
        )
        items.append(newItem)
        saveConfig()
    }

    public func toggleAppLauncher() {
        config.showAppLauncher.toggle()
        saveConfig()
    }

    public func togglePin(itemId: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            // It was in pinned items -> unpin it
            var item = items.remove(at: index)
            item.isPinned = false

            // If it's currently running, move to unpinnedRunningItems
            if isItemRunning(item) {
                unpinnedRunningItems.append(item)
            }
            saveConfig()
        } else if let index = unpinnedRunningItems.firstIndex(where: { $0.id == itemId }) {
            // It was unpinned -> pin it
            var item = unpinnedRunningItems.remove(at: index)
            item.isPinned = true
            items.append(item)
            saveConfig()
        }
    }

    public func removeItem(itemId: UUID) {
        if let unpinnedIndex = unpinnedRunningItems.firstIndex(where: { $0.id == itemId }) {
            let item = unpinnedRunningItems.remove(at: unpinnedIndex)
            terminate(item: item)
            return
        }

        guard let item = hierarchyEngine.findItem(byId: itemId) else { return }
        var engine = hierarchyEngine
        if engine.removeItem(itemId: itemId) {
            self.hierarchyEngine = engine
            self.items = engine.items
            if isItemRunning(item) {
                var unpinned = item
                unpinned.isPinned = false
                unpinnedRunningItems.append(unpinned)
            }
            saveConfig()
        }
    }

    // MARK: - Folder Management

    public func renameFolder(folderId: UUID, newTitle: String) {
        var engine = hierarchyEngine
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "DOSSIER" : trimmed
        if engine.renameFolder(folderId: folderId, newTitle: finalTitle) {
            self.hierarchyEngine = engine
            self.items = engine.items
            if activeFolder?.id == folderId {
                activeFolder = items.first(where: { $0.id == folderId })
            }
            saveConfig()
        }
    }

    public func findItem(byId id: UUID) -> DockItem? {
        if let unpinned = unpinnedRunningItems.first(where: { $0.id == id }) {
            return unpinned
        }
        return hierarchyEngine.findItem(byId: id)
    }

    public func handleMiddleClick(at localPoint: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastMiddleClickTime) > 0.25 else { return }

        // Find candidate items whose frames contain localPoint and are apps
        let matchingApps: [(item: DockItem, rect: CGRect)] = itemFrames.compactMap { (itemId, rect) in
            guard rect.contains(localPoint),
                  let item = findItem(byId: itemId),
                  item.type == .app else { return nil }
            return (item, rect)
        }

        // Pick the most specific (smallest area) matching app
        guard let target = matchingApps.min(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) else {
            return
        }

        lastMiddleClickTime = now
        print("[MIDDLE_CLICK] Terminating app: \(target.item.title) (bundle: \(target.item.bundleIdentifier ?? "nil"))")
        terminate(item: target.item)
    }

    public func handleFolderMiddleClick(at localPoint: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastMiddleClickTime) > 0.25 else { return }

        let matchingApps: [(item: DockItem, rect: CGRect)] = folderItemFrames.compactMap { (itemId, rect) in
            guard rect.contains(localPoint),
                  let item = findItem(byId: itemId),
                  item.type == .app else { return nil }
            return (item, rect)
        }

        guard let target = matchingApps.min(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) else {
            return
        }

        lastMiddleClickTime = now
        print("[MIDDLE_CLICK] Terminating app from folder: \(target.item.title) (bundle: \(target.item.bundleIdentifier ?? "nil"))")
        terminate(item: target.item)
    }

    public func mergeIntoFolder(sourceId: UUID, targetId: UUID, folderName: String = "Dossier") {
        guard sourceId != targetId else { return }
        var engine = hierarchyEngine
        let success = engine.merge(
            sourceId: sourceId,
            targetId: targetId,
            unpinnedItems: &unpinnedRunningItems,
            folderName: folderName
        )
        if success {
            self.hierarchyEngine = engine
            self.items = engine.items
            IconProvider.shared.invalidateCache(for: targetId)
            saveConfig()
        }
    }

    public func removeFromFolder(subItemId: UUID, folderId: UUID) {
        var engine = hierarchyEngine
        let result = engine.removeFromFolder(subItemId: subItemId, folderId: folderId)
        if result.removedItem != nil {
            self.hierarchyEngine = engine
            self.items = engine.items
            IconProvider.shared.invalidateCache(for: folderId)
            if activeFolder?.id == folderId {
                activeFolder = items.first(where: { $0.id == folderId })
            }
            saveConfig()
        }
    }

    public func moveSubItem(folderId: UUID, sourceId: UUID, targetId: UUID, placement: DropPlacement = .before) {
        guard sourceId != targetId else { return }
        var engine = hierarchyEngine
        let success = engine.moveSubItem(folderId: folderId, sourceId: sourceId, targetId: targetId, placement: placement)
        if success {
            self.hierarchyEngine = engine
            self.items = engine.items
            IconProvider.shared.invalidateCache(for: folderId)
            if activeFolder?.id == folderId {
                activeFolder = items.first(where: { $0.id == folderId })
            }
            saveConfig()
        }
    }

    public func dissolveFolder(folderId: UUID) {
        var engine = hierarchyEngine
        let success = engine.dissolveFolder(folderId: folderId)
        if success {
            self.hierarchyEngine = engine
            self.items = engine.items
            if activeFolder?.id == folderId {
                activeFolder = nil
            }
            saveConfig()
        }
    }

    // MARK: - Reordering and Drop State

    public func setDropTarget(itemId: UUID, placement: DropPlacement) {
        self.activeDropTargetId = itemId
        self.activeDropPlacement = placement
    }

    public func clearDropTarget() {
        self.activeDropTargetId = nil
        self.activeDropPlacement = nil
    }

    public func clearDropState() {
        self.activeDropTargetId = nil
        self.activeDropPlacement = nil
        self.dragSourceId = nil
    }

    public func moveItem(sourceId: UUID, targetId: UUID, placement: DropPlacement = .before) {
        guard sourceId != targetId else { return }
        var engine = hierarchyEngine
        let success = engine.moveItem(
            sourceId: sourceId,
            targetId: targetId,
            placement: placement,
            unpinnedItems: &unpinnedRunningItems
        )
        if success {
            self.hierarchyEngine = engine
            self.items = engine.items
            saveConfig()
        }
    }

    public func moveItemToEnd(sourceId: UUID) {
        var engine = hierarchyEngine
        let success = engine.moveItemToEnd(sourceId: sourceId, unpinnedItems: &unpinnedRunningItems)
        if success {
            self.hierarchyEngine = engine
            self.items = engine.items
            saveConfig()
        }
    }

    // MARK: - Dynamic Resizing
    
    public func startResizing() {
        isResizing = true
        initialDragIconSize = config.iconSize
    }

    public func updateIconSize(translationX: CGFloat, isRightEdge: Bool) {
        if !isResizing || initialDragIconSize == nil {
            startResizing()
        }
        guard let baseSize = initialDragIconSize else { return }

        // Total count of items determining sensitivity
        let totalItems = max(3, items.count + unpinnedRunningItems.count)
        
        // Moving right edge to the right (translationX > 0) widens the dock -> increases icon size.
        // Moving left edge to the left (translationX < 0) widens the dock -> increases icon size.
        let effectiveDelta = isRightEdge ? translationX : -translationX

        // 1:1 edge tracking formula: ΔiconSize = (2 * Δedge) / totalItems
        let sizeDelta = Double(effectiveDelta * 2.0) / Double(totalItems)
        let newSize = min(max(baseSize + sizeDelta, Self.minIconSize), Self.maxIconSize)

        if abs(config.iconSize - newSize) > 0.05 {
            config.iconSize = newSize
            objectWillChange.send()
        }
    }

    public func finishResizing() {
        isResizing = false
        initialDragIconSize = nil
        saveConfig()
    }

    // MARK: - Context Menu Insertions & Settings

    public func insertionIndex(for xPosition: CGFloat) -> Int {
        guard !items.isEmpty else { return 0 }

        var itemsWithFrames: [(index: Int, frame: CGRect)] = []
        for (i, item) in items.enumerated() {
            if let frame = itemFrames[item.id] {
                itemsWithFrames.append((index: i, frame: frame))
            }
        }

        guard !itemsWithFrames.isEmpty else {
            return items.count
        }

        itemsWithFrames.sort { $0.frame.minX < $1.frame.minX }

        if xPosition < itemsWithFrames[0].frame.midX {
            return itemsWithFrames[0].index
        }

        for i in 0..<(itemsWithFrames.count - 1) {
            let currentMid = itemsWithFrames[i].frame.midX
            let nextMid = itemsWithFrames[i + 1].frame.midX
            if xPosition >= currentMid && xPosition < nextMid {
                return itemsWithFrames[i].index + 1
            }
        }

        let last = itemsWithFrames[itemsWithFrames.count - 1]
        return last.index + 1
    }

    public func insertSeparator(at index: Int) {
        var engine = hierarchyEngine
        engine.insertSeparator(at: index)
        self.hierarchyEngine = engine
        self.items = engine.items
        saveConfig()
    }

    public func createEmptyFolder(at index: Int, title: String = "NOUVEAU DOSSIER") {
        var engine = hierarchyEngine
        engine.createEmptyFolder(at: index, title: title)
        self.hierarchyEngine = engine
        self.items = engine.items
        saveConfig()
    }

    public func toggleAutohide() {
        config.autohideEnabled.toggle()
        onAutohideToggled?(config.autohideEnabled)
        saveConfig()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        let success = launchAtLoginService.setEnabled(enabled)
        if success {
            config.launchAtLogin = enabled
        } else {
            config.launchAtLogin = launchAtLoginService.isEnabled
        }
        saveConfig()
    }

    public func toggleLaunchAtLogin() {
        setLaunchAtLogin(!config.launchAtLogin)
    }

    public func resetToDefaults() {
        config = DockConfig.defaultConfig
        config.launchAtLogin = launchAtLoginService.isEnabled
        items = config.items.filter { $0.type != .settings }
        saveConfig()
        onResetDock?()
    }

    public func toggleTrash() {
        config.showTrash.toggle()
        saveConfig()
    }

    private func setupTrashTimer() {
        Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTrashStatus()
            }
            .store(in: &cancellables)
    }

    public func updateTrashStatus() {
        guard let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first else {
            isTrashEmpty = true
            return
        }

        var statBuf = stat()
        let empty: Bool
        if stat(trashURL.path, &statBuf) == 0 {
            // On APFS, an empty directory has st_size <= 64 (representing . and .. entries)
            empty = statBuf.st_size <= 64
        } else {
            empty = true
        }

        if isTrashEmpty != empty {
            isTrashEmpty = empty
        }
    }

    public func openTrash() {
        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(trashURL)
        }
        updateTrashStatus()
    }

    public func emptyTrash() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var success = false

            // 1. Try NSAppleScript with Finder activation
            let scriptSource = """
            tell application "Finder"
                activate
                empty trash
            end tell
            """
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                _ = script.executeAndReturnError(&error)
                if error == nil {
                    success = true
                }
            }

            // 2. Fallback: try osascript CLI process if NSAppleScript failed
            if !success {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = ["-e", "tell application \"Finder\" to activate", "-e", "tell application \"Finder\" to empty trash"]
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        success = true
                    }
                } catch {
                    // Ignore
                }
            }

            // 3. Fallback: direct file deletion if permissions permit
            if !success {
                if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
                    if let items = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) {
                        for item in items {
                            try? FileManager.default.removeItem(at: item)
                        }
                    }
                }
            }

            // Refresh status on main thread
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.updateTrashStatus()
            }
        }
    }

    public func dropOnTrash(sourceId: UUID) {
        if let index = items.firstIndex(where: { $0.id == sourceId }) {
            items.remove(at: index)
            saveConfig()
        } else if let unpinned = unpinnedRunningItems.first(where: { $0.id == sourceId }) {
            terminate(item: unpinned)
        }
        updateTrashStatus()
    }

    public func saveConfig() {
        config.items = items.filter { $0.type != .settings }
        persistenceService.saveConfig(config)
        onConfigUpdated?(config)
    }
}
