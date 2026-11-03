import Foundation

/// Pure value-type engine managing the dock items collection and structural hierarchy invariants.
public struct DockHierarchyEngine: Equatable, Sendable {
    public var items: [DockItem]

    public init(items: [DockItem] = []) {
        self.items = items
    }

    /// Finds any dock item by its unique ID, either at root level or nested inside a folder.
    public func findItem(byId id: UUID) -> DockItem? {
        for item in items {
            if item.id == id {
                return item
            }
            if let subItems = item.subItems, let match = subItems.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Folder Merging & Grouping

    /// Merges a source item into a target item.
    /// - If target is an app: creates a new folder containing [target, source] at target's position.
    /// - If target is a folder: appends source (or source's children if source is a folder) to target.
    /// Invariant: Maximum depth is 1 (never nests folders inside folders).
    /// Invariant: Unpinned sources are marked pinned when merged into a folder.
    @discardableResult
    public mutating func merge(
        sourceId: UUID,
        targetId: UUID,
        unpinnedItems: inout [DockItem],
        folderName: String = "Dossier"
    ) -> Bool {
        guard sourceId != targetId else { return false }

        // 1. Extract source item
        guard let source = extractItem(id: sourceId, unpinnedItems: &unpinnedItems) else {
            return false
        }

        // 2. Find target item
        guard let targetIndex = items.firstIndex(where: { $0.id == targetId }) else {
            // Restore source to end if target not found
            items.append(source)
            return false
        }

        var target = items[targetIndex]

        if target.type == .folder {
            var subItems = target.subItems ?? []
            if source.type == .folder {
                // Flatten folder contents to preserve max depth = 1
                let pinnedKids = (source.subItems ?? []).map { item -> DockItem in
                    var pinned = item
                    pinned.isPinned = true
                    return pinned
                }
                subItems.append(contentsOf: pinnedKids)
            } else {
                var pinnedSource = source
                pinnedSource.isPinned = true
                subItems.append(pinnedSource)
            }
            target.subItems = subItems
            items[targetIndex] = target
        } else {
            // Target is an app -> create a new folder containing [target, source]
            var folderChildren: [DockItem] = []
            var pinnedTarget = target
            pinnedTarget.isPinned = true
            folderChildren.append(pinnedTarget)

            if source.type == .folder {
                let pinnedKids = (source.subItems ?? []).map { item -> DockItem in
                    var pinned = item
                    pinned.isPinned = true
                    return pinned
                }
                folderChildren.append(contentsOf: pinnedKids)
            } else {
                var pinnedSource = source
                pinnedSource.isPinned = true
                folderChildren.append(pinnedSource)
            }

            let newFolder = DockItem(
                id: UUID(),
                type: .folder,
                title: folderName.uppercased(),
                isPinned: true,
                subItems: folderChildren
            )
            items[targetIndex] = newFolder
        }

        return true
    }

    /// Convenience overload for merge without unpinned items collection.
    @discardableResult
    public mutating func merge(
        sourceId: UUID,
        targetId: UUID,
        folderName: String = "Dossier"
    ) -> Bool {
        var unpinned: [DockItem] = []
        return merge(sourceId: sourceId, targetId: targetId, unpinnedItems: &unpinned, folderName: folderName)
    }

    // MARK: - Folder Dissolution & Sub-item Extraction

    /// Dissolves an entire folder, unpacking all of its sub-items into the root dock list at the folder's position.
    @discardableResult
    public mutating func dissolveFolder(folderId: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == folderId }) else { return false }
        let folder = items.remove(at: index)
        if let subItems = folder.subItems {
            for (offset, item) in subItems.enumerated() {
                var pinned = item
                pinned.isPinned = true
                items.insert(pinned, at: index + offset)
            }
        }
        return true
    }

    /// Removes a sub-item from a folder, inserting it into the root list immediately after the folder.
    /// Invariant: If only 1 sub-item remains after extraction, the folder auto-dissolves into that single item.
    public mutating func removeFromFolder(
        subItemId: UUID,
        folderId: UUID
    ) -> (removedItem: DockItem?, dissolved: Bool) {
        guard let folderIndex = items.firstIndex(where: { $0.id == folderId }),
              var subItems = items[folderIndex].subItems,
              let subIndex = subItems.firstIndex(where: { $0.id == subItemId }) else {
            return (nil, false)
        }

        var extracted = subItems.remove(at: subIndex)
        extracted.isPinned = true

        if subItems.count == 1 {
            // Auto-dissolve singleton folder
            var remainingApp = subItems[0]
            remainingApp.isPinned = true
            items[folderIndex] = remainingApp
            // Insert extracted item right next to the remaining app
            items.insert(extracted, at: folderIndex + 1)
            return (extracted, true)
        } else if subItems.isEmpty {
            // Remove empty folder and place extracted item at that index
            items[folderIndex] = extracted
            return (extracted, true)
        } else {
            // Keep folder with updated sub-items and insert extracted item next to it
            items[folderIndex].subItems = subItems
            items.insert(extracted, at: folderIndex + 1)
            return (extracted, false)
        }
    }

    // MARK: - Reordering

