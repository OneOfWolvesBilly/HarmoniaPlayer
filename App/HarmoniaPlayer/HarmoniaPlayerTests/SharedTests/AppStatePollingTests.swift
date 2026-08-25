//
//  AppStatePollingTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-04-20.
//

import XCTest
@testable import Harmonia_Player

/// Tests for AppState playback polling task lifecycle (Slice 9-E).
///
/// Verifies that the polling task is cancelled on `stop()` and that the
/// loop exits cleanly when cancelled externally. These tests guard against
/// regression of `CancellationError` handling in `startPolling()`.
///
/// **Swift 6 / Xcode 26 note:**
/// Test class is `@MainActor` — XCTest runs `@MainActor`-isolated classes on
/// the main actor automatically, so no `await MainActor.run {}` wrappers are
/// needed in individual test methods.
@MainActor
final class AppStatePollingTests: XCTestCase {

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
        sut = AppState(iapManager: iap, provider: provider, userDefaults: testDefaults, playlistStore: FakePlaylistStore())
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

    /// Loads a track and starts playback so `pollingTask` is active.
    private func loadAndPlay() async {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await sut.load(urls: [url])
        if let first = sut.playlist.tracks.first {
            await sut.play(trackID: first.id)
        }
    }

    // MARK: - Tests

    /// `testStopPolling_CancelsTask`
    ///
    /// Given a track is playing with an active polling task,
    /// when `stop()` is called,
    /// then `pollingTask` is cancelled and cleared.
    func testStopPolling_CancelsTask() async {
        await loadAndPlay()
        XCTAssertNotNil(sut.pollingTask, "pollingTask should be active during playback")

        await sut.stop()

        XCTAssertNil(sut.pollingTask, "pollingTask should be cleared after stop()")
    }

    /// `testPolling_StopsOnCancellation`
    ///
    /// Given a track is playing with an active polling task,
    /// when the polling task is cancelled externally,
    /// then the loop exits cleanly (task completes without hanging).
    func testPolling_StopsOnCancellation() async {
        await loadAndPlay()
        let task = sut.pollingTask
        XCTAssertNotNil(task, "pollingTask should be active during playback")

        task?.cancel()
        await task?.value

        XCTAssertTrue(task?.isCancelled ?? false, "task should be cancelled after external cancel()")
    }

    // MARK: - Service State Reflection

    /// `testPollingReflectsServicePaused`
    ///
    /// Given the app believes it is playing while the service reports
    /// `.paused`,
    /// when a polling tick runs,
    /// then `playbackState` becomes `.paused` and polling is cancelled.
    func testPollingReflectsServicePaused() async throws {
        await loadAndPlay()
        fakePlaybackService.state = .paused

        try await Task.sleep(nanoseconds: 600_000_000) // ≥ one 0.25s tick

        XCTAssertEqual(sut.playbackState, .paused,
                       "polling should reflect the service's paused state")
        XCTAssertNil(sut.pollingTask,
                     "polling should stop once the paused state is reflected")
    }

    /// `testPollingReflectsServiceError`
    ///
    /// Given the app believes it is playing while the service reports
    /// `.error`,
    /// when a polling tick runs,
    /// then `playbackState` becomes that error, `lastError` is set, and
    /// polling is cancelled.
    func testPollingReflectsServiceError() async throws {
        await loadAndPlay()
        fakePlaybackService.state = .error(.outputError)

        try await Task.sleep(nanoseconds: 600_000_000) // ≥ one 0.25s tick

        XCTAssertEqual(sut.playbackState, .error(.outputError),
                       "polling should reflect the service's error state")
        XCTAssertEqual(sut.lastError, .outputError,
                       "lastError should carry the service's error")
        XCTAssertNil(sut.pollingTask,
                     "polling should stop once the error state is reflected")
    }

    /// `testPollingStillDetectsStopped`
    ///
    /// Given the app believes it is playing while the service reports
    /// `.stopped` (natural completion of the last track),
    /// when a polling tick runs,
    /// then the existing completion behaviour is unchanged: playback
    /// stops and `currentTrack` is cleared.
    func testPollingStillDetectsStopped() async throws {
        await loadAndPlay()
        fakePlaybackService.state = .stopped

        try await Task.sleep(nanoseconds: 600_000_000) // ≥ one 0.25s tick

        XCTAssertEqual(sut.playbackState, .stopped,
                       "natural completion should still be detected")
        XCTAssertNil(sut.currentTrack,
                     "completion of the last track should clear currentTrack")
    }
}
