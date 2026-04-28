//
//  LyricsLanguageVariant.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE
//  -------
//  Application Layer representation of one language variant of embedded
//  USLT lyrics. Mirrors HarmoniaCore.LyricsLanguageVariant but lives in
//  the Application Layer so that Track and AppState can use it without
//  importing HarmoniaCore.
//
//  The Integration Layer (HarmoniaTagReaderAdapter) is responsible for
//  mapping HarmoniaCore.LyricsLanguageVariant → this type.
//

import Foundation

/// A single language variant of embedded lyrics (USLT frame).
///
/// - `languageCode`: ISO 639-2 three-letter code (e.g. `"eng"`, `"chi"`, `"jpn"`).
///   `nil` when the USLT frame declares no language.
/// - `text`: raw lyrics text. May contain LRC-style timestamps when the
///   source is a sidecar `.lrc` file; `LyricsService` strips them before display.
struct LyricsLanguageVariant: Codable, Equatable, Sendable {

    /// ISO 639-2 language code, or `nil` if undeclared.
    let languageCode: String?

    /// Raw lyrics text (not yet stripped of timestamps).
    let text: String

    init(languageCode: String?, text: String) {
        self.languageCode = languageCode
        self.text = text
    }
}
