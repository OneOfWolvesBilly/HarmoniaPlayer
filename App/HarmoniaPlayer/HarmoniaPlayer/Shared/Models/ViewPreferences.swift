//
//  ViewPreferences.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-23.
//

import Foundation

/// Layout preset for the main player window
///
/// Controls which panels are visible and how the window is arranged.
/// Raw values are stable strings suitable for persistence (e.g. UserDefaults).
///
/// **Cases:**
/// - `compact`: Playlist only — minimal, distraction-free layout
/// - `standard`: Playlist + Now Playing — everyday use
/// - `waveformFocused`: All panels — waveform, playlist, and track info
enum LayoutPreset: String, CaseIterable, Equatable, Sendable {
    case compact
    case standard
    case waveformFocused
}

/// UI preference state for the main player window
///
/// Value type (struct). Stored in `AppState.viewPreferences` and
/// observed by SwiftUI views for layout decisions.
///
/// **Default** (via `.defaultPreferences`):
/// - `isWaveformVisible`: `true`
/// - `isPlaylistVisible`: `true`
/// - `layoutPreset`: `.standard`
///
/// **Usage:**
/// ```swift
/// // Read
/// if appState.viewPreferences.isWaveformVisible { ... }
///
/// // Mutate
/// appState.viewPreferences.layoutPreset = .compact
/// ```
struct ViewPreferences: Equatable, Sendable {
    var isWaveformVisible: Bool
    var isPlaylistVisible: Bool
    var layoutPreset: LayoutPreset

    /// Default preferences applied at app launch
    static let defaultPreferences = ViewPreferences(
        isWaveformVisible: true,
        isPlaylistVisible: true,
        layoutPreset: .standard
    )
}
