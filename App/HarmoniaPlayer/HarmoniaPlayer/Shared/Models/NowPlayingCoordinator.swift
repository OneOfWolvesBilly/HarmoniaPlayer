//
//  NowPlayingCoordinator.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  @MainActor final class that owns all NowPlaying-related wiring
//  for Slice 9-L. Coordinates between two boundaries:
//
//    - NowPlayingService      — Application Layer abstraction over
//                               the system Now Playing surface
//                               (Control Center widget, lock screen,
//                               AirPods, media keys, Siri).
//    - AppState publishers
//      and action closures    — Injected via constructor so this
//                               coordinator never holds an AppState
//                               reference and never imports AppState.
//
//  Lives in `Shared/Models/` (not `Services/`) for the same reason
//  AppState and EQCoordinator live there — coordinators are lifecycle
//  participants, not stateless service utilities.
//
//  SCOPE
//  -----
//  AppState holds a single `let nowPlayingCoordinator: NowPlayingCoordinator`
//  reference. AppState itself has no NowPlaying-specific @Published
//  properties, observation logic, or callback assignment — only the
//  coordinator construction in `init` and one
//  `nowPlayingCoordinator.notifySeekCompleted(at:)` call inside
//  `seek(to:)` after a successful seek (spec §9-L).
//
//  WIRING DIRECTION
//  ----------------
//  PUSH (AppState publishers → service):
//    - On `currentTrackPublisher` event: refresh metadata, push
//      initial elapsed time = 0; on nil → clear widget.
//    - On `playbackStatePublisher` event: push state + rate, then
//      re-anchor elapsed time via `currentTimeProvider`; on
//      `.stopped` → clear widget.
//    - On `notifySeekCompleted(at:)` (called by AppState directly,
//      not via publisher): push new elapsed time. Seek success is
//      not derivable from `playbackStatePublisher` alone.
//
//  PULL (service callbacks → injected closures):
//    - The service exposes `onPlay` / `onPause` / `onTogglePlayPause`
//      / `onNext` / `onPrevious` / `onStop` / `onSeek` callbacks.
//      The coordinator assigns each to the corresponding injected
//      closure (capturing `[weak self]` from AppState init).
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - `@MainActor` annotation explicit. All injected action closures
//    are `@MainActor () async -> Void` so the coordinator can call
//    them directly without crossing isolation boundaries.
//  - Explicit `nonisolated deinit { }` mirrors EQCoordinator's
//    workaround for the Xcode 26 beta `swift_task_deinitOnExecutorImpl`
//    crash on synthesised MainActor deinit.
//

import Foundation
import Combine

@MainActor
final class NowPlayingCoordinator {

    // MARK: - Injected dependencies

    private let service: NowPlayingService
    private let currentTimeProvider: @MainActor () -> TimeInterval

    // MARK: - Subscriptions

    /// Holds publisher subscriptions for `currentTrackPublisher` and
    /// `playbackStatePublisher`. Released automatically when this
    /// coordinator is deallocated.
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    /// Construct a coordinator with all dependencies injected.
    ///
    /// Action closures are `@MainActor () async -> Void` so the
    /// coordinator can call them directly when the corresponding
    /// system command arrives, without re-hopping isolation. Inside
    /// the init body the closures are wrapped in
    /// `Task { @MainActor in await ... }` because the service
    /// callbacks (`onPlay` / `onPause` / etc.) are synchronous
    /// signatures imposed by `MPRemoteCommandCenter`.
    init(
        service: NowPlayingService,
        currentTrackPublisher: AnyPublisher<Track?, Never>,
        playbackStatePublisher: AnyPublisher<PlaybackState, Never>,
        currentTimeProvider: @escaping @MainActor () -> TimeInterval,
        play: @escaping @MainActor () async -> Void,
        pause: @escaping @MainActor () async -> Void,
        stop: @escaping @MainActor () async -> Void,
        seek: @escaping @MainActor (TimeInterval) async -> Void,
        next: @escaping @MainActor () async -> Void,
        previous: @escaping @MainActor () async -> Void,
        togglePlayPause: @escaping @MainActor () async -> Void
    ) {
        self.service = service
        self.currentTimeProvider = currentTimeProvider

        // Push side: subscribe to currentTrack publisher.
        //
        // On non-nil: refresh metadata + re-anchor elapsed time to 0
        // (matches spec — every track change resets the system's
        // interpolation baseline).
        // On nil: clear the widget entirely.
        currentTrackPublisher
            .receive(on: RunLoop.main)
            .sink { [weak service] track in
                guard let service else { return }
                if let track {
                    service.updateCurrentTrack(track)
                    service.updateElapsedTime(0)
                } else {
                    service.clear()
                }
            }
            .store(in: &cancellables)

        // Push side: subscribe to playbackState publisher.
        //
        // For every state transition: push state + corresponding
        // rate, then re-anchor elapsed time to whatever
        // currentTimeProvider reports (so the system's interpolation
        // restarts from a known point).
        // On .stopped: also clear the widget per spec.
        playbackStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak service, weak self] state in
                guard let service, let self else { return }
                let rate: Double = (state == .playing) ? 1.0 : 0.0
                service.updatePlaybackState(state, rate: rate)
                service.updateElapsedTime(self.currentTimeProvider())
                if state == .stopped {
                    service.clear()
                }
            }
            .store(in: &cancellables)

        // Pull side: route service callbacks to injected closures.
        //
        // `Task { @MainActor in await ... }` is used so async closures
        // can be invoked from synchronous callback sites (the closures
        // exposed by `MPRemoteCommandCenter` handlers are sync).
        service.onPlay = {
            Task { @MainActor in await play() }
        }
        service.onPause = {
            Task { @MainActor in await pause() }
        }
        service.onStop = {
            Task { @MainActor in await stop() }
        }
        service.onSeek = { seconds in
            Task { @MainActor in await seek(seconds) }
        }
        service.onNext = {
            Task { @MainActor in await next() }
        }
        service.onPrevious = {
            Task { @MainActor in await previous() }
        }
        service.onTogglePlayPause = {
            Task { @MainActor in await togglePlayPause() }
        }
    }

    // MARK: - Public surface

    /// Notify the coordinator that AppState's `seek(to:)` has
    /// completed successfully. Pushes the new elapsed time to the
    /// system so the widget scrubber re-anchors interpolation.
    ///
    /// Called from `AppState.seek(to:)` after the underlying
    /// playback service reports success. This is the single point
    /// of direct AppState → Coordinator notification — every other
    /// signal flows through the injected publishers.
    func notifySeekCompleted(at seconds: TimeInterval) {
        service.updateElapsedTime(seconds)
    }

    // MARK: - Deinit (Xcode 26 beta workaround)

    /// Synthesised MainActor deinit routes through
    /// `swift_task_deinitOnExecutorImpl` which crashes in Xcode 26
    /// beta. Explicit `nonisolated deinit { }` falls back to the
    /// synchronous ARC path. Same workaround as EQCoordinator and
    /// FakeEQService.
    nonisolated deinit { }
}
