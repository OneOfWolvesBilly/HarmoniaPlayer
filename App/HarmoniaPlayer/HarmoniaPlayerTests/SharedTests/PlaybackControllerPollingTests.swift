//
//  PlaybackControllerPollingTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the `PlaybackController` polling task lifecycle: the task is
/// cancelled on `stop()`, exits cleanly when cancelled externally, and
/// reflects the service's state on every tick.
@MainActor
final class PlaybackControllerPollingTests: XCTestCase {

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

    /// Seeds one track and starts playback so `pollingTask` is active.
    private func loadAndPlay(_ f: Fixture) async {
        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"))
        f.context.playlists[0].tracks = [track]
        await f.sut.play(trackID: track.id)
    }

    // MARK: - Tests

    func testStopPolling_CancelsTask() async {
        let f = makeSUT()
        await loadAndPlay(f)
        XCTAssertNotNil(f.sut.pollingTask, "pollingTask should be active during playback")

        await f.sut.stop()

        XCTAssertNil(f.sut.pollingTask, "pollingTask should be cleared after stop()")
    }

    func testPolling_StopsOnCancellation() async {
        let f = makeSUT()
        await loadAndPlay(f)
        let task = f.sut.pollingTask
        XCTAssertNotNil(task, "pollingTask should be active during playback")

        task?.cancel()
        await task?.value

        XCTAssertTrue(task?.isCancelled ?? false, "task should be cancelled after external cancel()")
    }

    func testPollingReflectsServicePaused() async throws {
        let f = makeSUT()
        await loadAndPlay(f)
        f.fake.state = .paused

        try await Task.sleep(nanoseconds: 600_000_000) // ≥ one 0.25s tick

        XCTAssertEqual(f.sut.playbackState, .paused,
                       "polling should reflect the service's paused state")
        XCTAssertNil(f.sut.pollingTask,
                     "polling should stop once the paused state is reflected")
    }

    func testPollingReflectsServiceError() async throws {
        let f = makeSUT()
        await loadAndPlay(f)
        f.fake.state = .error(.outputError)

        try await Task.sleep(nanoseconds: 600_000_000) // ≥ one 0.25s tick

        XCTAssertEqual(f.sut.playbackState, .error(.outputError),
                       "polling should reflect the service's error state")
        XCTAssertEqual(f.alertCenter.lastError, .outputError,
                       "lastError should carry the service's error")
        XCTAssertNil(f.sut.pollingTask,
                     "polling should stop once the error state is reflected")
    }

    func testPollingStillDetectsStopped() async throws {
        let f = makeSUT()
        await loadAndPlay(f)
        f.fake.state = .stopped

        try await Task.sleep(nanoseconds: 600_000_000) // ≥ one 0.25s tick

        XCTAssertEqual(f.sut.playbackState, .stopped,
                       "natural completion should still be detected")
        XCTAssertNil(f.sut.currentTrack,
                     "completion of the last track should clear currentTrack")
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
