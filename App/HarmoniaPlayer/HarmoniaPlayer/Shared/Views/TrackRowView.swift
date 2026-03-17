//
//  TrackRowView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Single row in the playlist `List`. Displays track metadata and playback
//  state indicators so the user can identify tracks at a glance.
//
//  DESIGN NOTES
//  ------------
//  - This view is purely presentational; it receives all data via parameters
//    and emits no actions directly — tap handling is done by the parent
//    `PlaylistView` using `onTapGesture`.
//  - `isPlaying` controls the speaker icon; `isSelected` controls text colour
//    to ensure legibility against the system selection highlight.
//  - Duration is formatted as `m:ss` (e.g. `3:45`) using integer arithmetic
//    to avoid floating-point rounding artefacts in display.
//  - The `accessibilityIdentifier` uses the track UUID so XCUITest can target
//    a specific row without depending on displayed text.
//

import SwiftUI

/// A single row in the playlist `List`.
///
/// Displays the track's playing indicator, title, artist, and duration.
/// Selection highlight colour is adjusted so text remains legible when the
/// row is selected (white on accent background).
///
/// - Parameters:
///   - track: The `Track` whose metadata is displayed.
///   - isPlaying: When `true`, shows a speaker icon instead of a music note.
///   - isSelected: When `true`, renders text in white for contrast.
struct TrackRowView: View {

    let track: Track
    let isPlaying: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Playing indicator
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            // Title + Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Duration
            if let duration = track.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityIdentifier("track-row-\(track.id)")
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}