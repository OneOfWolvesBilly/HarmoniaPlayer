//
//  PlaybackService.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Playback service interface
///
/// Abstracts audio playback operations. Implementations are provided by
/// HarmoniaCore-Swift or mock implementations for testing.
///
/// **Lifecycle:**
/// - `load()` prepares a track
/// - `play()` starts playback
/// - `pause()` pauses (preserves position)
/// - `stop()` stops and releases resources
///
/// **Thread Safety:**
/// All methods are async and safe to call from any thread.
protocol PlaybackService {
    
    /// Load and prepare a track for playback
    ///
    /// - Parameter url: URL of the audio file
    /// - Throws: PlaybackError if file cannot be loaded
    func load(url: URL) async throws
    
    /// Start playback
    ///
    /// If already playing, this is a no-op.
    ///
    /// - Throws: PlaybackError if playback cannot start
    func play() async throws
    
    /// Pause playback
    ///
    /// Safe to call when already paused. Position is preserved.
    func pause() async
    
    /// Stop playback and release resources
    ///
    /// Resets playback position to beginning.
    func stop() async
    
    /// Seek to absolute time
    ///
    /// - Parameter seconds: Target position in seconds
    /// - Throws: PlaybackError if seek fails
    func seek(to seconds: TimeInterval) async throws
    
    /// Current playback time
    ///
    /// - Returns: Current position in seconds
    func currentTime() async -> TimeInterval
    
    /// Track duration
    ///
    /// - Returns: Total duration in seconds, or 0 if no track loaded
    func duration() async -> TimeInterval
    
    /// Current playback state
    ///
    /// For debugging and UI synchronization.
    var state: PlaybackState { get }
}
