//
//  LyricsSource.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// The source from which lyrics content is resolved.
enum LyricsSource: String, Codable, Sendable {
    /// Embedded USLT frame(s) in the audio file.
    case embedded
    /// Sidecar `.lrc` file found alongside the audio file.
    case lrc
}
