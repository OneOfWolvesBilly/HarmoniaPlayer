//
//  LyricsPreference.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//
//  Per-track user preference for lyrics display.
//  Persisted via LyricsPreferenceStore (UserDefaults-backed).
//

import Foundation

/// Per-track user preference for lyrics source, encoding, and language.
///
/// Stored as JSON in `UserDefaults` under key
/// `hp.lyrics.prefs.<absolute-file-path>[#track=<n>]`.
///
/// - `source`: which source the user last selected (`.embedded` or `.lrc`).
/// - `encoding`: IANA charset name, or `"auto"` for automatic detection.
/// - `languageCode`: ISO 639-2 code; `nil` means auto (system locale match).
/// - `customPath`: reserved for v0.15 custom file selection; always `nil` in 9-J.
struct LyricsPreference: Codable, Equatable {
    var source: LyricsSource
    var encoding: String        // IANA charset name; "auto" = auto-detect
    var languageCode: String?   // ISO 639-2; nil = auto (locale match)
    var customPath: String?     // reserved for v0.15, always nil in 9-J

    init(
        source: LyricsSource,
        encoding: String = "auto",
        languageCode: String? = nil,
        customPath: String? = nil
    ) {
        self.source = source
        self.encoding = encoding
        self.languageCode = languageCode
        self.customPath = customPath
    }
}
