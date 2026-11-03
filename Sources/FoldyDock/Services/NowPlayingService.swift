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
