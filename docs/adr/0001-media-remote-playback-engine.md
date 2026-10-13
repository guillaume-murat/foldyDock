# 1. Use MediaRemote for universal Now Playing playback observation and transport control

Date: 2026-10-13

## Context

FoldyDock requires a native music widget embedded in the dock capsule to display the currently playing track (artwork, title, artist, playback state), issue transport controls (Previous, Play/Pause, Next), and bring the source application to the foreground upon click across all audio sources (Apple Music, Spotify, browsers playing YouTube/web players, Podcasts, VLC, etc.).

## Decision

We use Apple's private `MediaRemote.framework` via dynamic loading (`dlopen`/`dlsym`) wrapped in a protocol-driven provider service (`NowPlayingServiceProviding`).

## Why

Apple provides no public macOS API for third-party utilities to observe system-wide playback metadata or control arbitrary media sources.

1. **AppleScript (`osascript`)**: Requires requesting intrusive per-application Automation permissions (`NSAppleEventsUsageDescription`) for every individual music app, fails completely for web browsers or non-scriptable players, and cannot listen to real-time playback notifications without expensive timer polling.
2. **`MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`**: Only designed for applications publishing their own internal audio sessions, not for observing or intercepting audio sessions emitted by other system applications.
3. **`MediaRemote`**:
   - Zero user permission prompts or entitlements required.
   - Universally supports Apple Music, Spotify, YouTube/web playback in Safari/Chrome/Firefox/Arc, and all media players.
   - Dispatches system push notifications when playback state or track metadata changes (`kMRMediaRemoteNowPlayingInfoDidChangeNotification`).
   - Directly exposes `MRMediaRemoteGetNowPlayingApplicationPID`, providing the exact `NSRunningApplication` PID needed to activate the source window on click.

Wrapping the implementation behind `NowPlayingServiceProviding` enables isolated, deterministic unit testing in `DockViewModel` without requiring system daemons during test runs.
