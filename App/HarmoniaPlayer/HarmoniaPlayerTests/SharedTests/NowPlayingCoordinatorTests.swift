//
//  NowPlayingCoordinatorTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Slice 9-L: NowPlayingCoordinator wiring tests.
//
//  TEST STRATEGY
//  -------------
//  AppState is NOT instantiated in these tests. The coordinator is
//  constructed directly with:
//    - a `FakeNowPlayingService` for the push-side recording surface
//    - two local `PassthroughSubject`s impersonating AppState's
//      `$currentTrack` and `$playbackState` publishers
//    - inline closure recorders for `currentTimeProvider` and the
//      seven action closures
//
//  Each test drives the coordinator the same way AppState would in
//  production — by sending a value through a subject or by invoking
//  one of the pull-side callbacks the coordinator has assigned to
//  the service — and asserts on the recorded side effects.
//
//  This keeps the coordinator's contract surface small and explicit:
//  it only knows about the protocol abstractions it was constructed
//  with, never about AppState.
//

import XCTest
import Combine
@testable import Harmonia_Player

@MainActor
final class NowPlayingCoordinatorTests: XCTestCase {

    // MARK: - Recorders & subjects

    private var fakeService: FakeNowPlayingService!
    private var trackSubject: PassthroughSubject<Track?, Never>!
    private var stateSubject: PassthroughSubject<PlaybackState, Never>!

    /// Backing store for `currentTimeProvider`; tests mutate this to
    /// control what the coordinator reads when re-anchoring elapsed
    /// time on playback-state events.
    private var stubbedCurrentTime: TimeInterval = 0

    private var playCallCount = 0
    private var pauseCallCount = 0
    private var stopCallCount = 0
    private var nextCallCount = 0
    private var previousCallCount = 0
    private var togglePlayPauseCallCount = 0

    private var seekArgsHistory: [TimeInterval] = []

    private var sut: NowPlayingCoordinator!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        fakeService = FakeNowPlayingService()
        trackSubject = PassthroughSubject<Track?, Never>()
        stateSubject = PassthroughSubject<PlaybackState, Never>()
        stubbedCurrentTime = 0
        playCallCount = 0
        pauseCallCount = 0
        stopCallCount = 0
        nextCallCount = 0
        previousCallCount = 0
        togglePlayPauseCallCount = 0
        seekArgsHistory = []

