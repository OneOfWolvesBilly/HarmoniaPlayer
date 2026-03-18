//
//  PlayerView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Right panel of the main window. Displays now-playing information and
//  all transport controls available via click.
//
//  DESIGN NOTES
//  ------------
//  - Album art is loaded from `currentTrack.artworkURL` if available;
//    otherwise a grey rounded-rectangle placeholder with a music note icon
//    is shown.
//  - The seek slider uses a local `isSeeking` flag to freeze the displayed
//    position while the user is dragging. On drag end (`editing == false`),
//    `appState.seek(to:)` is called with the final slider value. This
//    prevents the slider from jumping back to `currentTime` mid-drag.
//  - Repeat icon changes to `repeat.1` when `repeatMode == .one` to match
//    macOS Music.app convention.
//  - Shuffle button tint changes to `accentColor` when shuffle is active,
//    matching the repeat button convention.
//  - All transport actions are dispatched via `Task { await appState.method() }`
//    to satisfy Swift 6 concurrency requirements.
//  - No `import HarmoniaCore` — all state access goes through `AppState`.
//

import SwiftUI
import AppKit

/// Right-panel now-playing and transport controls view.
///
/// Displays:
/// - Album art (from metadata) or a placeholder
/// - Track title and artist
/// - Seek slider with current position and total duration
/// - Transport controls: Previous, Play/Pause, Stop, Next
/// - Repeat and Shuffle mode buttons
/// - Playback status label
struct PlayerView: View {

    @EnvironmentObject private var appState: AppState

    /// `true` while the user is dragging the seek slider.
    /// Freezes slider position to prevent mid-drag jumps from polling updates.
    @State private var isSeeking = false

    /// The slider value captured at drag-start; updated as the user scrubs.
    @State private var seekValue: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            albumArtView
            metadataView
            seekSliderView
            transportControlsView
            modeControlsView
            statusLabelView
        }
        .padding(20)
    }

    // MARK: - Album Art

    /// Album art loaded from `artworkURL`, or a grey placeholder.
    private var albumArtView: some View {
        Group {
            if let data = appState.currentTrack?.artworkData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("album-art")
    }

    // MARK: - Metadata

    /// Track title and artist labels.
    private var metadataView: some View {
        VStack(spacing: 4) {
            Text(appState.currentTrack?.title ?? "No Track Loaded")
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .accessibilityIdentifier("now-playing-title")

            Text(appState.currentTrack?.artist ?? "")
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("now-playing-artist")
        }
    }

    // MARK: - Seek Slider

    /// Progress slider showing current position over total duration.
    ///
    /// Dragging freezes the displayed position via `isSeeking`. On release,
    /// seeks to the final drag position.
    private var seekSliderView: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekValue : appState.currentTime },
                    set: { newValue in seekValue = newValue }
                ),
                in: 0...max(appState.duration, 1)
            ) { editing in
                if editing {
                    // Drag started — freeze display at current position
                    isSeeking = true
                    seekValue = appState.currentTime
                } else {
                    // Drag ended — send final position to AppState
                    isSeeking = false
                    Task { try? await appState.seek(to: seekValue) }
                }
            }
            .accessibilityIdentifier("progress-slider")
            .disabled(appState.duration <= 0)

            HStack {
                Text(formatTime(appState.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text(formatTime(appState.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    // MARK: - Transport Controls

    /// Previous, Play/Pause, Stop, Next buttons.
    private var transportControlsView: some View {
        HStack(spacing: 24) {
            Button {
                Task { await appState.playPreviousTrack() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("previous-button")
            .help("Previous track")

            Button {
                Task {
                    if appState.playbackState == .playing {
                        await appState.pause()
                    } else {
                        await appState.play()
                    }
                }
            } label: {
                Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.title)
            }
            .accessibilityIdentifier("play-pause-button")
            .help(appState.playbackState == .playing ? "Pause" : "Play")

            Button {
                Task { await appState.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("stop-button")
            .help("Stop")

            Button {
                Task { await appState.playNextTrack() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("next-button")
            .help("Next track")
        }
        .buttonStyle(.plain)
        .disabled(appState.playlist.tracks.isEmpty)
    }

    // MARK: - Mode Controls

    /// Repeat and Shuffle toggle buttons.
    private var modeControlsView: some View {
        HStack(spacing: 20) {
            // Repeat cycles: off → all → one → off
            Button {
                appState.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIcon)
                    .foregroundStyle(appState.repeatMode == .off
                        ? Color.secondary
                        : Color.accentColor)
            }
            .accessibilityIdentifier("repeat-button")
            .help(repeatHelpText)

            // Shuffle toggles on/off
            Button {
                appState.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(appState.isShuffled
                        ? Color.accentColor
                        : Color.secondary)
            }
            .accessibilityIdentifier("shuffle-button")
            .help(appState.isShuffled ? "Shuffle: On" : "Shuffle: Off")
        }
        .buttonStyle(.plain)
        .disabled(appState.playlist.tracks.isEmpty)
    }

    // MARK: - Status Label

    /// Current playback state as human-readable text.
    private var statusLabelView: some View {
        Text(statusText)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .accessibilityIdentifier("playback-status-label")
    }

    // MARK: - Helpers

    /// SF Symbol name for the current repeat mode.
    private var repeatIcon: String {
        switch appState.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    /// Tooltip text for the repeat button.
    private var repeatHelpText: String {
        switch appState.repeatMode {
        case .off: return "Repeat: Off"
        case .all: return "Repeat: All"
        case .one: return "Repeat: One"
        }
    }

    /// Human-readable description of `appState.playbackState`.
    private var statusText: String {
        switch appState.playbackState {
        case .playing:      return "Playing"
        case .paused:       return "Paused"
        case .stopped:      return "Stopped"
        case .loading:      return "Loading"
        case .idle:         return "Idle"
        case .error(let e): return "Error: \(e)"
        }
    }

    /// Formats a `TimeInterval` as `m:ss` (e.g. `3:45`).
    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
