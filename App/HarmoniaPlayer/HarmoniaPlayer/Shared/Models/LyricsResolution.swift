//
//  LyricsResolution.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//
//  Result of a lyrics availability check and optional content resolution.
//  Produced by LyricsService.resolveAvailability(for:).
//

import Foundation

/// Describes what lyrics are available for a track and which is selected.
///
/// **β strategy (9-J):** `resolveAvailability` fills everything except
/// `content`, which is `nil` until the user opens `LyricsPanel`. At that
/// point `resolveContent` is called and AppState stores the loaded content
/// in an updated `LyricsResolution`.
///
/// `hasAny` drives button visibility — checked synchronously on track load.
struct LyricsResolution {

    /// Whether any lyrics source (USLT or sidecar `.lrc`) is available.
    /// Drives the toggle-button visibility in `PlayerView`.
    let hasAny: Bool

    /// The currently selected source, or `nil` when `hasAny == false`.
    let currentSource: LyricsSource?

    /// All sources that are available for this track.
    let availableSources: Set<LyricsSource>

    /// Language codes available for the current source.
    ///
    /// Non-empty only when `currentSource == .embedded` and the file
    /// contains multiple USLT variants. Each element is an ISO 639-2 code
    /// or `nil` for frames with no declared language.
    let availableLanguages: [String?]

    /// The currently selected language code, or `nil` when not applicable.
    ///
    /// `nil` is valid when:
    /// - source is `.lrc` (no language variants in 9-J), or
    /// - source is `.embedded` with a single variant whose `languageCode` is `nil`.
    let currentLanguage: String?

    /// Resolved display text, or `nil` when not yet loaded (lazy).
    ///
    /// `nil` on first `resolveAvailability` call. Populated after
    /// `resolveContent` is called (on panel open).
    let content: String?

    /// Convenience — no lyrics available at all.
    static let none = LyricsResolution(
        hasAny: false,
        currentSource: nil,
        availableSources: [],
        availableLanguages: [],
        currentLanguage: nil,
        content: nil
    )
}
