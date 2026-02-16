//
//  PlaybackState.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Playback state enumeration
///
/// Represents the current state of audio playback.
///
/// **States:**
/// - `idle`: No track loaded
/// - `loading`: Track is being prepared
/// - `playing`: Audio is playing
/// - `paused`: Playback paused (position preserved)
/// - `stopped`: Playback stopped (position reset)
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
}
