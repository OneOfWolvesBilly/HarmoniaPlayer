//
//  HarmoniaPlaybackServiceAdapter.swift
//  HarmoniaPlayer / Shared / Services
//
//  Created on 2026-03-12.
//
//  PURPOSE
//  -------
//  Bridges HarmoniaCore.PlaybackService (synchronous) to the async
//  HarmoniaPlayer.PlaybackService protocol that AppState depends on.
//
//  DESIGN NOTES
//  ------------
//  - This file, HarmoniaTagReaderAdapter.swift, and HarmoniaCoreProvider.swift
//    are the ONLY production files in HarmoniaPlayer that may import HarmoniaCore.
//    All other layers depend solely on the HarmoniaPlayer.PlaybackService protocol.
//  - The stored property is typed as `HarmoniaCore.PlaybackService` (fully
//    qualified) to avoid ambiguity with HarmoniaPlayer.PlaybackService, which
//    shares the same short name inside this module.
//  - Bridging sync → async is straightforward: Swift's structured concurrency
//    allows calling synchronous functions directly from an async context, so
//    each async protocol method simply delegates to the synchronous core method.
//

import Foundation
import HarmoniaCore

/// Bridges the synchronous `HarmoniaCore.PlaybackService` to the async
/// `HarmoniaPlayer.PlaybackService` protocol consumed by `AppState`.
///
/// Maps `HarmoniaCore.PlaybackState` to `HarmoniaPlayer.PlaybackState`:
///
/// | HarmoniaCore  | HarmoniaPlayer              |
/// |---------------|-----------------------------|
/// | .stopped      | .stopped                    |
/// | .playing      | .playing                    |
/// | .paused       | .paused                     |
/// | .buffering    | .loading                    |
/// | .error(e)     | .error(.coreError(e.description)) |
final class HarmoniaPlaybackServiceAdapter: PlaybackService {

    // MARK: - Dependencies

    /// Wrapped synchronous core service.
    /// Fully qualified to disambiguate from HarmoniaPlayer.PlaybackService.
    private let core: HarmoniaCore.PlaybackService

    // MARK: - Initialization

    /// Creates an adapter wrapping the given synchronous core service.
    /// - Parameter core: A `HarmoniaCore.PlaybackService` instance (e.g. `DefaultPlaybackService`).
    init(core: HarmoniaCore.PlaybackService) {
        self.core = core
    }

    // MARK: - PlaybackService (state)

    /// Maps the core synchronous state to the async HarmoniaPlayer state.
    var state: PlaybackState {
        switch core.state {
        case .stopped:          return .stopped
        case .playing:          return .playing
        case .paused:           return .paused
        case .buffering:        return .loading          // HarmoniaCore uses .buffering; player uses .loading
        case .error(let e):     return .error(.coreError(e.description))
        }
    }

    // MARK: - PlaybackService (async methods)

    /// Loads a track URL. Delegates directly to the synchronous core method.
    func load(url: URL) async throws              { try core.load(url: url) }

    /// Starts playback. Delegates directly to the synchronous core method.
    func play() async throws                      { try core.play() }

    /// Pauses playback. Non-throwing; delegates to the synchronous core method.
    func pause() async                            { core.pause() }

    /// Stops playback and releases resources. Non-throwing; delegates to the synchronous core method.
    func stop() async                             { core.stop() }

    /// Seeks to an absolute position. Delegates directly to the synchronous core method.
    func seek(to seconds: TimeInterval) async throws { try core.seek(to: seconds) }

    /// Returns current playback position. Delegates to the synchronous core method.
    func currentTime() async -> TimeInterval      { core.currentTime() }

    /// Returns the duration of the loaded track. Delegates to the synchronous core method.
    func duration() async -> TimeInterval         { core.duration() }

    /// Sets the playback volume. Delegates to the synchronous core method.
    func setVolume(_ volume: Float) async         { core.setVolume(volume) }
}