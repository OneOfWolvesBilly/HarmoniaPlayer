//
//  AppStatePlaybackControlTests.swift
//  HarmoniaPlayerTests
//
//  Slice 4-B: play() / pause() / stop() transport controls.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState transport controls (Slice 4-B).
///
/// Verifies that `play()`, `pause()`, and `stop()` delegate correctly
/// to `PlaybackService` and keep `playbackState` in sync.
/// Error paths from `play()` are captured in `lastError` and
/// reflected as `playbackState = .error(...)`.
///
/// **Swift 6 / Xcode 26 note:**
/// `@MainActor` is required because `AppState` is `@MainActor`-isolated.
/// Async test methods are required for all transport control calls.
@MainActor
final class AppStatePlaybackControlTests: XCTestCase {

    // MARK: - Test Fixtures

    private var sut: AppState!
    private var fakeService: FakePlaybackService!

    override func setUp() {
        super.setUp()
        fakeService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakeService)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: provider)
    }

    override func tearDown() {
        sut = nil
        fakeService = nil
        super.tearDown()
    }

    // MARK: - play()

    /// testPlay_CallsPlaybackServicePlay
    ///
    /// Given: AppState with FakePlaybackService
    /// When:  `await play()` is called
    /// Then:  `fakeService.playCallCount == 1`
    func testPlay_CallsPlaybackServicePlay() async {
        // When
        await sut.play()

        // Then
        XCTAssertEqual(fakeService.playCallCount, 1)
    }

    /// testPlay_SetsPlayingState
    ///
    /// Given: No error stub on FakePlaybackService
    /// When:  `await play()` is called
    /// Then:  `playbackState == .playing`
    func testPlay_SetsPlayingState() async {
        // When
        await sut.play()

        // Then
        XCTAssertEqual(sut.playbackState, .playing)
    }

    /// testPlay_OnError_SetsLastError
    ///
    /// Given: `stubbedPlayError` set on FakePlaybackService
    /// When:  `await play()` is called
    /// Then:  `lastError != nil`
    func testPlay_OnError_SetsLastError() async {
        // Given
        fakeService.stubbedPlayError = PlaybackError.outputError

        // When
        await sut.play()

        // Then
        XCTAssertNotNil(sut.lastError)
    }

    /// testPlay_OnError_SetsErrorState
    ///
    /// Given: `stubbedPlayError` set on FakePlaybackService
    /// When:  `await play()` is called
    /// Then:  `playbackState == .error(...)`
    func testPlay_OnError_SetsErrorState() async {
        // Given
        fakeService.stubbedPlayError = PlaybackError.outputError

        // When
        await sut.play()

        // Then
        if case .error = sut.playbackState {
            // Pass
        } else {
            XCTFail("Expected playbackState to be .error, got \(sut.playbackState)")
        }
    }

    // MARK: - pause()

    /// testPause_CallsPlaybackServicePause
    ///
    /// Given: AppState with FakePlaybackService
    /// When:  `await pause()` is called
    /// Then:  `fakeService.pauseCallCount == 1`
    func testPause_CallsPlaybackServicePause() async {
        // When
        await sut.pause()

        // Then
        XCTAssertEqual(fakeService.pauseCallCount, 1)
    }

    /// testPause_SetsPausedState
    ///
    /// Given: AppState with FakePlaybackService
    /// When:  `await pause()` is called
    /// Then:  `playbackState == .paused`
    func testPause_SetsPausedState() async {
        // When
        await sut.pause()

        // Then
        XCTAssertEqual(sut.playbackState, .paused)
    }

    // MARK: - stop()

    /// testStop_CallsPlaybackServiceStop
    ///
    /// Given: AppState with FakePlaybackService
    /// When:  `await stop()` is called
    /// Then:  `fakeService.stopCallCount == 1`
    func testStop_CallsPlaybackServiceStop() async {
        // When
        await sut.stop()

        // Then
        XCTAssertEqual(fakeService.stopCallCount, 1)
    }

    /// testStop_SetsStoppedState
    ///
    /// Given: AppState with FakePlaybackService
    /// When:  `await stop()` is called
    /// Then:  `playbackState == .stopped`
    func testStop_SetsStoppedState() async {
        // When
        await sut.stop()

        // Then
        XCTAssertEqual(sut.playbackState, .stopped)
    }

    /// testStop_ResetsCurrentTimeToZero
    ///
    /// Given: AppState (currentTime starts at 0; will be more meaningful
    ///        after Slice 4-D adds seek(to:) to set currentTime > 0)
    /// When:  `await stop()` is called
    /// Then:  `currentTime == 0`
    func testStop_ResetsCurrentTimeToZero() async {
        // When
        await sut.stop()

        // Then
        XCTAssertEqual(sut.currentTime, 0)
    }
}
