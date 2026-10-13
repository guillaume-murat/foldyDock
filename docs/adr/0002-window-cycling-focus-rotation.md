# 2. Window cycling and focus rotation for multi-window applications

Date: 2026-10-13

## Context

When an application has multiple open windows (e.g. Safari tabs in separate windows, TextEdit documents, Finder windows), users expect clicking the dock item to cycle focus through each open window.

## Decision

We implement sequential round-robin window cycling using the macOS Accessibility API (`AXUIElement`) within `AppObserverService`:
1. **Activation gate**: When the clicked application is in the background or hidden, the initial click brings the application to the foreground with its current active window. Window cycling triggers exclusively when the application is already the frontmost active application.
2. **Filtering**: Window cycling inspects `kAXWindowsAttribute` and filters for standard user document windows (`kAXWindowRole` and `kAXStandardWindowSubrole` / `kAXDialogSubrole`), ignoring floating inspector panels, palettes, and auxiliary helper windows.
3. **Round-robin rotation**: Determines the index of the currently focused window (`kAXFocusedWindowAttribute`) and rotates to `(currentIndex + 1) % eligibleWindows.count`.
4. **Minimized restoration**: If the target window is minimized (`kAXMinimizedAttribute`), it is unminimized (`kCFBooleanFalse`) and raised to the foreground.
5. **Multi-Space support**: The target window is raised (`kAXRaiseAction`), set to main/focused, and cooperative activation is yielded with an AppleScript activate signal to trigger macOS Mission Control Space switching if the window lives on another virtual desktop.

## Why

1. **Accessibility API (`AXUIElement`)**: Operates directly at the Window Server level with sub-millisecond responsiveness and fine-grained control over window minimization and focus state.
2. **Predictable user experience**: Cycling only when already frontmost prevents skipping the active window upon returning to an app.
3. **Full multi-window visibility**: Restoring minimized windows ensures windows stored in the dock aren't orphaned from the user's workflow.
