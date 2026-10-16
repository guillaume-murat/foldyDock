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

**FoldyDock** is a lightweight, native macOS dock alternative with iOS-style folders, music playback control, and smart window management.  
*FoldyDock est un dock flottant natif et léger pour macOS, intégrant des dossiers façon iOS, un contrôle musical universel et une gestion avancée des fenêtres.*

- 📂 **iOS-Style Folders / Dossiers iOS** : Miniatures réactives, popover dédié et fusion par glisser-déposer.
- 🎵 **Now Playing Widget / Widget Musical** : Contrôle universel de la musique (YouTube Music, Spotify, Apple Music...) avec boutons play/pause/skip.
- 🗂️ **Window Picker Popover / Sélecteur de Fenêtres** : Survol d'une icône (2+ fenêtres) pour lister et sélectionner directement la fenêtre souhaitée.
- 🌗 **Light & Dark Mode / Mode Clair & Sombre** : Thème adaptatif (Système, Clair, Sombre) avec contraste optimal sur tous les éléments et popovers.
- 🔄 **Window Cycling / Rotation du Focus** : Clics successifs sur l'icône pour alterner entre les fenêtres d'une même application.
- 🪟 **Frosted Glass / Verre Dépoli** : Barre flottante avec flou natif (`NSVisualEffectView`) sans vol de focus.
- 🌐 **Multi-Space** : Visibilité fluide sur tous les Bureaux virtuels (`.canJoinAllSpaces`).
- ⚡ **Multi-Window Dots / Indicateurs de Fenêtres** : Pastilles indiquant le nombre exact de fenêtres ouvertes par application.
- 🖱️ **Middle-Click Quit / Fermeture Rapide** : Clic molette pour quitter instantanément une application.
- 🚀 **App Launcher / Lanceur d'Apps** : Recherche et lancement ultra-rapides de toutes les applications du Mac.
- ⚙️ **Settings (`⌘,`) / Réglages** : Personnalisation en direct des tailles, marges, masque automatique et lancement au démarrage.

---

## ✨ Key Features / Fonctionnalités

### 1. 🎵 Now Playing Widget / Widget Musical
- **Universal Detection**: Detects playing media across macOS 15.4+, including YouTube Music, Spotify, and Apple Music.  
  *Détection universelle de la musique compatible macOS 15.4+, incluant YouTube Music, Spotify et Apple Music.*
- **Controls & Opener**: Play/Pause, Next/Previous controls, and 1-click app activation.  
  *Boutons Lecture/Pause, Suivant/Précédent, et clic pour ouvrir l'application en cours.*
- **Adaptive Artwork**: Displays album cover or official app icon.  
  *Affichage automatique de la pochette ou de l'icône de l'application source.*

### 2. 🔄 Window Cycling & Hover Picker / Rotation & Sélecteur de Fenêtres
- **Hover Window Picker**: Hovering an application with 2+ open windows displays a frosted glass popover listing all window titles and states (active/minimized) for 1-click selection.  
  *Sélecteur de fenêtres au survol (dès 2 fenêtres ouvertes) listant les titres et états (active/minimisée) pour cibler une fenêtre en un clic.*
- **Round-Robin Focus**: Sequential cycling through all open windows of an app on dock icon clicks.  
  *Rotation séquentielle du focus entre les fenêtres ouvertes à chaque clic sur l'icône du dock.*
- **Restore Minimized**: Automatically unminimizes windows when reached in the cycle or selected in the picker.  
  *Restaure automatiquement les fenêtres minimisées lorsqu'elles sont sélectionnées ou atteintes dans le cycle.*
- **Multi-Space Support**: Automatically switches to the virtual Desktop of the target window.  
  *Bascule automatique sur le Bureau virtuel (Space) hébergeant la fenêtre ciblée.*

### 3. 📂 iOS-Style App Folders / Dossiers d'Applications iOS
- **Live Miniatures Grid**: Dynamic miniature icons (2×2, 3×3, 4×4...) for all contained apps.  
  *Miniatures dynamiques en grille pour visualiser le contenu des dossiers fermés.*
- **Drag-to-Merge**: Drop an application over another to instantly create a folder.  
  *Glissez une app sur une autre pour créer instantanément un dossier.*
- **Folder Popover**: Expandable drawer with large icons, drag-and-drop reordering, and inline renaming.  
  *Tiroir d'applications avec icônes agrandies, réorganisation et renommage rapide.*

### 4. 🪟 Native Frosted Glass Dock / Dock Flottant en Verre Dépoli
- **Light & Dark Themes**: Follows macOS system appearance automatically or forces Light / Dark mode across the dock, music widget, folders, and popovers.  
  *Thèmes Clair & Sombre : suit automatiquement l'apparence de macOS ou force le mode Clair / Sombre sur le dock, le widget musical, les dossiers et les popovers.*
- **Floating Panel**: Hardware-accelerated blur (`NSVisualEffectView`) at `.floating` level without stealing keyboard focus.  
  *Panneau flottant avec flou accéléré matériellement sans jamais voler le focus clavier.*
- **All Spaces**: Visible across all virtual desktops and full-screen environments.  
  *Actif sur tous les Bureaux virtuels (Spaces) et modes plein écran.*

### 5. ⚡ Smart Window Indicators / Indicateurs de Fenêtres
- **Multi-Dot Badges**: 1 dot (1 window), 2 dots (2 windows), 3 dots (3 windows), or `2 dots +` (4+ windows).  
  *Pastilles dynamiques indiquant le nombre de fenêtres ouvertes.*
- **Dimmed Hidden Apps**: Hidden (`⌘H`) or minimized apps automatically dim with hover highlight.  
  *Atténuation automatique des applications masquées ou minimisées.*

### 6. 🖱️ Mouse Controls & Trash / Contrôles Souris & Corbeille
- **Left-Click**: Launch or focus application with native spring bounce animation.  
  *Lancement ou focus avec animation de rebond fluide.*
- **Middle-Click**: Instantly terminate applications directly from the dock or folders.  
  *Clic molette pour fermer instantanément une application.*
- **Trash Integration**: Dedicated trash icon with file drop-to-delete and right-click to empty.  
  *Corbeille intégrée avec glisser-déposer pour supprimer des fichiers.*

### 7. 🚀 Launcher & Settings / Lanceur & Réglages
- **Foldy Launcher**: Search drawer indexing all applications on your Mac.  
  *Tiroir de recherche rapide pour toutes les applications installées.*
- **Settings Panel (`⌘,`)**: Real-time adjustment of dock height, icon sizes, autohide, and launch at login.  
  *Panneau complet pour ajuster la taille, l'automasquage et le lancement au démarrage.*

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
│   │   ├── NowPlayingState.swift    # Now Playing state model (MediaTrack, Play/Pause/Idle)
│   │   └── DockHierarchyEngine.swift# Deterministic folder merge/dissolve & reorder logic
│   ├── Services/
│   │   ├── AppObserverService.swift # Running applications & window count tracking via AXUIElement
│   │   ├── WindowCycleHelper.swift  # Deterministic round-robin window focus rotation
│   │   ├── MediaRemoteNowPlayingService.swift # Universal media detection & control bridge
│   │   ├── NowPlayingScriptParser.swift       # Resilient script output parser for Now Playing
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
│   │   ├── NowPlayingWidget.swift   # Embedded media capsule with controls & app opener
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
