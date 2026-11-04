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

**CalendarWidget**:
A dedicated capsule showing the current date and the Next Events, anchored immediately before the NowPlayingWidget and surrounded by dividers. It is not a DockItem and cannot be moved.
_Avoid_: Agenda bar, date pill, calendar item

**Next Events**:
The up to three items shown by the CalendarWidget: today's all-day event if any (one at most), then events in progress, then whichever events or incomplete reminders come soonest within the next 24 hours, across all calendars visible in Calendar and all reminder lists. Reminders without a time and reminders past their time never qualify.
_Avoid_: Upcoming appointments, agenda entries, meetings

**Launch at Login**:
A system integration service managing automatic startup of FoldyDock on macOS user login using Apple's modern `SMAppService` framework.
_Avoid_: Autostart helper, login item daemon

**Window Cycling**:
The round-robin focus rotation among eligible standard windows of an already frontmost application upon repeated dock item clicks. Restores minimized windows upon focus.
_Avoid_: Alt-tabbing, window flipping, task switcher

**Window Picker Popover**:
A contextual popover displayed upon hovering an application icon with 2 or more open windows, listing their titles and states (active/minimized) to let the user select and focus a specific window directly.
_Avoid_: Window switcher, Alt-tab preview, thumbnail bar

**User Window**:
A standard window or dialog of an application that the user works in, on any Space. Excludes panels, palettes, helper windows (such as Chrome's full-screen toolbar) and the Finder desktop.
_Avoid_: Window list entry, CG window

**App Window Inventory**:
The reconciled list of an application's User Windows, pairing what Accessibility reports (current Space) with the application's Window menu (all Spaces). It is the single source for the dock's window dots, the Window Picker Popover, window cycling and the "all windows minimized" state.
_Avoid_: Window list, window count

**Appearance Mode**:
The visual theme governing the dock and its popovers (`system`, `light`, or `dark`), either synchronizing automatically with macOS appearance or enforcing an explicit light or dark frosted glass palette.
_Avoid_: Color scheme, skin, UI style
