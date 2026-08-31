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
        showLyrics.toggle()
    }

    /// Re-runs lyrics availability detection for the given track — the
    /// user-intent entry point behind the panel's Recheck button. Useful when
    /// the user has just added a sidecar `.lrc` file or fixed embedded USLT
    /// metadata while a track was already loaded. Delegates to
    /// `updateResolution(for:)`.
    func recheckLyrics(for track: Track?) {
        updateResolution(for: track)
    }

    /// Switches the active lyrics source (`.embedded` ↔ `.lrc`) for the
    /// given track. No-op when the source is not available. Persists the
    /// choice via `LyricsPreferenceStore`.
    func setLyricsSource(_ source: LyricsSource, for track: Track?) {
        guard let track,
              var resolution = lyricsResolution,
              resolution.availableSources.contains(source) else { return }

        // Recompute language list when switching to/from embedded
        let availableLanguages: [String?]
        let currentLanguage: String?
        if source == .embedded, let variants = track.lyrics, !variants.isEmpty {
            availableLanguages = variants.map { $0.languageCode }
            currentLanguage = resolution.currentLanguage
                ?? variants.first?.languageCode
        } else {
            availableLanguages = []
            currentLanguage = nil
        }

        resolution = LyricsResolution(
            hasAny: true,
            currentSource: source,
            availableSources: resolution.availableSources,
            availableLanguages: availableLanguages,
            currentLanguage: currentLanguage,
            content: nil
        )
        lyricsResolution = resolution

        // Persist
        let pref = LyricsPreference(
            source: source,
            encoding: persistedEncoding(for: track) ?? "auto",
            languageCode: currentLanguage,
            customPath: nil
        )
        lyricsPreferenceStore.save(pref, for: track)
    }

    /// Selects a USLT language variant for the given track. No-op when the
    /// current source is not `.embedded`. Persists the choice via
    /// `LyricsPreferenceStore`.
    func setLyricsLanguage(_ languageCode: String?, for track: Track?) {
        guard let track,
              var resolution = lyricsResolution,
              resolution.currentSource == .embedded else { return }

        resolution = LyricsResolution(
            hasAny: true,
            currentSource: .embedded,
            availableSources: resolution.availableSources,
            availableLanguages: resolution.availableLanguages,
            currentLanguage: languageCode,
            content: nil
        )
        lyricsResolution = resolution

        let pref = LyricsPreference(
            source: .embedded,
            encoding: persistedEncoding(for: track) ?? "auto",
            languageCode: languageCode,
            customPath: nil
        )
        lyricsPreferenceStore.save(pref, for: track)
    }

    /// Sets the `.lrc` file decoding charset for the given track. Persists
    /// the choice. `"auto"` triggers auto-detection on next read.
    func setLyricsEncoding(_ encoding: String, for track: Track?) {
        guard let track,
              let resolution = lyricsResolution else { return }
        let pref = LyricsPreference(
            source: resolution.currentSource ?? .lrc,
            encoding: encoding,
            languageCode: resolution.currentLanguage,
            customPath: nil
        )
        lyricsPreferenceStore.save(pref, for: track)
    }

    /// Recomputes `lyricsResolution` for the given track, applying any
    /// persisted preference. `nil` clears the resolution.
    ///
    /// Called by the `AppState` `$currentTrack` sink on track change and by
    /// `recheckLyrics(for:)`; also exposed to tests so they can verify the
    /// recomputation logic synchronously.
    func updateResolution(for track: Track?) {
        guard let track else {
            lyricsResolution = nil
            return
        }

        var resolution = lyricsService.resolveAvailability(for: track)

        // Apply persisted preference (overrides defaults from
        // resolveAvailability) — only when sources match what's actually available.
        if let pref = lyricsPreferenceStore.load(for: track),
           resolution.availableSources.contains(pref.source) {
            let newLang: String?
            let newAvailableLangs: [String?]
            if pref.source == .embedded, let variants = track.lyrics, !variants.isEmpty {
                newAvailableLangs = variants.map { $0.languageCode }
                newLang = pref.languageCode ?? resolution.currentLanguage
            } else {
                newAvailableLangs = []
                newLang = nil
            }
            resolution = LyricsResolution(
                hasAny: true,
                currentSource: pref.source,
                availableSources: resolution.availableSources,
                availableLanguages: newAvailableLangs,
                currentLanguage: newLang,
                content: nil
            )
        }

        lyricsResolution = resolution
    }

    /// Returns the persisted encoding name for the given track, or `nil` if
    /// no preference is stored. Used to keep encoding stable when the user
    /// changes only source or language.
    private func persistedEncoding(for track: Track) -> String? {
        lyricsPreferenceStore.load(for: track)?.encoding
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}
}
