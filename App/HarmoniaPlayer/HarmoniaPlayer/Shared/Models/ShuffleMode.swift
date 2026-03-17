//
//  ShuffleMode.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// Whether shuffle mode is enabled.
///
/// When `.on`, `AppState.playNextTrack()` picks a random track
/// from the playlist excluding the current track.
/// When `.off`, tracks play in playlist order.
typealias ShuffleMode = Bool

extension ShuffleMode {
    /// Shuffle disabled — tracks play in playlist order.
    static let off: ShuffleMode = false
    /// Shuffle enabled — next track is picked randomly.
    static let on: ShuffleMode = true
}
