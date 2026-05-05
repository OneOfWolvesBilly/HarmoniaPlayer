//
//  FakeNowPlayingService.swift
//  HarmoniaPlayerTests / FakeInfrastructure
//
//  Slice 9-L: test fake for AppState wiring assertions.
//
//  Records every push call (updateCurrentTrack / updatePlaybackState /
//  updateElapsedTime / clear) for verification, and exposes the same
//  pull-direction callbacks (`onPlay`, `onPause`, `onTogglePlayPause`,
//  `onNext`, `onPrevious`, `onStop`, `onSeek`) that the production
//  `MPNowPlayingAdapter` will eventually own.
//
//  Tests assert on call counts and last-argument captures rather than
//  hooking the real `MPNowPlayingInfoCenter` — that boundary is the
//  domain of the production adapter, not unit tests.
//

import Foundation
@testable import HarmoniaPlayer

/// Test fake for `NowPlayingService`.
///
/// **Push side — call recording:**
/// - `updateCurrentTrackCallCount` / `lastUpdatedTrack`
/// - `updatePlaybackStateCallCount` / `lastUpdatedState` / `lastUpdatedRate`
/// - `updateElapsedTimeCallCount` / `lastUpdatedElapsed` / `updatedElapsedHistory`
/// - `clearCallCount`
///
/// **Pull side — callbacks:** the same closure properties from the
/// `NowPlayingService` protocol; tests invoke them directly to
/// simulate system commands.
final class FakeNowPlayingService: NowPlayingService {

    // MARK: - updateCurrentTrack recording

    private(set) var updateCurrentTrackCallCount = 0
    private(set) var lastUpdatedTrack: Track??

    func updateCurrentTrack(_ track: Track?) {
        updateCurrentTrackCallCount += 1
        lastUpdatedTrack = .some(track)
    }

    // MARK: - updatePlaybackState recording

    private(set) var updatePlaybackStateCallCount = 0
    private(set) var lastUpdatedState: PlaybackState?
    private(set) var lastUpdatedRate: Double?

    func updatePlaybackState(_ state: PlaybackState, rate: Double) {
        updatePlaybackStateCallCount += 1
        lastUpdatedState = state
        lastUpdatedRate = rate
    }

    // MARK: - updateElapsedTime recording

    private(set) var updateElapsedTimeCallCount = 0
    private(set) var lastUpdatedElapsed: Double?
    private(set) var updatedElapsedHistory: [Double] = []

    func updateElapsedTime(_ seconds: Double) {
        updateElapsedTimeCallCount += 1
        lastUpdatedElapsed = seconds
        updatedElapsedHistory.append(seconds)
    }

    // MARK: - clear recording

    private(set) var clearCallCount = 0

    func clear() {
        clearCallCount += 1
    }

    // MARK: - Pull-side callbacks

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onStop: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    // MARK: - Xcode 26 beta isolated-deinit workaround

    /// Module-level `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would
    /// otherwise route the synthesised deinit through
    /// `swift_task_deinitOnExecutorImpl`, which the runtime crashes on.
    /// Same workaround as `FakeEQService`.
    nonisolated deinit { }
}
