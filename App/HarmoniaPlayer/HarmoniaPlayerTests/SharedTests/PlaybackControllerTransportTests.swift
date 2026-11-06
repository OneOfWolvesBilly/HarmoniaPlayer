//
//  PlaybackControllerTransportTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import Combine
import XCTest
@testable import Harmonia_Player

/// Tests for the `PlaybackController` transport surface: `play()`,
/// `pause()`, `stop()`, `seek(to:)`, `setVolume(_:)`, the initial state,
/// error recovery, sleep / wake, the root-wired notifications, and the
/// Now Playing publishers.
@MainActor
final class PlaybackControllerTransportTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() async throws {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private struct Fixture {
        let sut: PlaybackController
        let fake: FakePlaybackService
        let context: FakePlaylistContext
        let alertCenter: AlertCenter
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let fake = FakePlaybackService()
        let context = FakePlaylistContext()
        let alertCenter = AlertCenter()
        let sut = PlaybackController(
            playbackService: fake,
            alertCenter: alertCenter,
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        sut.playlistContext = context
        return Fixture(sut: sut, fake: fake, context: context, alertCenter: alertCenter)
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    /// Seeds one track, plays it, and resets the fake's counters so each
    /// test starts from a playing track with a clean call record.
    private func loadTrackIntoSUT(_ f: Fixture) async {
        let track = Track(url: makeURL("test"))
        f.context.playlists[0].tracks = [track]
        await f.sut.play(trackID: track.id)
        f.fake.resetCounts()
    }

    /// Seeds three tracks and returns them.
    private func seedThreeTracks(_ f: Fixture) -> (Track, Track, Track) {
        let tracks = [Track(url: makeURL("sel-a")), Track(url: makeURL("sel-b")), Track(url: makeURL("sel-c"))]
        f.context.playlists[0].tracks = tracks
        return (tracks[0], tracks[1], tracks[2])
    }

    // MARK: - Initial state

    func testInitialPlaybackState_IsIdle() {
        let f = makeSUT()
        XCTAssertEqual(f.sut.playbackState, .idle)
    }

    func testInitialCurrentTime_IsZero() {
        let f = makeSUT()
        XCTAssertEqual(f.sut.currentTime, 0)
    }

    func testInitialDuration_IsZero() {
        let f = makeSUT()
        XCTAssertEqual(f.sut.duration, 0)
    }

    // MARK: - play()

    func testPlay_CallsPlaybackServicePlay() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)

        await f.sut.play()

        XCTAssertEqual(f.fake.playCallCount, 1)
    }

