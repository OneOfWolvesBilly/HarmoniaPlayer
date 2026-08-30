//
//  LyricsStore.swift
//  HarmoniaPlayer / Shared / Models
//

import Foundation

/// Store owning the lyrics panel visibility, the current track's lyrics
/// resolution, and the lyrics service dependencies.
///
/// Extracted from `AppState`. Views whose body reads lyrics state observe
/// this store directly via `@Environment(LyricsStore.self)`, so lyrics-state
/// changes no longer re-render views observing unrelated `AppState`
/// properties.
///
/// The store never reads current-track state: every track-dependent method
/// takes the track explicitly, and callers (the `AppState` `$currentTrack`
/// sink, the views) supply the current track themselves.
@MainActor @Observable
final class LyricsStore {

    // MARK: - State

    /// Whether the lyrics panel is currently visible.
    ///
    /// Toggled by `toggleLyrics()`. Initialised to `false`.
    var showLyrics = false

    /// Lyrics availability + selected source/language for the caller-supplied
    /// track.
    ///
    /// `nil` when no track is loaded. Recomputed by `updateResolution(for:)`,
    /// applying any persisted `LyricsPreference` for the track.
    /// `lyricsResolution?.hasAny` drives the lyrics panel's content-vs-empty
    /// state (the "No lyrics available" + Recheck placeholder), not the toggle
    /// button's visibility — the button is always shown and is disabled only
    /// when no track is loaded.
    var lyricsResolution: LyricsResolution?

    // MARK: - Dependencies

    /// Lyrics service — resolves USLT + sidecar `.lrc` content.
    let lyricsService: LyricsService

    /// Lyrics preference store — per-track source/encoding/language
    /// persistence.
    let lyricsPreferenceStore: LyricsPreferenceStore

    // MARK: - Initialization

    init(lyricsService: LyricsService,
         lyricsPreferenceStore: LyricsPreferenceStore) {
        self.lyricsService = lyricsService
        self.lyricsPreferenceStore = lyricsPreferenceStore
    }

    // MARK: - Actions

    /// Toggles the lyrics panel visibility.
    func toggleLyrics() {
    }

    /// Re-runs lyrics availability detection for the given track — the
    /// user-intent entry point behind the panel's Recheck button. Useful when
    /// the user has just added a sidecar `.lrc` file or fixed embedded USLT
    /// metadata while a track was already loaded. Delegates to
    /// `updateResolution(for:)`.
    func recheckLyrics(for track: Track?) {
    }

    /// Switches the active lyrics source (`.embedded` ↔ `.lrc`) for the
    /// given track. No-op when the source is not available. Persists the
    /// choice via `LyricsPreferenceStore`.
    func setLyricsSource(_ source: LyricsSource, for track: Track?) {
    }

    /// Selects a USLT language variant for the given track. No-op when the
    /// current source is not `.embedded`. Persists the choice via
    /// `LyricsPreferenceStore`.
    func setLyricsLanguage(_ languageCode: String?, for track: Track?) {
    }

    /// Sets the `.lrc` file decoding charset for the given track. Persists
    /// the choice. `"auto"` triggers auto-detection on next read.
    func setLyricsEncoding(_ encoding: String, for track: Track?) {
    }

    /// Recomputes `lyricsResolution` for the given track, applying any
    /// persisted preference. `nil` clears the resolution.
    func updateResolution(for track: Track?) {
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}
}