        sut = NowPlayingCoordinator(
            service: fakeService,
            currentTrackPublisher: trackSubject.eraseToAnyPublisher(),
            playbackStatePublisher: stateSubject.eraseToAnyPublisher(),
            currentTimeProvider: { [weak self] in self?.stubbedCurrentTime ?? 0 },
            play: { [weak self] in self?.playCallCount += 1 },
            pause: { [weak self] in self?.pauseCallCount += 1 },
            stop: { [weak self] in self?.stopCallCount += 1 },
            seek: { [weak self] seconds in self?.seekArgsHistory.append(seconds) },
            next: { [weak self] in self?.nextCallCount += 1 },
            previous: { [weak self] in self?.previousCallCount += 1 },
            togglePlayPause: { [weak self] in self?.togglePlayPauseCallCount += 1 }
        )
    }

    override func tearDown() async throws {
        sut = nil
        fakeService = nil
        trackSubject = nil
        stateSubject = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeTrack(
        title: String = "Test Track",
        artist: String = "Test Artist",
        duration: TimeInterval = 180
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).mp3"),
            title: title,
            artist: artist,
            duration: duration
        )
    }

    /// Yields long enough for Combine `.receive(on: RunLoop.main)`
    /// hops to deliver synchronously to the sink.
    private func awaitPublishers() async {
        await Task.yield()
        await Task.yield()
    }

    // MARK: - Push: track change

    func testCoordinator_OnTrackChange_CallsUpdateCurrentTrack() async {
        let track = makeTrack(title: "New Song")

        trackSubject.send(track)
        await awaitPublishers()

        XCTAssertEqual(fakeService.updateCurrentTrackCallCount, 1)
        XCTAssertEqual(fakeService.lastUpdatedTrack??.title, "New Song")
    }

    func testCoordinator_OnTrackChangeToNil_CallsClear() async {
        trackSubject.send(makeTrack())
        await awaitPublishers()
        let baseline = fakeService.clearCallCount

        trackSubject.send(nil)
        await awaitPublishers()

        XCTAssertEqual(fakeService.clearCallCount, baseline + 1)
    }

    func testCoordinator_OnTrackChange_PushesElapsedTimeZero() async {
        trackSubject.send(makeTrack())
        await awaitPublishers()

        XCTAssertGreaterThanOrEqual(fakeService.updateElapsedTimeCallCount, 1)
        XCTAssertEqual(fakeService.updatedElapsedHistory.first, 0)
    }

    // MARK: - Push: playback state change

    func testCoordinator_OnPlay_UpdatesPlaybackState() async {
        stateSubject.send(.paused)
        await awaitPublishers()
        let baseline = fakeService.updatePlaybackStateCallCount

        stateSubject.send(.playing)
        await awaitPublishers()

        XCTAssertGreaterThan(fakeService.updatePlaybackStateCallCount, baseline)
        XCTAssertEqual(fakeService.lastUpdatedState, .playing)
        XCTAssertEqual(fakeService.lastUpdatedRate, 1.0)
    }

    func testCoordinator_OnPause_UpdatesPlaybackState() async {
        stateSubject.send(.playing)
        await awaitPublishers()
        let baseline = fakeService.updatePlaybackStateCallCount

        stateSubject.send(.paused)
        await awaitPublishers()

        XCTAssertGreaterThan(fakeService.updatePlaybackStateCallCount, baseline)
        XCTAssertEqual(fakeService.lastUpdatedState, .paused)
        XCTAssertEqual(fakeService.lastUpdatedRate, 0.0)
    }

    func testCoordinator_OnPlaybackStateChange_PushesCurrentElapsedTime() async {
        stubbedCurrentTime = 12.3
        stateSubject.send(.playing)
        await awaitPublishers()
        let baselineHistoryCount = fakeService.updatedElapsedHistory.count

        stateSubject.send(.paused)
        await awaitPublishers()

        XCTAssertGreaterThan(fakeService.updatedElapsedHistory.count, baselineHistoryCount)
        XCTAssertEqual(fakeService.lastUpdatedElapsed, 12.3)
    }

    func testCoordinator_OnPause_DoesNotClear() async {
        stateSubject.send(.playing)
        await awaitPublishers()
        let baselineClearCount = fakeService.clearCallCount

        stateSubject.send(.paused)
        await awaitPublishers()

        XCTAssertEqual(fakeService.clearCallCount, baselineClearCount,
                       "pause must not clear the Now Playing widget")
    }

    func testCoordinator_OnStop_ClearsNowPlaying() async {
        stateSubject.send(.playing)
        await awaitPublishers()
        let baselineClearCount = fakeService.clearCallCount

        stateSubject.send(.stopped)
        await awaitPublishers()

        XCTAssertGreaterThan(fakeService.clearCallCount, baselineClearCount)
    }

    // MARK: - Push: seek notification (direct method, not via publisher)

    func testCoordinator_OnSeekNotification_UpdatesElapsedTime() async {
        let baselineHistoryCount = fakeService.updatedElapsedHistory.count

        sut.notifySeekCompleted(at: 42.0)
        await awaitPublishers()

        XCTAssertGreaterThan(fakeService.updatedElapsedHistory.count, baselineHistoryCount)
        XCTAssertEqual(fakeService.lastUpdatedElapsed, 42.0)
    }

    // MARK: - Pull: command callbacks routed to injected closures

    func testCoordinator_OnPlayCommand_InvokesPlayClosure() async {
        fakeService.onPlay?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(playCallCount, 1)
    }

    func testCoordinator_OnPauseCommand_InvokesPauseClosure() async {
        fakeService.onPause?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(pauseCallCount, 1)
    }

    func testCoordinator_OnNextCommand_InvokesNextClosure() async {
        fakeService.onNext?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(nextCallCount, 1)
    }

    func testCoordinator_OnPrevCommand_InvokesPreviousClosure() async {
        fakeService.onPrevious?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(previousCallCount, 1)
    }

    func testCoordinator_OnSeekCommand_InvokesSeekClosure() async {
        fakeService.onSeek?(42.0)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(seekArgsHistory.count, 1)
        XCTAssertEqual(seekArgsHistory.last, 42.0)
    }

    func testCoordinator_OnTogglePlayPauseCommand_InvokesToggleClosure() async {
        fakeService.onTogglePlayPause?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(togglePlayPauseCallCount, 1)
    }

    func testCoordinator_OnStopCommand_InvokesStopClosure() async {
        fakeService.onStop?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(stopCallCount, 1)
    }
}
