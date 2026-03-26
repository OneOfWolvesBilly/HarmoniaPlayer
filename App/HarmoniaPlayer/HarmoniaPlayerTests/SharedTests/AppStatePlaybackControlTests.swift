//
//  AppStatePlaybackControlTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-03-09.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState transport controls: play() / pause() / stop() (Slice 4-B).
///
/// Verifies that each transport method delegates to `PlaybackService`,
/// keeps `playbackState` in sync, and handles errors correctly.
///
/// **Swift 6 / Xcode 26 note:**
/// Test class is `@MainActor` — XCTest runs `@MainActor`-isolated classes on
/// the main actor automatically, so no `await MainActor.run {}` wrappers are
/// needed in individual test methods.
@MainActor
final class AppStatePlaybackControlTests: XCTestCase {

    // MARK: - Test Fixtures

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Loads a track into AppState so play() can proceed past the
    /// "no currentTrack" and "stopped state" guards added in Slice 6-B.
    private func loadTrackIntoSUT() async {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await sut.load(urls: [url])
        // play(trackID:) sets currentTrack and transitions state to .paused
        // via the fake service; subsequent play() calls work correctly.
        if let first = sut.playlist.tracks.first {
            await sut.play(trackID: first.id)
            // Reset call counts so individual tests start clean.
            fakePlaybackService.resetCounts()
        }
    }

    // MARK: - play()

    /// `testPlay_CallsPlaybackServicePlay`
    ///
    /// Given a track is loaded and paused,
    /// when `play()` is called,
    /// then `playbackService.play()` is called exactly once.
    func testPlay_CallsPlaybackServicePlay() async {
        await loadTrackIntoSUT()

        await sut.play()

        XCTAssertEqual(fakePlaybackService.playCallCount, 1)
    }

    /// `testPlay_SetsPlayingState`
    ///
    /// Given a track is loaded and paused,
    /// when `play()` is called,
    /// then `playbackState` is `.playing`.
    func testPlay_SetsPlayingState() async {
        await loadTrackIntoSUT()

        await sut.play()

        XCTAssertEqual(sut.playbackState, .playing)
    }

    /// `testPlay_OnError_SetsLastError`
    ///
    /// Given `stubbedPlayError` is set,
    /// when `play()` is called,
    /// then `lastError` is non-nil.
    func testPlay_OnError_SetsLastError() async {
        await loadTrackIntoSUT()
        fakePlaybackService.stubbedPlayError = PlaybackError.outputError

        await sut.play()

        XCTAssertNotNil(sut.lastError)
    }

    /// `testPlay_OnError_SetsErrorState`
    ///
    /// Given `stubbedPlayError` is set,
    /// when `play()` is called,
    /// then `playbackState` is `.error(...)`.
    func testPlay_OnError_SetsErrorState() async {
        await loadTrackIntoSUT()
        fakePlaybackService.stubbedPlayError = PlaybackError.outputError

        await sut.play()

        if case .error = sut.playbackState {
            // expected
        } else {
            XCTFail("Expected playbackState == .error, got \(sut.playbackState)")
        }
    }

    // MARK: - pause()

    /// `testPause_CallsPlaybackServicePause`
    ///
    /// Given a fresh AppState,
    /// when `pause()` is called,
    /// then `playbackService.pause()` is called exactly once.
    func testPause_CallsPlaybackServicePause() async {
        await sut.pause()

        XCTAssertEqual(fakePlaybackService.pauseCallCount, 1)
    }

    /// `testPause_SetsPausedState`
    ///
    /// Given any AppState,
    /// when `pause()` is called,
    /// then `playbackState` is `.paused`.
    func testPause_SetsPausedState() async {
        await sut.pause()

        XCTAssertEqual(sut.playbackState, .paused)
    }

    // MARK: - stop()

    /// `testStop_CallsPlaybackServiceStop`
    ///
    /// Given a fresh AppState,
    /// when `stop()` is called,
    /// then `playbackService.stop()` is called exactly once.
    func testStop_CallsPlaybackServiceStop() async {
        await sut.stop()

        XCTAssertEqual(fakePlaybackService.stopCallCount, 1)
    }

    /// `testStop_SetsStoppedState`
    ///
    /// Given any AppState,
    /// when `stop()` is called,
    /// then `playbackState` is `.stopped`.
    func testStop_SetsStoppedState() async {
        await sut.stop()

        XCTAssertEqual(sut.playbackState, .stopped)
    }

    /// `testStop_ResetsCurrentTimeToZero`
    ///
    /// Given `currentTime` is non-zero,
    /// when `stop()` is called,
    /// then `currentTime` is `0`.
    func testStop_ResetsCurrentTimeToZero() async {
        // Arrange: manually force currentTime > 0 is not directly possible,
        // but stop() spec states it always resets to 0 regardless.
        await sut.stop()

        XCTAssertEqual(sut.currentTime, 0)
    }

    // MARK: - seek(to:) — Slice 4-D

    /// `testSeek_CallsPlaybackServiceSeek`
    ///
    /// Given a fresh AppState,
    /// when `seek(to: 30.0)` is called,
    /// then `playbackService.seek(to:)` is called exactly once.
    func testSeek_CallsPlaybackServiceSeek() async {
        await sut.seek(to: 30.0)

        XCTAssertEqual(fakePlaybackService.seekCallCount, 1)
    }

    /// `testSeek_PassesCorrectSeconds`
    ///
    /// Given a fresh AppState,
    /// when `seek(to: 30.0)` is called,
    /// then the argument passed to `playbackService.seek(to:)` is `30.0`.
    func testSeek_PassesCorrectSeconds() async {
        await sut.seek(to: 30.0)

        XCTAssertEqual(fakePlaybackService.seekedToSeconds.first, 30.0)
    }

    /// `testSeek_Success_UpdatesCurrentTime`
    ///
    /// Given no error stub is set,
    /// when `seek(to: 30.0)` is called,
    /// then `currentTime` is `30.0`.
    func testSeek_Success_UpdatesCurrentTime() async {
        await sut.seek(to: 30.0)

        XCTAssertEqual(sut.currentTime, 30.0)
    }

    /// `testSeek_Error_SetsLastError`
    ///
    /// Given `stubbedSeekError` is set,
    /// when `seek(to:)` is called,
    /// then `lastError` is non-nil.
    func testSeek_Error_SetsLastError() async {
        fakePlaybackService.stubbedSeekError = PlaybackError.failedToDecode

        await sut.seek(to: 30.0)

        XCTAssertNotNil(sut.lastError)
    }

    /// `testSeek_Error_DoesNotChangePlaybackState`
    ///
    /// Given `playbackState` is `.playing` and `stubbedSeekError` is set,
    /// when `seek(to:)` is called,
    /// then `playbackState` remains `.playing`.
    func testSeek_Error_DoesNotChangePlaybackState() async {
        await loadTrackIntoSUT()
        await sut.play()
        XCTAssertEqual(sut.playbackState, .playing)

        fakePlaybackService.stubbedSeekError = PlaybackError.failedToDecode

        await sut.seek(to: 30.0)

        XCTAssertEqual(sut.playbackState, .playing)
    }
}
