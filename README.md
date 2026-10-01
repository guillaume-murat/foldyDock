<p align="center">
  <img src="logoFoldyDock.png" width="140" alt="FoldyDock Logo" />
</p>

<h1 align="center">FoldyDock</h1>

<p align="center">
  <strong>A sleek, native floating dock for macOS with iOS-style folders, smart window tracking, and real-time frosted glass.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma%20%7C%20Sequoia-black?style=flat-square&logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-blue?style=flat-square" alt="SwiftUI + AppKit" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%26%20Intel-green?style=flat-square" alt="Universal" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License: MIT" />
</p>

<p align="center">
  <a href="#-key-features">Key Features</a> •
  <a href="#-mouse--shortcuts-controls">Shortcuts</a> •
  <a href="#-building--running">Building & Running</a> •
  <a href="#-codebase-architecture">Architecture</a> •
  <a href="#-contributing">Contributing</a> •
  <a href="#-license">License</a>
</p>

---

## 📖 Overview / Présentation

**FoldyDock** is a modern, lightweight, native macOS dock alternative designed to replace or complement the default macOS Dock with powerful productivity features:

- 📂 **iOS-Style App Folders** with real-time responsive miniatures, popover management, and drag-and-drop merging.
- 🪟 **Floating Frosted Glass Bar** powered by native `NSVisualEffectView` blur and unobtrusive floating window level.
- 🌐 **Full Multi-Space Support** (`.canJoinAllSpaces`), appearing seamlessly across all virtual desktops.
- ⚡ **Smart Window Tracking & Multi-Dot Indicators** showing exact running instances and open window counts.
- 🖱️ **Rapid Middle-Click App Quit** with smooth exit animations.
- 🚀 **Built-in App Launcher & Instant Search** to quickly find and launch any application on your Mac.
- ⚙️ **Comprehensive Settings Window (`⌘,`)** with real-time adjustments for sizes, paddings, autohide delays, and start at login.

---

## ✨ Key Features

### 1. 🪟 Native Frosted Glass Floating Dock
- Positioned horizontally and centered at the bottom of your screen.
- Real-time hardware-accelerated background blur (`NSVisualEffectView` with `.hudWindow` vibrancy) integrating gracefully with wallpapers and windows.
- Non-activating `NSPanel` (`.floating` level), ensuring clicks and hover animations never steal keyboard focus from your foreground application.
- Active across **all virtual desktops (Spaces)** and full-screen environments.

### 2. 📁 iOS-Style App Folders
- **Dynamic Miniatures Grid:** Folders display live thumbnails of contained apps without item count limits. The preview grid automatically scales down icon sizes (2×2, 3×3, 4×4...) with clean cell alignment.
- **Folder Capsule & Running Preview:** When applications inside a closed folder are running, the folder displays a compact horizontal capsule preview for 1-click focus.
- **Folder Popover:** Clicking a folder deploys a full popover with large icons (52 pt), drag-and-drop reordering, and direct double-click inline renaming.
- **Drag-to-Merge:** Simply drag an application onto another to instantly group them into a new folder.

### 3. ⚡ Multi-Window Tracking & Dimmed Hidden Apps
- **Window Count Indicators:** Custom indicator dots reflect how many windows each running app has open:
  - 1 window: 1 centered dot.
  - 2 windows: 2 side-by-side dots.
  - 3 windows: 3 dots.
  - 4+ windows: 2 dots accompanied by a clean `+` badge (`MiniPlusShape`).
- **Dimmed Hidden/Minimized Apps:** When an app is hidden (`⌘H`) or minimized, its dock icon dims automatically (customizable opacity between 10% and 100%, default 50%) and subtly brightens on hover.

### 4. 🖱️ Advanced Mouse & Gesture Controls
- **Left-Click:** Launch or bring application to the foreground with an authentic bouncing animation (`BouncingModifier`).
- **Middle-Click (Scroll Wheel):** Instantly closes/terminates the targeted application (`NSRunningApplication.terminate()`) with an immediate exit animation. Works on dock items and sub-apps inside folders.
- **Right-Click Context Menus:** Full options to open, quit, keep in dock, rename folders, separate sections, or open settings.
- **Trash Can Integration:** Dedicated macOS trash item on the right supporting direct click to open, right-click to empty, and drag-and-drop to move files to trash.

### 5. 🚀 Foldy App Launcher (`AppLauncherView`)
- Anchored on the left of the dock with the official Foldy mascot logo.
- Opens an ultra-fast searchable drawer indexing all apps in `/Applications`, `/System/Applications`, and `~/Applications`.
- 1-click launch, Finder reveal (`⌘`-click or context menu), and quick pin to dock.

### 6. 🔄 Launch at Login (`SMAppService`)
- Modern, reliable macOS startup integration using Apple's official `SMAppService` API (no legacy launch daemons).
- Can be toggled on/off at any time in Settings.

