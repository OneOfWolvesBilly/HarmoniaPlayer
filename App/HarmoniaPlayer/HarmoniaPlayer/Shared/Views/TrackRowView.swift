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
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)

            // Artist column
            Text(track.artist.isEmpty ? "—" : track.artist)
                .font(.body)
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)

            // Duration column
            Text(formatDuration(track.duration))
                .font(.body)
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityIdentifier("track-row-\(track.id)")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
