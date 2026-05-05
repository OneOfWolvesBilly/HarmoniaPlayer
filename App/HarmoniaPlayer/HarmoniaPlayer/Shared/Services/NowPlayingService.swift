//
//  NowPlayingService.swift
//  HarmoniaPlayer / Shared / Services
//
//  Slice 9-L: macOS Now Playing widget + system media keys integration.
//
//  Application-layer protocol describing the contract between AppState
//  and the system Now Playing surface (Control Center widget, lock
//  screen, AirPods, media keys, Siri).
//
//  AppState depends on this protocol only — never on `MediaPlayer`
//  framework directly. The production implementation
//  (`MPNowPlayingAdapter`) lives in the Integration Layer and is the
//  only file allowed to import `MediaPlayer`.
//

import Foundation

/// Application-facing contract for system Now Playing integration.
///
/// **Push direction (AppState → service):** AppState informs the
/// adapter of metadata and playback state changes via
/// `updateCurrentTrack(_:)`, `updatePlaybackState(_:rate:)`,
/// `updateElapsedTime(_:)`, and `clear()`.
///
/// **Pull direction (service → AppState):** the adapter exposes
/// closure-typed callbacks that AppState wires to its own action
/// methods. When the system widget receives a user action (play tap,
/// scrubber drag, AirPods press, Siri command), the adapter invokes
/// the corresponding callback.
///
/// **Update cadence:** pure event-driven. AppState pushes elapsed
/// time only on track change (with 0), playback state change (with
/// current `currentTime`), and successful `seek(to:)` (with new
/// position). The system interpolates between updates.
protocol NowPlayingService: AnyObject {

    // MARK: - Push (AppState → service)

    /// Refresh title / artist / album / duration / artwork for the
    /// new track. Implementations also push initial elapsed time = 0
    /// and a playback rate matching the next state transition.
    ///
    /// Passing `nil` is a separate code path from `clear()`:
    /// AppState calls `clear()` directly when stopping, and calls
    /// `updateCurrentTrack(nil)` only if the published `currentTrack`
    /// becomes nil through other means (e.g. playlist clear).
    func updateCurrentTrack(_ track: Track?)

    /// Push the new playback state and corresponding rate
    /// (1.0 playing / 0.0 paused/stopped). Implementations re-anchor
    /// the system's elapsed-time interpolation by also pushing the
    /// caller-supplied `elapsedSeconds` value via
    /// `updateElapsedTime(_:)` semantics.
    func updatePlaybackState(_ state: PlaybackState, rate: Double)

    /// Re-anchor the system's elapsed-time interpolation to the
    /// supplied position, in seconds.
    ///
    /// Called by AppState on track change (with 0), on playback
    /// state change (with current `currentTime`), and on successful
    /// `seek(to:)` (with the new position). Never called from the
    /// existing 1 Hz UI polling loop.
    func updateElapsedTime(_ seconds: Double)

    /// Clear the entire Now Playing info dictionary. Used on
    /// `stop()` and on `currentTrack = nil`.
    func clear()

    // MARK: - Pull (service → AppState)

    /// Invoked when the system delivers a play command
    /// (Control Center, lock screen, AirPods, media key, Siri).
    var onPlay: (() -> Void)? { get set }

    /// Invoked when the system delivers a pause command.
    var onPause: (() -> Void)? { get set }

    /// Invoked when the system delivers a toggle command.
    /// AirPods single-press maps here in macOS.
    var onTogglePlayPause: (() -> Void)? { get set }

    /// Invoked when the system delivers a next-track command.
    var onNext: (() -> Void)? { get set }

    /// Invoked when the system delivers a previous-track command.
    var onPrevious: (() -> Void)? { get set }

    /// Invoked when the system delivers a stop command.
    var onStop: (() -> Void)? { get set }

    /// Invoked when the user drags the system scrubber. Argument is
    /// the requested position in seconds.
    var onSeek: ((Double) -> Void)? { get set }
}
