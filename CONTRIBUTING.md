# Contributing to FoldyDock

Thank you for your interest in contributing to **FoldyDock**! 🎉

FoldyDock is an open-source, native macOS floating dock written in Swift and SwiftUI, designed to bring iOS-style app folders, smooth autohide, multi-window tracking, and deep desktop customization to macOS.

---

## 🧭 Project Architecture & Guidelines

Before submitting PRs or refactoring components, please consult:
- **[`CONTEXT.md`](CONTEXT.md)**: Defines the core ubiquitous domain language (`DockItem`, `Folder`, `DockHierarchy`, `Folder Capsule`, `Pinned Application`, `Drop Placement`, `Launch at Login`). Please use these exact terms in code and documentation.
- **`Sources/FoldyDock/`**:
  - `Models/`: Data structures (`DockItem`, `DockConfig`, `DockHierarchyEngine`).
  - `Services/`: System integrations (`AppObserverService`, `AppDiscoveryService`, `DockPersistenceService`, `LaunchAtLoginService`, `LogoProvider`, `IconProvider`).
  - `ViewModels/`: Presentation state (`DockViewModel`).
  - `Views/`: SwiftUI components (`DockContainerView`, `DockItemView`, `FolderPopoverView`, `FolderIconGrid`, `ExpandedFolderBubbleView`, `FoldyDockSettingsView`, `AppLauncherView`).
  - `Window/`: AppKit windowing wrappers (`DockPanel`, `HotspotPanel`, `SettingsWindowController`, `VisualEffectBackground`).

---

## 🛠️ Development Setup

### Prerequisites
- macOS 14.0 (Sonoma) or higher
- Xcode 15+ or Swift 5.9+ toolchain

### Building and Running Locally
Clone the repository:
```bash
git clone https://github.com/guillaumeslash/folderDock.git
cd folderDock
```

Compile and package the application bundle (`FoldyDock.app` in `build/`):
```bash
./scripts/build_app.sh
```

Compile and run directly:
```bash
./scripts/build_app.sh run
```

### Running Unit Tests
If using Xcode:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

---

## 📋 Pull Request Process

1. **Fork & Branch**: Create a feature or bugfix branch from `main` (e.g. `feat/my-feature` or `fix/issue-description`).
2. **Coding Standards**:
   - Write modern, idiomatic Swift.
   - Annotate UI and ViewModel classes with `@MainActor` where appropriate.
   - Ensure AppKit / SwiftUI interactions do not block the main thread.
   - Keep module boundaries clean (delegate collection mutations to `DockHierarchyEngine`).
3. **Commit Messages**: Follow [Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat:`, `fix:`, `refactor:`, `docs:`, `test:`).
4. **Test**: Ensure the app compiles cleanly with `./scripts/build_app.sh` and existing features work as expected.
5. **Open PR**: Submit your PR with a clear summary of changes, rationale, and screenshots/GIFs for UI changes.

---

## 🐛 Bug Reports & Feature Requests

Please open an issue on GitHub with:
- macOS version and architecture (Apple Silicon / Intel).
- Clear reproduction steps.
- Expected vs actual behavior.
- Screenshots or console logs if applicable.

---

## 📄 License

By contributing to FoldyDock, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