### 7. 🎨 Foldy Mascot & Adaptive Menu Bar Icon
- Crisp high-resolution mascot branding.
- Dedicated macOS menu bar status item: built as a native Apple template image (`isTemplate = true`), it automatically adapts to **Dark Mode** (clean white monochrome) and **Light Mode** (clean black monochrome).

---

## 🖱️ Mouse & Shortcuts Controls

| Interaction | Target | Action |
| :--- | :--- | :--- |
| **Left Click** | Application | Launch or switch to application (with bounce animation) |
| **Left Click** | Folder | Open folder popover drawer |
| **Left Click** | Launcher (Foldy) | Open installed applications search popover |
| **Middle Click** | Application | Force-close application immediately (with exit animation) |
| **Middle Click** | App in Folder | Close specific sub-application from closed folder |
| **Right Click** | Any Item | Context menu (Keep in Dock, Quit, Rename, Remove) |
| **Right Click** | Dock Background | Open FoldyDock Settings, Add Separator, Add Folder |
| **Drag & Drop** | App over App | Merge applications into a folder |
| **Drag & Drop** | App horizontally | Reorder dock items or intra-folder items |
| **Drag & Drop** | File to Trash | Move dragged file to macOS Trash |
| **`⌘ ,`** | Shortcut | Open FoldyDock Settings window |

---

## 🛠️ Building & Running

### Prerequisites
- **macOS 14.0 Sonoma** or later (tested on macOS 14 & 15 Sequoia)
- **Swift 5.9+** toolchain or **Xcode 15+**

### Compile & Assemble the App Bundle
Use the automated build script to compile in Release mode and assemble `build/FoldyDock.app`:

```bash
./scripts/build_app.sh
```

### Compile & Launch Directly
To compile and automatically run FoldyDock:

```bash
./scripts/build_app.sh run
```

### Running Unit Tests
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

---

## 🗂️ Codebase Architecture

```
foldyDock/
├── Package.swift                    # SPM manifest (macOS 14 target)
├── scripts/
│   └── build_app.sh                 # Compilation, resource bundler & app launcher
├── Sources/FoldyDock/
│   ├── Main.swift                   # @main entry point, NSApplicationDelegate, menu bar item
│   ├── Models/
│   │   ├── DockItem.swift           # Unified model (.app, .folder, .separator)
│   │   ├── DockConfig.swift         # User configuration, size, autohide, paddings
│   │   └── DockHierarchyEngine.swift# Deterministic folder merge/dissolve & reorder logic
│   ├── Services/
│   │   ├── AppObserverService.swift # Running applications & window count tracking via AXUIElement
│   │   ├── AppDiscoveryService.swift# Fast async discovery of installed Mac applications
│   │   ├── DockPersistenceService.swift # Atomic JSON persistence in Application Support
│   │   ├── LaunchAtLoginService.swift   # macOS SMAppService startup manager
│   │   ├── LogoProvider.swift       # Mascot scaling & adaptive menu bar template provider
│   │   └── IconProvider.swift       # System app icon extraction & folder mini-grid rendering
│   ├── ViewModels/
│   │   └── DockViewModel.swift      # Central MVVM observable state & UI event dispatcher
│   ├── Views/
│   │   ├── DockContainerView.swift  # Main dock horizontal stack & padding layout
│   │   ├── DockItemView.swift       # Single dock item view with titles and badges
│   │   ├── FolderPopoverView.swift  # Expanded folder popover grid
│   │   ├── FolderIconGrid.swift     # Closed folder miniature icon grid
│   │   ├── ExpandedFolderBubbleView.swift # Capsule for folder running applications
│   │   ├── MultiWindowIndicatorView.swift # Dynamic multi-window dot indicators & plus shape
│   │   ├── AppLauncherView.swift    # Foldy icon launcher
│   │   ├── ApplicationsPopoverView.swift  # Searchable installed apps popover
│   │   ├── TrashItemView.swift      # Interactive Trash item with drop-to-delete
│   │   ├── FoldyDockSettingsView.swift    # Full settings control panel
│   │   ├── BouncingModifier.swift   # Spring physics launch bounce animation
│   │   └── MouseInteractionModifier.swift # Left, middle, and right click gesture handler
│   └── Window/
│       ├── DockPanel.swift          # Non-activating floating NSPanel (.canJoinAllSpaces)
│       ├── HotspotPanel.swift       # Edge hover detection panel for autohide trigger
│       ├── SettingsWindowController.swift # Singleton settings window manager
│       └── VisualEffectBackground.swift   # Frosted glass blur AppKit view wrapper
├── Tests/FoldyDockTests/            # Comprehensive unit test suite
└── logoFoldyDock.png, menuBarIcon.png, AppIcon.icns
```

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are very welcome!
Please check out **[`CONTRIBUTING.md`](CONTRIBUTING.md)** and review our ubiquitous domain vocabulary in **[`CONTEXT.md`](CONTEXT.md)** before opening a Pull Request.

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2026 Guillaume Murat.
