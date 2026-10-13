import Foundation
import Combine

public protocol NowPlayingServiceProviding: AnyObject {
    var statePublisher: AnyPublisher<NowPlayingState, Never> { get }
    var currentState: NowPlayingState { get }
    func playPause()
    func nextTrack()
    func previousTrack()
    func activateSource()
}

public final class NoOpNowPlayingService: NowPlayingServiceProviding {
    public static let shared = NoOpNowPlayingService()

    public init() {}

    public var statePublisher: AnyPublisher<NowPlayingState, Never> {
        Just(.idle).eraseToAnyPublisher()
    }

    public var currentState: NowPlayingState { .idle }

    public func playPause() {}
    public func nextTrack() {}
    public func previousTrack() {}
    public func activateSource() {}
}
