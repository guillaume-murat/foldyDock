import Testing
import Foundation
import Combine
@testable import FoldyDock

// Mock implementation of NowPlayingServiceProviding for isolated deterministic testing
final class MockNowPlayingService: NowPlayingServiceProviding {
    private let subject = CurrentValueSubject<NowPlayingState, Never>(.idle)

    var statePublisher: AnyPublisher<NowPlayingState, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentState: NowPlayingState {
        subject.value
    }

    var playPauseCalled = false
    var nextTrackCalled = false
    var previousTrackCalled = false
    var activateSourceCalled = false

    func emit(state: NowPlayingState) {
        subject.send(state)
    }

    func playPause() {
        playPauseCalled = true
    }

    func nextTrack() {
        nextTrackCalled = true
    }

    func previousTrack() {
        previousTrackCalled = true
    }

    func activateSource() {
        activateSourceCalled = true
    }
}

@Suite("NowPlayingWidgetTests")
@MainActor
struct NowPlayingWidgetTests {
    @Test("DockViewModel initializes with NowPlayingService and defaults to idle state")
    func testInitializationAndDefaultIdleState() {
        let mockService = MockNowPlayingService()
        let viewModel = DockViewModel(nowPlayingService: mockService)

        #expect(viewModel.nowPlayingState == .idle)
        #expect(viewModel.config.showNowPlayingWidget == true)
    }

    @Test("DockViewModel updates nowPlayingState when service emits new state")
    func testStateUpdatesFromService() {
        let mockService = MockNowPlayingService()
        let viewModel = DockViewModel(nowPlayingService: mockService)

        let track = MediaTrack(title: "Starboy", artist: "The Weeknd", artworkData: nil, pid: 1234)
        mockService.emit(state: .playing(track))
        #expect(viewModel.nowPlayingState == .playing(track))

        mockService.emit(state: .paused(track))
        #expect(viewModel.nowPlayingState == .paused(track))

        mockService.emit(state: .idle)
        #expect(viewModel.nowPlayingState == .idle)
    }

    @Test("DockViewModel toggles showNowPlayingWidget configuration")
    func testToggleNowPlayingWidget() {
        let mockService = MockNowPlayingService()
        let viewModel = DockViewModel(nowPlayingService: mockService)

        #expect(viewModel.config.showNowPlayingWidget == true)
        viewModel.toggleNowPlayingWidget()
        #expect(viewModel.config.showNowPlayingWidget == false)
        viewModel.toggleNowPlayingWidget()
        #expect(viewModel.config.showNowPlayingWidget == true)
    }

    @Test("DockViewModel delegates transport actions to NowPlayingService")
    func testTransportActionsDelegation() {
        let mockService = MockNowPlayingService()
        let viewModel = DockViewModel(nowPlayingService: mockService)

        viewModel.togglePlayPause()
        #expect(mockService.playPauseCalled == true)

        viewModel.nextTrack()
        #expect(mockService.nextTrackCalled == true)

        viewModel.previousTrack()
        #expect(mockService.previousTrackCalled == true)

        viewModel.activateNowPlayingSource()
        #expect(mockService.activateSourceCalled == true)
    }
}
