import Foundation
import Combine
import AppKit

public final class MediaRemoteNowPlayingService: NowPlayingServiceProviding {
    public static let shared = MediaRemoteNowPlayingService()

    private let subject = CurrentValueSubject<NowPlayingState, Never>(.idle)

    public var statePublisher: AnyPublisher<NowPlayingState, Never> {
        subject.eraseToAnyPublisher()
    }

    public var currentState: NowPlayingState {
        subject.value
    }

    private enum MediaRemoteCommand: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias MRGetInfo = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias MRRegister = @convention(c) (DispatchQueue) -> Void
    private typealias MRSendCommand = @convention(c) (Int32, AnyObject?) -> Bool
    private typealias MRGetPID = @convention(c) (DispatchQueue, @escaping (pid_t) -> Void) -> Void

    private var mrGetInfo: MRGetInfo?
    private var mrRegister: MRRegister?
    private var mrSendCommand: MRSendCommand?
    private var mrGetPID: MRGetPID?

    private var currentPID: pid_t?
    private var pollTimer: Timer?
    private var isFetching: Bool = false
    private let serialQueue = DispatchQueue(label: "com.foldydock.mediaremote.serial", qos: .userInitiated)

    public init() {
        loadMediaRemoteSymbols()
        registerForNotifications()
        refreshNowPlaying()
        startPeriodicCheck()
    }

    private func loadMediaRemoteSymbols() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return
        }

        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mrGetInfo = unsafeBitCast(sym, to: MRGetInfo.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            mrRegister = unsafeBitCast(sym, to: MRRegister.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(sym, to: MRSendCommand.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            mrGetPID = unsafeBitCast(sym, to: MRGetPID.self)
        }
    }

    private func registerForNotifications() {
        mrRegister?(DispatchQueue.main)

        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingPlaybackStateDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"
        ]

        for name in notificationNames {
            CFNotificationCenterAddObserver(
                darwinCenter,
                observer,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    let service = Unmanaged<MediaRemoteNowPlayingService>.fromOpaque(observer).takeUnretainedValue()
                    DispatchQueue.main.async {
                        service.refreshNowPlaying()
                    }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    @objc public func refreshNowPlaying() {
        serialQueue.async { [weak self] in
            guard let self else { return }
            if self.isFetching { return }
            self.isFetching = true

            self.fetchViaOsascript { [weak self] scriptState in
                guard let self else { return }
                defer {
                    self.serialQueue.async {
                        self.isFetching = false
                    }
                }

                if case .idle = scriptState, let mrGetInfo = self.mrGetInfo {
                    // Fallback to legacy in-process MediaRemote API if script returned idle
                    mrGetInfo(DispatchQueue.main) { [weak self] dict in
                        guard let self else { return }
                        if let dict = dict as? [String: Any], !dict.isEmpty {
                            self.parseLegacyDict(dict)
                        } else {
                            self.currentPID = nil
                            self.subject.send(.idle)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.currentPID = scriptState.pid
                        self.subject.send(scriptState)
                    }
                }
            }
        }
    }

    private func fetchViaOsascript(completion: @escaping (NowPlayingState) -> Void) {
        let script = """
        use scripting additions
        use framework "/System/Library/PrivateFrameworks/MediaRemote.framework"

        set MRNowPlayingRequest to current application's NSClassFromString("MRNowPlayingRequest")

        if MRNowPlayingRequest is missing value or MRNowPlayingRequest's localNowPlayingItem() is missing value then
            return "IDLE"
        end if

        if MRNowPlayingRequest's localIsPlaying() then
            set status to "Playing"
        else
            set status to "Paused"
        end if

        set infoDict to MRNowPlayingRequest's localNowPlayingItem()'s nowPlayingInfo()
        set bundleObj to MRNowPlayingRequest's localNowPlayingPlayerPath()'s client()

        set trackTitle to ""
        set trackArtist to ""
        set trackAlbum to ""
        set bundleId to ""
        set appName to ""
        set pid to 0

        try
            set trackTitle to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoTitle") as text
        end try
        try
            set trackArtist to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoArtist") as text
        end try
        try
            set trackAlbum to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoAlbum") as text
        end try
        try
            set bundleId to (bundleObj's bundleIdentifier()) as text
        end try
        try
            set appName to (bundleObj's displayName()) as text
        end try
        try
            set pid to (bundleObj's processIdentifier()) as integer
        end try

        return status & linefeed & trackTitle & linefeed & trackArtist & linefeed & trackAlbum & linefeed & bundleId & linefeed & appName & linefeed & pid
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let state = NowPlayingScriptParser.parse(output: output)
            completion(state)
        } catch {
            completion(.idle)
        }
    }

    private func parseLegacyDict(_ dict: [String: Any]) {
        let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String
            ?? dict["title"] as? String
        let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String
            ?? dict["artist"] as? String
        let artworkData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            ?? dict["artworkData"] as? Data

        let playbackRate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
            ?? (dict["playbackRate"] as? NSNumber)?.doubleValue
            ?? 0.0

        let isPlaying = playbackRate > 0.0

        if let title, !title.isEmpty {
            let resolvedArtist = if let artist, !artist.isEmpty { artist } else { "Unknown Artist" }
            let track = MediaTrack(
                title: title,
                artist: resolvedArtist,
                artworkData: artworkData,
                pid: self.currentPID
            )
            self.subject.send(isPlaying ? .playing(track) : .paused(track))
        } else if isPlaying {
            let track = MediaTrack(
                title: "Playing Media",
                artist: artist ?? "macOS Audio",
                artworkData: artworkData,
                pid: self.currentPID
            )
            self.subject.send(.playing(track))
        } else {
            self.currentPID = nil
            self.subject.send(.idle)
        }
    }

    private func startPeriodicCheck() {
        // Fallback safety poll for applications that defer Darwin notifications
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshNowPlaying()
        }
    }

    deinit {
        pollTimer?.invalidate()
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(darwinCenter, observer)
    }

    // MARK: - Transport Commands
    private func postMediaKey(_ key: Int32) {
        func doKey(down: Bool) {
            let flags = down ? 0xa00 : 0xb00
            let data1 = (Int(key) << 16) | (flags & 0xff00)
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }

    private func sendCommand(_ command: MediaRemoteCommand) {
        _ = mrSendCommand?(command.rawValue, nil)

        switch command {
        case .togglePlayPause, .play, .pause:
            postMediaKey(16) // NX_KEYTYPE_PLAY
        case .nextTrack:
            postMediaKey(19) // NX_KEYTYPE_FAST (Next)
        case .previousTrack:
            postMediaKey(20) // NX_KEYTYPE_REWIND (Previous)
        case .stop:
            postMediaKey(16)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    public func playPause() {
        sendCommand(.togglePlayPause)
    }

    public func nextTrack() {
        sendCommand(.nextTrack)
    }

    public func previousTrack() {
        sendCommand(.previousTrack)
    }

    private func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApp?.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: - Source Activation
    public func activateSource() {
        let targetPID = currentPID ?? currentState.pid
        if let targetPID, targetPID > 0, let app = NSRunningApplication(processIdentifier: targetPID) {
            activateApp(app)
            return
        }

        if let bundleId = currentState.bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            activateApp(app)
            return
        }

        if let bundleId = currentState.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        // In idle state with no active stream, try activating an already running media app
        let bundleIds = [
            "com.google.ios.youtubemusic",
            "com.apple.Music",
            "com.spotify.client"
        ]
        for bundleId in bundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                activateApp(app)
                return
            }
        }
    }
}