    /// Moves a root item or sub-item relative to a target item (`.before` or `.after`).
    @discardableResult
    public mutating func moveItem(
        sourceId: UUID,
        targetId: UUID,
        placement: DropPlacement = .before,
        unpinnedItems: inout [DockItem]
    ) -> Bool {
        guard sourceId != targetId else { return false }
        guard let item = extractItem(id: sourceId, unpinnedItems: &unpinnedItems) else { return false }

        guard let targetIndex = items.firstIndex(where: { $0.id == targetId }) else {
            items.append(item)
            return true
        }

        let destinationIndex: Int
        switch placement {
        case .before:
            destinationIndex = targetIndex
        case .after:
            destinationIndex = min(targetIndex + 1, items.count)
        case .merge:
            destinationIndex = targetIndex
        }

        items.insert(item, at: destinationIndex)
        return true
    }

    /// Convenience overload for moveItem without unpinned items collection.
    @discardableResult
    public mutating func moveItem(
        sourceId: UUID,
        targetId: UUID,
        placement: DropPlacement = .before
    ) -> Bool {
        var unpinned: [DockItem] = []
        return moveItem(sourceId: sourceId, targetId: targetId, placement: placement, unpinnedItems: &unpinned)
    }

    /// Moves an item to the end of the root dock list.
    @discardableResult
    public mutating func moveItemToEnd(
        sourceId: UUID,
        unpinnedItems: inout [DockItem]
    ) -> Bool {
        guard let item = extractItem(id: sourceId, unpinnedItems: &unpinnedItems) else { return false }
        items.append(item)
        return true
    }

    /// Reorders a sub-item inside a folder.
    @discardableResult
    public mutating func moveSubItem(
        folderId: UUID,
        sourceId: UUID,
        targetId: UUID,
        placement: DropPlacement = .before
    ) -> Bool {
        guard sourceId != targetId else { return false }
        guard let folderIndex = items.firstIndex(where: { $0.id == folderId }),
              var subItems = items[folderIndex].subItems else {
            return false
        }

        var sourceItem: DockItem?

        if let sourceIndex = subItems.firstIndex(where: { $0.id == sourceId }) {
            sourceItem = subItems.remove(at: sourceIndex)
        } else if let dockIndex = items.firstIndex(where: { $0.id == sourceId }) {
            let extracted = items.remove(at: dockIndex)
            if extracted.type == .app {
                sourceItem = extracted
            } else if extracted.type == .folder, let kids = extracted.subItems {
                subItems.append(contentsOf: kids)
            }
        }

        guard let item = sourceItem else {
            items[folderIndex].subItems = subItems
            return false
        }

        let targetIndex = subItems.firstIndex(where: { $0.id == targetId }) ?? subItems.count
        let destinationIndex: Int
        switch placement {
        case .before, .merge:
            destinationIndex = targetIndex
        case .after:
            destinationIndex = min(targetIndex + 1, subItems.count)
        }

        subItems.insert(item, at: destinationIndex)
        items[folderIndex].subItems = subItems
        return true
    }

    // MARK: - Separators & Folder Creation

    /// Inserts a visual separator at the specified index.
    public mutating func insertSeparator(at index: Int) {
        let safeIndex = max(0, min(index, items.count))
        let separator = DockItem(type: .separator, title: "Séparateur")
        items.insert(separator, at: safeIndex)
    }

    /// Creates an empty folder with the given title at the specified index.
    public mutating func createEmptyFolder(at index: Int, title: String = "NOUVEAU DOSSIER") {
        let safeIndex = max(0, min(index, items.count))
        let newFolder = DockItem(
            id: UUID(),
            type: .folder,
            title: title.uppercased(),
            isPinned: true,
            subItems: []
        )
        items.insert(newFolder, at: safeIndex)
    }

    /// Renames a folder by its ID.
    @discardableResult
    public mutating func renameFolder(folderId: UUID, newTitle: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == folderId && $0.type == .folder }) else {
            return false
        }
        items[index].title = newTitle.uppercased()
        return true
    }

    /// Removes an item by its ID from root or from any containing folder.
    /// Invariant: Auto-dissolves a folder if removing this item reduces it to 1 child.
    @discardableResult
    public mutating func removeItem(itemId: UUID) -> Bool {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items.remove(at: index)
            return true
        }

        for folderIndex in items.indices where items[folderIndex].type == .folder {
            if var subItems = items[folderIndex].subItems,
               let subIndex = subItems.firstIndex(where: { $0.id == itemId }) {
                subItems.remove(at: subIndex)

                if subItems.count == 1 {
                    // Auto-dissolve singleton folder
                    var remaining = subItems[0]
                    remaining.isPinned = true
                    items[folderIndex] = remaining
                } else if subItems.isEmpty {
                    items.remove(at: folderIndex)
                } else {
                    items[folderIndex].subItems = subItems
                }
                return true
            }
        }

        return false
    }

    // MARK: - Private Extraction Helper

    private mutating func extractItem(id: UUID, unpinnedItems: inout [DockItem]) -> DockItem? {
        if let rootIndex = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: rootIndex)
        }

        if let unpinnedIndex = unpinnedItems.firstIndex(where: { $0.id == id }) {
            var unpinned = unpinnedItems.remove(at: unpinnedIndex)
            unpinned.isPinned = true
            return unpinned
        }

        for folderIndex in items.indices where items[folderIndex].type == .folder {
            if var children = items[folderIndex].subItems,
               let childIndex = children.firstIndex(where: { $0.id == id }) {
                let extracted = children.remove(at: childIndex)
                if children.count == 1 {
                    var remaining = children[0]
                    remaining.isPinned = true
                    items[folderIndex] = remaining
                } else if children.isEmpty {
                    items.remove(at: folderIndex)
                } else {
                    items[folderIndex].subItems = children
                }
                var pinned = extracted
                pinned.isPinned = true
                return pinned
            }
        }

        return nil
    }
}
