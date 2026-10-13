# 3. Window picker popover on hover for multi-window applications

Date: 2026-10-13

## Context

When an application has multiple open windows, clicking the dock icon to cycle blindly through windows can be inconvenient or unreliable depending on third-party application UI thread responsiveness (e.g. Gecko/WebKit async menu updates). Users need an immediate visual overview of all open windows for an application to select and focus the exact window they want with a single click.

## Decision

We introduce a **Window Picker Popover** displayed upon hovering an application dock icon with 2 or more open windows:
1. **Trigger & Hover Delay**: Controlled by a configurable timer (`windowPickerHoverDelay`, default 350 ms, adjustable in preferences) to avoid accidental popups during rapid cursor transit across the dock.
2. **Visual Presentation**: A vertical frosted glass popover displaying the titles of all open windows, with visual badges indicating the currently focused window (blue dot / checkmark) and minimized status.
3. **Multi-Space and Minimized Activation**: Selecting a window from the popover brings it to the foreground, automatically unminimizes it if minimized, and switches virtual desktops (Spaces) via macOS Mission Control.
4. **Graceful Dismissal**: The popover remains open while hovering either the dock icon or the popover, with a short buffer tolerance (~200 ms) allowing smooth cursor movement between the two. Clicking an item or clicking outside dismisses the popover.
5. **Direct Click Preservation**: Clicking the dock icon directly bypasses the popover, activates the application, and closes the popover immediately.

## Why

1. **Explicit Selection vs. Blind Rotation**: Users see the exact names of open documents and tabs, eliminating guesswork and repeated clicks.
2. **Native macOS Aesthetics**: Frosted glass materials conform to FoldyDock's design language without requiring heavy screen recording permissions (ScreenCaptureKit).
3. **Customizability**: Configurable hover delay and toggle enable users to tailor the responsiveness to their workflow.
