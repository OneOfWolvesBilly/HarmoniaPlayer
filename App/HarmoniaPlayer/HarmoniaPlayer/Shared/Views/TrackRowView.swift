//
//  TrackRowView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Single row in the playlist List. Columns align with PlaylistView headers:
//  [icon 24pt] [Title flex] [Artist flex] [Duration 64pt]
//

import SwiftUI

struct TrackRowView: View {

    let track: Track
    let isPlaying: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Playing indicator icon
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                .frame(width: 24, alignment: .center)

            // Title column
            Text(track.title)
                .font(.body)
                .foregroundStyle(rowTitleColor)
                .strikethrough(!track.isAccessible, color: rowTitleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)

            // Artist column
            Text(track.artist.isEmpty ? "—" : track.artist)
                .font(.body)
                .foregroundStyle(rowSecondaryColor)
                .strikethrough(!track.isAccessible, color: rowSecondaryColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)

            // Duration column
            Text(formatDuration(track.duration))
                .font(.body)
                .foregroundStyle(rowSecondaryColor)
                .strikethrough(!track.isAccessible, color: rowSecondaryColor)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(track.isAccessible ? 1.0 : 0.6)
        .accessibilityIdentifier("track-row-\(track.id)")
    }

    // MARK: - Helpers

    /// Title text color.
    /// Inaccessible tracks use .tertiary which adapts to both light and dark mode —
    /// more visible than .secondary on dark backgrounds.
    private var rowTitleColor: Color {
        guard track.isAccessible else { return Color(nsColor: .tertiaryLabelColor) }
        return isSelected ? .white : .primary
    }

    /// Secondary text color (artist, duration).
    private var rowSecondaryColor: Color {
        guard track.isAccessible else { return Color(nsColor: .tertiaryLabelColor) }
        return isSelected ? Color.white.opacity(0.8) : .secondary
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
