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
/// **State mapping** (`HarmoniaCore.PlaybackState` → `HarmoniaPlayer.PlaybackState`):
///
/// | HarmoniaCore  | HarmoniaPlayer                       |
/// |---------------|--------------------------------------|
/// | .stopped      | .stopped                             |
/// | .playing      | .playing                             |
/// | .paused       | .paused                              |
/// | .buffering    | .loading                             |
/// | .error(e)     | .error(mapCoreError(e))               |
///
/// **Error mapping** (`CoreError` → `PlaybackError`):
///
/// | CoreError          | PlaybackError      |
/// |--------------------|--------------------|
/// | .notFound          | .failedToOpenFile  |
/// | .ioError           | .failedToOpenFile  |
/// | .unsupported       | .unsupportedFormat |
/// | .decodeError       | .failedToDecode    |
/// | .invalidState      | .invalidState      |
/// | .invalidArgument   | .invalidArgument   |
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
        case .error(let e):     return .error(Self.mapCoreError(e))
        }
    }

    // MARK: - PlaybackService (async methods)

    /// Loads a track URL. Catches `CoreError` and rethrows as `PlaybackError`.
    func load(url: URL) async throws {
        do {
            try core.load(url: url)
        } catch let error as CoreError {
            throw Self.mapCoreError(error)
        }
    }

    /// Starts playback. Catches `CoreError` and rethrows as `PlaybackError`.
    func play() async throws {
        do {
            try core.play()
        } catch let error as CoreError {
            throw Self.mapCoreError(error)
        }
    }

    /// Pauses playback. Non-throwing; delegates to the synchronous core method.
    func pause() async                            { core.pause() }

    /// Stops playback and releases resources. Non-throwing; delegates to the synchronous core method.
    func stop() async                             { core.stop() }

    /// Seeks to an absolute position. Catches `CoreError` and rethrows as `PlaybackError`.
    func seek(to seconds: TimeInterval) async throws {
        do {
            try core.seek(to: seconds)
        } catch let error as CoreError {
            throw Self.mapCoreError(error)
        }
    }

    /// Returns current playback position. Delegates to the synchronous core method.
    func currentTime() async -> TimeInterval      { core.currentTime() }

    /// Returns the duration of the loaded track. Delegates to the synchronous core method.
    func duration() async -> TimeInterval         { core.duration() }

    /// Sets the playback volume. Delegates to the synchronous core method.
    func setVolume(_ volume: Float) async         { core.setVolume(volume) }

    // MARK: - Error Mapping

    /// Maps a `HarmoniaCore.CoreError` to a `HarmoniaPlayer.PlaybackError`.
    ///
    /// This is the single boundary where Core error types are translated
    /// into application-level typed error codes. No `String` payload is
    /// carried across — technical details stay in HarmoniaCore's logger.
    static func mapCoreError(_ error: CoreError) -> PlaybackError {
        switch error {
        case .notFound:         return .failedToOpenFile
        case .ioError:          return .failedToOpenFile
        case .unsupported:      return .unsupportedFormat
        case .decodeError:      return .failedToDecode
        case .invalidState:     return .invalidState
        case .invalidArgument:  return .invalidArgument
        }
    }
}
