# FoldyDock Domain

FoldyDock is an expandable, floating macOS dock with folders, window tracking, real-time frosted glass blur, and system integrations.

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

**NowPlayingWidget**:
A dedicated playback control and metadata capsule anchored between the unpinned applications and the Trash item, surrounded by dividers.
_Avoid_: Music bar, player pill, media widget

**NowPlayingSource**:
The active system media-emitting application (e.g. Music, Spotify, Safari, Chrome) monitored via macOS MediaRemote.
_Avoid_: Music provider, audio player, sound emitter

**TransportControls**:
The dedicated interactive playback controls (Previous, Play/Pause, Next) dispatching remote commands to the active NowPlayingSource.
_Avoid_: Media buttons, player actions, playback buttons

**Launch at Login**:
A system integration service managing automatic startup of FoldyDock on macOS user login using Apple's modern `SMAppService` framework.
_Avoid_: Autostart helper, login item daemon
