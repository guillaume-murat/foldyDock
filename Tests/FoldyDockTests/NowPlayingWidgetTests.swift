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

    @Test("NowPlayingScriptParser parses active playback correctly")
    func testScriptParserActivePlayback() {
        let output = """
        Playing
        Dans ma ville, on traîne
        Orelsan
        La fête est finie
        com.google.ios.youtubemusic
        YouTube Music
        87033
        """
        let state = NowPlayingScriptParser.parse(output: output)
        guard case .playing(let track) = state else {
            Issue.record("Expected playing state, got \(state)")
            return
        }

        #expect(track.title == "Dans ma ville, on traîne")
        #expect(track.artist == "Orelsan")
        #expect(track.album == "La fête est finie")
        #expect(track.bundleIdentifier == "com.google.ios.youtubemusic")
        #expect(track.pid == 87033)
    }

    @Test("NowPlayingScriptParser parses paused playback correctly")
    func testScriptParserPausedPlayback() {
        let output = """
        Paused
        Starboy
        The Weeknd
        Starboy
        com.apple.Music
        Music
        1234
        """
        let state = NowPlayingScriptParser.parse(output: output)
        guard case .paused(let track) = state else {
            Issue.record("Expected paused state, got \(state)")
            return
        }

        #expect(track.title == "Starboy")
        #expect(track.artist == "The Weeknd")
        #expect(track.album == "Starboy")
        #expect(track.bundleIdentifier == "com.apple.Music")
        #expect(track.pid == 1234)
    }

    @Test("NowPlayingScriptParser handles idle and empty responses")
    func testScriptParserIdleAndEmpty() {
        #expect(NowPlayingScriptParser.parse(output: "IDLE") == .idle)
        #expect(NowPlayingScriptParser.parse(output: "idle\n") == .idle)
        #expect(NowPlayingScriptParser.parse(output: "") == .idle)
        #expect(NowPlayingScriptParser.parse(output: "   ") == .idle)
    }

    @Test("NowPlayingScriptParser handles missing artist gracefully with appName fallback")
    func testScriptParserArtistFallback() {
        let output = """
        Playing
        Audio Stream

        Stream Album
        com.brave.Browser
        Brave Browser
        5678
        """
        let state = NowPlayingScriptParser.parse(output: output)
        guard case .playing(let track) = state else {
            Issue.record("Expected playing state, got \(state)")
            return
        }

        #expect(track.title == "Audio Stream")
        #expect(track.artist == "Brave Browser")
    }
}