    func testPlay_SetsPlayingState() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)

        await f.sut.play()

        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    func testPlay_OnError_SetsLastError() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        f.fake.stubbedPlayError = PlaybackError.outputError

        await f.sut.play()

        XCTAssertNotNil(f.alertCenter.lastError)
    }

    func testPlay_OnError_SetsErrorState() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        f.fake.stubbedPlayError = PlaybackError.outputError

        await f.sut.play()

        if case .error = f.sut.playbackState {
            // expected
        } else {
            XCTFail("Expected playbackState == .error, got \(f.sut.playbackState)")
        }
    }

    // MARK: - pause()

    func testPause_CallsPlaybackServicePause() async {
        let f = makeSUT()

        await f.sut.pause()

        XCTAssertEqual(f.fake.pauseCallCount, 1)
    }

    func testPause_SetsPausedState() async {
        let f = makeSUT()

        await f.sut.pause()

        XCTAssertEqual(f.sut.playbackState, .paused)
    }

    // MARK: - stop()

    func testStop_CallsPlaybackServiceStop() async {
        let f = makeSUT()

        await f.sut.stop()

        XCTAssertEqual(f.fake.stopCallCount, 1)
    }

    func testStop_SetsStoppedState() async {
        let f = makeSUT()

        await f.sut.stop()

        XCTAssertEqual(f.sut.playbackState, .stopped)
    }

    func testStop_ResetsCurrentTimeToZero() async {
        let f = makeSUT()
        await f.sut.seek(to: 30.0)

        await f.sut.stop()

        XCTAssertEqual(f.sut.currentTime, 0)
    }

    func testStop_ClearsCurrentTrack() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        XCTAssertNotNil(f.sut.currentTrack, "Pre-condition: currentTrack should be set")

        await f.sut.stop()

        XCTAssertNil(f.sut.currentTrack)
    }

    func testStop_ClearsPlayingPlaylistID() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        XCTAssertNotNil(f.sut.playingPlaylistID, "Pre-condition: playingPlaylistID should be set")

        await f.sut.stop()

        XCTAssertNil(f.sut.playingPlaylistID)
    }

    // MARK: - seek(to:)

    func testSeek_CallsPlaybackServiceSeek() async {
        let f = makeSUT()

        await f.sut.seek(to: 30.0)

        XCTAssertEqual(f.fake.seekCallCount, 1)
    }

    func testSeek_PassesCorrectSeconds() async {
        let f = makeSUT()

        await f.sut.seek(to: 30.0)

        XCTAssertEqual(f.fake.seekedToSeconds.first, 30.0)
    }

    func testSeek_Success_UpdatesCurrentTime() async {
        let f = makeSUT()

        await f.sut.seek(to: 30.0)

        XCTAssertEqual(f.sut.currentTime, 30.0)
    }

    func testSeek_Error_SetsLastError() async {
        let f = makeSUT()
        f.fake.stubbedSeekError = PlaybackError.failedToDecode

        await f.sut.seek(to: 30.0)

        XCTAssertNotNil(f.alertCenter.lastError)
    }

    func testSeek_Error_DoesNotChangePlaybackState() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        await f.sut.play()
        XCTAssertEqual(f.sut.playbackState, .playing)
        f.fake.stubbedSeekError = PlaybackError.failedToDecode

        await f.sut.seek(to: 30.0)

        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    func testSeek_Success_CallsOnSeekCompleted() async {
        let f = makeSUT()
        var received: [TimeInterval] = []
        f.sut.onSeekCompleted = { received.append($0) }

        await f.sut.seek(to: 42)

        XCTAssertEqual(received, [42])
    }

    func testSeek_Failure_DoesNotCallOnSeekCompleted() async {
        let f = makeSUT()
        f.fake.stubbedSeekError = PlaybackError.failedToDecode
        var callCount = 0
        f.sut.onSeekCompleted = { _ in callCount += 1 }

        await f.sut.seek(to: 42)

        XCTAssertEqual(callCount, 0)
    }

    // MARK: - play() with selection

    func testPlay_NoCurrentTrack_WithSelection_PlaysSelectedTrack() async {
        let f = makeSUT()
        let (_, trackB, _) = seedThreeTracks(f)
        XCTAssertNil(f.sut.currentTrack, "Pre-condition: currentTrack should be nil")
        f.context.selectedTrackIDs = [trackB.id]

        await f.sut.play()

        XCTAssertEqual(f.sut.currentTrack?.id, trackB.id)
    }

    func testPlay_NoCurrentTrack_WithMultipleSelection_PlaysFirstInPlaylistOrder() async {
        let f = makeSUT()
        let (_, trackB, trackC) = seedThreeTracks(f)
        f.context.selectedTrackIDs = [trackC.id, trackB.id]

        await f.sut.play()

        XCTAssertEqual(f.sut.currentTrack?.id, trackB.id)
    }

    func testPlay_NoCurrentTrack_NoSelection_PlaysFirstTrack() async {
        let f = makeSUT()
        let (trackA, _, _) = seedThreeTracks(f)
        XCTAssertTrue(f.context.selectedTrackIDs.isEmpty)

        await f.sut.play()

        XCTAssertEqual(f.sut.currentTrack?.id, trackA.id)
    }

    func testPlay_NoCurrentTrack_EmptyPlaylist_IsNoop() async {
        let f = makeSUT()
        XCTAssertTrue(f.context.playlists[0].tracks.isEmpty)

        await f.sut.play()

        XCTAssertNil(f.sut.currentTrack)
        XCTAssertEqual(f.sut.playbackState, .idle)
    }

    // MARK: - setVolume(_:)

    func testSetVolume_ForwardsToService() async {
        let f = makeSUT()

        await f.sut.setVolume(0.5)

        XCTAssertEqual(f.fake.setVolumeCallCount, 1)
    }

    func testSetVolume_Clamps_AboveOne() async {
        let f = makeSUT()

        await f.sut.setVolume(1.5)

        XCTAssertEqual(f.fake.lastSetVolume, 1.0)
    }

    func testSetVolume_Clamps_BelowZero() async {
        let f = makeSUT()

        await f.sut.setVolume(-0.1)

        XCTAssertEqual(f.fake.lastSetVolume, 0.0)
    }

    // MARK: - recoverFromError()

    func testRecoverFromError_ErrorState_BecomesStopped() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        f.fake.stubbedPlayError = PlaybackError.outputError
        await f.sut.play()
        guard case .error = f.sut.playbackState else {
            return XCTFail("Pre-condition: playbackState should be .error, got \(f.sut.playbackState)")
        }

        f.sut.recoverFromError()

        XCTAssertEqual(f.sut.playbackState, .stopped)
    }

    func testRecoverFromError_WhenNotError_LeavesStateUnchanged() async {
        let f = makeSUT()
        await f.sut.pause()

        f.sut.recoverFromError()

        XCTAssertEqual(f.sut.playbackState, .paused)
    }

    // MARK: - Sleep / wake

    func testWillSleepRecordsPlayingState() {
        let f = makeSUT()
        f.sut.playbackState = .playing

        f.sut.handleSystemWillSleep()

        XCTAssertTrue(f.sut.wasPlayingBeforeSleep,
                      "willSleep should record that playback was active")
    }

    func testWillSleepRecordsFalseWhenPaused() {
        let f = makeSUT()
        f.sut.playbackState = .playing
        f.sut.handleSystemWillSleep()
        f.sut.playbackState = .paused

        f.sut.handleSystemWillSleep()

        XCTAssertFalse(f.sut.wasPlayingBeforeSleep,
                       "willSleep should record false when playback is paused")
    }

    func testDidWakeResumesWhenWasPlaying() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        f.sut.handleSystemWillSleep()
        f.fake.state = .paused
        f.fake.resetCounts()

        await f.sut.handleSystemDidWake()

        XCTAssertEqual(f.fake.playCallCount, 1,
                       "didWake should resume via the existing play() path")
    }

    func testDidWakeDoesNotResumeWhenWasPaused() async {
        let f = makeSUT()
        await loadTrackIntoSUT(f)
        await f.sut.pause()
        f.sut.handleSystemWillSleep()
        f.fake.resetCounts()

        await f.sut.handleSystemDidWake()

        XCTAssertEqual(f.fake.playCallCount, 0,
                       "didWake must not resume when playback was paused before sleep")
    }

    func testDidWakeClearsFlag() async {
        let f = makeSUT()
        f.sut.playbackState = .playing
        f.sut.handleSystemWillSleep()
        XCTAssertTrue(f.sut.wasPlayingBeforeSleep,
                      "precondition: willSleep must have recorded true")

        await f.sut.handleSystemDidWake()

        XCTAssertFalse(f.sut.wasPlayingBeforeSleep,
                       "didWake should clear the pre-sleep flag")
    }

    // MARK: - Root-wired notifications and publishers

    func testCurrentTrackChange_CallsOnCurrentTrackChanged() async {
        let f = makeSUT()
        let track = Track(url: makeURL("notify"))
        f.context.playlists[0].tracks = [track]
        var received: [Track?] = []
        f.sut.onCurrentTrackChanged = { received.append($0) }

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(received.last??.id, track.id)
    }

    func testPublishers_EmitCurrentTrackAndPlaybackState() async {
        let f = makeSUT()
        let track = Track(url: makeURL("publish"))
        f.context.playlists[0].tracks = [track]
        var tracks: [Track?] = []
        var states: [PlaybackState] = []
        var cancellables = Set<AnyCancellable>()
        f.sut.currentTrackPublisher.sink { tracks.append($0) }.store(in: &cancellables)
        f.sut.playbackStatePublisher.sink { states.append($0) }.store(in: &cancellables)

        await f.sut.play(trackID: track.id)
        await f.sut.pause()

        XCTAssertEqual(tracks.last??.id, track.id)
        XCTAssertTrue(states.contains(.playing), "playbackStatePublisher must emit .playing, got \(states)")
        XCTAssertEqual(states.last, .paused)
        cancellables.removeAll()
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
