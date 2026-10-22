# 4. Stable designated requirement for ad-hoc signed builds

Date: 2026-10-22

## Context

FoldyDock needs the macOS Accessibility permission (TCC) for window cycling and the Window Picker Popover. The app is ad-hoc signed by `scripts/build_app.sh`. An ad-hoc signature's default designated requirement is the binary's `cdhash`, which changes on every build: after each rebuild, TCC no longer matches the app, the old entry stays checked in System Settings but is ignored, and the permission must be removed and granted again by hand.

## Decision

Sign with an explicit designated requirement on the bundle identifier:

```bash
codesign --force --deep --sign - --identifier "com.foldydock.FoldyDock" \
  -r='designated => identifier "com.foldydock.FoldyDock"' FoldyDock.app
```

`FOLDYDOCK_SIGN_IDENTITY` can name a real code-signing certificate instead of `-`. At launch, `AccessibilityPermissionService` alerts when the permission is missing and can reset a stale TCC entry (`tccutil reset Accessibility com.foldydock.FoldyDock`); the check can be disabled in Settings.

## Why

1. The permission survives rebuilds, so the window features keep working during development.
2. No paid Developer ID certificate is required.

## Trade-off

Any binary signed with this identifier satisfies the requirement and inherits the Accessibility permission. Accepted for a locally built, open-source utility; use `FOLDYDOCK_SIGN_IDENTITY` with a real certificate to restore a strong requirement.
