import Foundation

public struct MediaTrack: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkData: Data?
    public let pid: pid_t?
    public let bundleIdentifier: String?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        artworkData: Data? = nil,
        pid: pid_t? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum NowPlayingState: Equatable, Sendable {
    case idle
    case playing(MediaTrack)
    case paused(MediaTrack)

    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    public var track: MediaTrack? {
        switch self {
        case .idle: return nil
        case .playing(let track), .paused(let track): return track
        }
    }

    public var title: String? { track?.title }
    public var artist: String? { track?.artist }
    public var album: String? { track?.album }
    public var artworkData: Data? { track?.artworkData }
    public var pid: pid_t? { track?.pid }
    public var bundleIdentifier: String? { track?.bundleIdentifier }
}
