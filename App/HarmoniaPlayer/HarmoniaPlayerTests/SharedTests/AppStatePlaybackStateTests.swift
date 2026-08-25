//
//  AppStatePlaybackStateTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-03-09.
//

import XCTest
@testable import Harmonia_Player

/// Tests for AppState initial playback state (Slice 4-A).
///
/// Verifies that `playbackState`, `currentTime`, and `duration` are
/// initialised to their documented defaults on a fresh `AppState` instance.
///
/// **Swift 6 / Xcode 26 note:**
/// Test class is `@MainActor` — XCTest runs `@MainActor`-isolated classes on
/// the main actor automatically, so no `await MainActor.run {}` wrappers are
/// needed in individual test methods.
@MainActor
final class AppStatePlaybackStateTests: XCTestCase {

    // MARK: - Fixture

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
        sut = AppState(iapManager: MockIAPManager(), provider: provider, userDefaults: testDefaults, playlistStore: FakePlaylistStore())
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

    /// Loads a track and starts playback so `playbackState == .playing`
    /// with a non-nil `currentTrack`.
    private func loadAndPlay() async {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await sut.load(urls: [url])
        if let first = sut.playlist.tracks.first {
            await sut.play(trackID: first.id)
        }
    }

    // MARK: - Slice 4-A: Initial State

    /// `testAppState_InitialPlaybackState_IsIdle`
    ///
    /// Given a freshly created AppState,
    /// when `playbackState` is read,
    /// then it is `.idle`.
    func testAppState_InitialPlaybackState_IsIdle() {
        XCTAssertEqual(sut.playbackState, .idle)
    }

    /// `testAppState_InitialCurrentTime_IsZero`
    ///
    /// Given a freshly created AppState,
    /// when `currentTime` is read,
    /// then it is `0`.
    func testAppState_InitialCurrentTime_IsZero() {
        XCTAssertEqual(sut.currentTime, 0)
    }

    /// `testAppState_InitialDuration_IsZero`
    ///
    /// Given a freshly created AppState,
    /// when `duration` is read,
    /// then it is `0`.
    func testAppState_InitialDuration_IsZero() {
        XCTAssertEqual(sut.duration, 0)
    }

    // MARK: - Sleep/Wake

    /// `testWillSleepRecordsPlayingState`
    ///
    /// Given `playbackState == .playing`,
    /// when `handleSystemWillSleep()` is called,
    /// then `wasPlayingBeforeSleep` is `true`.
    func testWillSleepRecordsPlayingState() {
        sut.playbackState = .playing

        sut.handleSystemWillSleep()

        XCTAssertTrue(sut.wasPlayingBeforeSleep,
                      "willSleep should record that playback was active")
    }

    /// `testWillSleepRecordsFalseWhenPaused`
    ///
    /// Given `wasPlayingBeforeSleep` was previously recorded `true` and
    /// `playbackState` is now `.paused`,
    /// when `handleSystemWillSleep()` is called,
    /// then `wasPlayingBeforeSleep` is overwritten to `false`.
    func testWillSleepRecordsFalseWhenPaused() {
        sut.playbackState = .playing
        sut.handleSystemWillSleep()
        sut.playbackState = .paused

        sut.handleSystemWillSleep()

        XCTAssertFalse(sut.wasPlayingBeforeSleep,
                       "willSleep should record false when playback is paused")
    }

    /// `testDidWakeResumesWhenWasPlaying`
    ///
    /// Given playback was active before sleep and the service left
    /// `.playing` during sleep (output invalidated, position retained),
    /// when `handleSystemDidWake()` is called,
    /// then `play()` reaches the playback service exactly once.
    func testDidWakeResumesWhenWasPlaying() async {
        await loadAndPlay()
        sut.handleSystemWillSleep()
        fakePlaybackService.state = .paused
        fakePlaybackService.resetCounts()

        await sut.handleSystemDidWake()

        XCTAssertEqual(fakePlaybackService.playCallCount, 1,
                       "didWake should resume via the existing play() path")
    }

    /// `testDidWakeDoesNotResumeWhenWasPaused`
    ///
    /// Given playback was paused before sleep,
    /// when `handleSystemDidWake()` is called,
    /// then no `play()` reaches the playback service.
    func testDidWakeDoesNotResumeWhenWasPaused() async {
        await loadAndPlay()
        await sut.pause()
        sut.handleSystemWillSleep()
        fakePlaybackService.resetCounts()

        await sut.handleSystemDidWake()

        XCTAssertEqual(fakePlaybackService.playCallCount, 0,
                       "didWake must not resume when playback was paused before sleep")
    }

    /// `testDidWakeClearsFlag`
    ///
    /// Given `wasPlayingBeforeSleep == true`,
    /// when `handleSystemDidWake()` is called,
    /// then the flag is `false` afterwards.
    func testDidWakeClearsFlag() async {
        sut.playbackState = .playing
        sut.handleSystemWillSleep()
        XCTAssertTrue(sut.wasPlayingBeforeSleep,
                      "precondition: willSleep must have recorded true")

        await sut.handleSystemDidWake()

        XCTAssertFalse(sut.wasPlayingBeforeSleep,
                       "didWake should clear the pre-sleep flag")
    }
}
