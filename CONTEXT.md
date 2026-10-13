# FoldyDock Domain

FoldyDock is an expandable, floating macOS dock with folders, window tracking, and real-time frosted glass blur.

## Language

**DockItem**:
An identifiable visual element positioned in the dock or inside a folder (application, folder, separator).
_Avoid_: Node, widget, component

**Folder**:
A composite dock item grouping multiple applications. A folder has a maximum depth of 1 and cannot contain another folder.
_Avoid_: Directory, group, category

**DockHierarchy**:
The ordered collection and structural tree of dock items, enforcing grouping, reordering, and dissolution invariants.
_Avoid_: ItemList, layout tree, container

**Folder Capsule**:
An expanded visual container deployed around an active folder and its running sub-applications, preserving the folder miniature's scale and dock height.
_Avoid_: Expanded bubble, folder popup, sub-dock

**Pinned Application**:
An application persistently positioned in the dock root or inside a folder.
_Avoid_: Favorite, anchored app, bookmark

**Unpinned Application**:
An application temporarily displayed in the dock while active, which disappears when terminated unless pinned.
_Avoid_: Ephemeral app, background app

**Drop Placement**:
The intended spatial resolution of a drag-and-drop interaction relative to a target item (`before`, `after`, or `merge`).
_Avoid_: Drop position, insert mode

**Launch at Login**:
A system integration service managing automatic startup of FoldyDock on macOS user login using Apple's modern `SMAppService` framework.
_Avoid_: Autostart helper, login item daemon

**Window Picker Popover**:
A contextual popover displayed upon hovering an application icon with 2 or more open windows, listing their titles and states (active/minimized) to let the user select and focus a specific window directly.
_Avoid_: Window switcher, Alt-tab preview, thumbnail bar
