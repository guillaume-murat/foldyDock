import Foundation

public struct MediaTrack: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let artworkData: Data?
    public let pid: pid_t?

    public init(
        title: String,
        artist: String,
        artworkData: Data? = nil,
        pid: pid_t? = nil
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.pid = pid
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
    public var artworkData: Data? { track?.artworkData }
    public var pid: pid_t? { track?.pid }
}
