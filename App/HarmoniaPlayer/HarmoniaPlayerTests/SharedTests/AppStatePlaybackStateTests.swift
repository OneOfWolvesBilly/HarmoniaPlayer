//
//  AppStatePlaybackTrackTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-03-09.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState.play(trackID:) load-and-play orchestration (Slice 4-C)
///
/// Verifies that `play(trackID:)` sets `currentTrack`, calls
/// `playbackService.load(url:)` and `playbackService.play()` in order,
/// updates `duration` after successful load, and propagates errors into
/// `lastError` and `playbackState`.
///
/// **Swift 6 / Xcode 26 note:**
/// Test class is `@MainActor` — XCTest runs `@MainActor`-isolated classes on
/// the main actor automatically, so no `await MainActor.run {}` wrappers are
/// needed in individual test methods.
@MainActor
final class AppStatePlaybackTrackTests: XCTestCase {

    // MARK: - Test Fixtures

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!

    override func setUp() {
        super.setUp()
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: provider)
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Loads one track into the SUT's playlist and returns it.
    private func loadOneTrack() async -> Track {
        let url = URL(fileURLWithPath: "/tmp/test-track.mp3")
        await sut.load(urls: [url])
        return sut.playlist.tracks[0]
    }

    // MARK: - Tests

    /// `testPlayTrack_SetsCurrentTrack`
    ///
    /// Given a playlist with one track,
    /// when `play(trackID:)` is called with that track's ID,
    /// then `currentTrack` is set to the matching track.
    func testPlayTrack_SetsCurrentTrack() async {
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(sut.currentTrack, track)
    }

    /// `testPlayTrack_CallsLoad`
    ///
    /// Given a playlist with one track,
    /// when `play(trackID:)` is called with that track's ID,
    /// then `playbackService.load(url:)` is called exactly once.
    func testPlayTrack_CallsLoad() async {
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }

    /// `testPlayTrack_LoadsCorrectURL`
    ///
    /// Given a playlist with one track,
    /// when `play(trackID:)` is called with that track's ID,
    /// then the URL passed to `playbackService.load(url:)` matches the track's URL.
    func testPlayTrack_LoadsCorrectURL() async {
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(fakePlaybackService.loadedURLs.first, track.url)
    }

    /// `testPlayTrack_CallsPlay`
    ///
    /// Given a playlist with one track and no error stubs,
    /// when `play(trackID:)` is called with that track's ID,
    /// then `playbackService.play()` is called exactly once.
    func testPlayTrack_CallsPlay() async {
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(fakePlaybackService.playCallCount, 1)
    }

    /// `testPlayTrack_SetsPlayingState`
    ///
    /// Given a playlist with one track and no error stubs,
    /// when `play(trackID:)` is called with that track's ID,
    /// then `playbackState` is `.playing`.
    func testPlayTrack_SetsPlayingState() async {
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(sut.playbackState, .playing)
    }

    /// `testPlayTrack_UpdatesDuration`
    ///
    /// Given `stubbedDuration = 240.0`,
    /// when `play(trackID:)` succeeds,
    /// then `duration` is updated to `240.0`.
    func testPlayTrack_UpdatesDuration() async {
        fakePlaybackService.stubbedDuration = 240.0
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(sut.duration, 240.0)
    }

    /// `testPlayTrack_LoadError_SetsLastError`
    ///
    /// Given `stubbedLoadError` is set,
    /// when `play(trackID:)` is called,
    /// then `lastError` is non-nil.
    func testPlayTrack_LoadError_SetsLastError() async {
        fakePlaybackService.stubbedLoadError = PlaybackError.failedToOpenFile
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertNotNil(sut.lastError)
    }

    /// `testPlayTrack_LoadError_SetsErrorState`
    ///
    /// Given `stubbedLoadError` is set,
    /// when `play(trackID:)` is called,
    /// then `playbackState` is `.error(...)`.
    func testPlayTrack_LoadError_SetsErrorState() async {
        fakePlaybackService.stubbedLoadError = PlaybackError.failedToOpenFile
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        if case .error = sut.playbackState {
            // expected
        } else {
            XCTFail("Expected playbackState == .error, got \(sut.playbackState)")
        }
    }

    /// `testPlayTrack_LoadError_DoesNotCallPlay`
    ///
    /// Given `stubbedLoadError` is set,
    /// when `play(trackID:)` is called,
    /// then `playbackService.play()` is never called.
    func testPlayTrack_LoadError_DoesNotCallPlay() async {
        fakePlaybackService.stubbedLoadError = PlaybackError.failedToOpenFile
        let track = await loadOneTrack()

        await sut.play(trackID: track.id)

        XCTAssertEqual(fakePlaybackService.playCallCount, 0)
    }

    /// `testPlayTrack_InvalidID_NoServiceCalls`
    ///
    /// Given an invalid trackID not present in the playlist,
    /// when `play(trackID:)` is called,
    /// then no service calls are made.
    func testPlayTrack_InvalidID_NoServiceCalls() async {
        _ = await loadOneTrack()

        await sut.play(trackID: UUID())

        XCTAssertEqual(fakePlaybackService.loadCallCount, 0)
    }

    /// `testPlayTrack_InvalidID_NilsCurrentTrack`
    ///
    /// Given an invalid trackID not present in the playlist,
    /// when `play(trackID:)` is called,
    /// then `currentTrack` is nil.
    func testPlayTrack_InvalidID_NilsCurrentTrack() async {
        _ = await loadOneTrack()

        await sut.play(trackID: UUID())

        XCTAssertNil(sut.currentTrack)
    }
}
