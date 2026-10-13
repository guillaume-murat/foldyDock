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
        guard let mrGetInfo else { return }

        // Query active PID
        mrGetPID?(DispatchQueue.main) { [weak self] pid in
            if pid > 0 {
                self?.currentPID = pid
            }
        }

        mrGetInfo(DispatchQueue.main) { [weak self] dict in
            guard let self else { return }

            guard let dict = dict as? [String: Any], !dict.isEmpty else {
                self.currentPID = nil
                self.subject.send(.idle)
                return
            }

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
    }

    private func startPeriodicCheck() {
        // Fallback safety poll for applications that defer Darwin notifications
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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
    private func sendCommand(_ command: MediaRemoteCommand) {
        _ = mrSendCommand?(command.rawValue, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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

    // MARK: - Source Activation
    public func activateSource() {
        let targetPID = currentPID ?? currentState.pid
        if let targetPID, targetPID > 0, let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate()
            return
        }

        // In idle state with no active stream, try activating an already running media app
        let bundleIds = ["com.apple.Music", "com.spotify.client"]
        for bundleId in bundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate()
                return
            }
        }
    }
}
