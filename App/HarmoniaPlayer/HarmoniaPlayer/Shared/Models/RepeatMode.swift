//
//  RepeatMode.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// Playback repeat mode.
///
/// Controls what happens when a track finishes playing naturally.
///
/// - `off`: Advance to next track; stop after the last track.
/// - `all`: Advance to next track; loop back to first after the last.
/// - `one`: Repeat the current track indefinitely.
enum RepeatMode: String, Equatable, Sendable, Codable {
    case off
    case all
    case one
}
