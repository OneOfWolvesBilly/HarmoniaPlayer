//
//  LyricsPreferenceStore.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Per-track persistence for lyrics preferences (source / encoding / language).
//  Backed by UserDefaults; keyed by absolute file path with optional
//  `#track=<n>` suffix for CUE virtual tracks (latent in 9-J, activated v0.15).
//
//  KEY FORMAT
//  ----------
//  - Non-CUE track:  hp.lyrics.prefs.<absolute-file-path>
//      e.g. "hp.lyrics.prefs./Music/song.mp3"
//  - CUE virtual track:  hp.lyrics.prefs.<absolute-file-path>#track=<n>
//      e.g. "hp.lyrics.prefs./Music/Album.flac#track=3"
//
//  Track does not yet carry a `cueTrackNumber` field in 9-J — the key
//  generator handles non-CUE only. v0.15 adds the suffix branch.
//
//  SCOPE
//  -----
//  Preferences are keyed by file path (and CUE track number when applicable),
//  shared across all playlists. The same file appearing in playlist A and
//  playlist B uses identical preference.
//

import Foundation

/// Per-track persistence for `LyricsPreference`.
protocol LyricsPreferenceStore: AnyObject {
    /// Returns the UserDefaults key for the given track.
    func key(for track: Track) -> String

    /// Loads the persisted preference for the given track, or `nil` if absent
    /// or unreadable.
    func load(for track: Track) -> LyricsPreference?

    /// Saves the given preference for the given track.
    /// Failures (e.g. encoder errors) are silently ignored — preferences are
    /// best-effort and must not break playback.
    func save(_ pref: LyricsPreference, for track: Track)
}

// MARK: - Default implementation

final class DefaultLyricsPreferenceStore: LyricsPreferenceStore {

    private static let keyPrefix = "hp.lyrics.prefs."

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func key(for track: Track) -> String {
        // Use track.url.path (decoded absolute file path).
        // CUE suffix branch (v0.15): when Track gains cueTrackNumber, append
        // "#track=<n>" here. 9-J ships without the suffix.
        return "\(Self.keyPrefix)\(track.url.path)"
    }

    func load(for track: Track) -> LyricsPreference? {
        let key = key(for: track)
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? decoder.decode(LyricsPreference.self, from: data)
    }

    func save(_ pref: LyricsPreference, for track: Track) {
        let key = key(for: track)
        guard let data = try? encoder.encode(pref) else { return }
        userDefaults.set(data, forKey: key)
    }
}
