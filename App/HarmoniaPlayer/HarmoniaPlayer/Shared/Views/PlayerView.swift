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
//  - Album art is loaded from `currentTrack.artworkData` if available;
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
//  - All UI strings use `String(localized:bundle:appState.languageBundle)`
//    for runtime language switching support.
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

    /// Opacity of the volume label bubble. 1.0 while dragging, fades to 0 after release.
    @State private var volumeLabelOpacity: Double = 0

    /// Task that delays hiding the volume label after drag ends.
    @State private var volumeLabelHideTask: Task<Void, Never>? = nil

    // MARK: - Localization helper

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: appState.languageBundle, comment: "")
    }

    var body: some View {
        VStack(spacing: 16) {
            albumArtView
            metadataView
            seekSliderView
            transportControlsView
            modeControlsView
            volumeSliderView
            statusLabelView
        }
        .padding(20)
    }

    // MARK: - Album Art

    /// Album art loaded from `artworkData`, or a grey placeholder.
    private var albumArtView: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
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
                            .font(.system(size: size * 0.25))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.05)))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier("album-art")
    }

    // MARK: - Metadata

    /// Track title and artist labels.
    private var metadataView: some View {
        VStack(spacing: 4) {
            Text(appState.currentTrack?.title ?? L("no_track_loaded"))
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
                    Task { await appState.seek(to: seekValue) }
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
            .help(L("help_previous_track"))

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
            .help(appState.playbackState == .playing ? L("help_pause") : L("help_play"))

            Button {
                Task { await appState.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("stop-button")
            .help(L("help_stop"))

            Button {
                Task { await appState.playNextTrack() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("next-button")
            .help(L("help_next_track"))
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
            .help(appState.isShuffled ? L("shuffle_on") : L("shuffle_off"))
        }
        .buttonStyle(.plain)
        .disabled(appState.playlist.tracks.isEmpty)
    }

    // MARK: - Volume Slider

    /// Volume control slider (0.0 – 1.0) with a floating percentage label
    /// that appears above the thumb while dragging and fades out after release.
    ///
    /// Label position tracks the thumb: centered on `volume × usable slider width`.
    /// Value is snapped to 1 decimal place (e.g. 0.732 → 0.730 = "73.0%").
    private var volumeSliderView: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(Color.secondary)

            // GeometryReader measures the slider's available width so the
            // label can be positioned directly above the current thumb position.
            GeometryReader { geo in
                let thumbEdge: CGFloat = 11   // macOS slider thumb edge inset (~half thumb width)
                let usable = geo.size.width - thumbEdge * 2
                let thumbX = thumbEdge + CGFloat(appState.volume) * usable

                ZStack(alignment: .top) {
                    // Volume label bubble — floats above thumb, center-aligned to thumb x
                    Text(volumePercentLabel)
                        .font(.caption2)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .frame(minHeight: 22)
                        .opacity(volumeLabelOpacity)
                        .position(x: thumbX, y: 0)
                        .animation(.easeOut(duration: 0.15), value: appState.volume)

                    // Slider sits below the label
                    Slider(
                        value: Binding(
                            get: { Double(appState.volume) },
                            set: { newValue in
                                // Snap to 0.1% steps (0.001 in 0.0–1.0 range)
                                let snapped = Float((newValue * 1000).rounded() / 1000)
                                Task { await appState.setVolume(snapped) }
                            }
                        ),
                        in: 0.0...1.0
                    ) { editing in
                        if editing {
                            // Cancel any pending hide and show immediately
                            volumeLabelHideTask?.cancel()
                            withAnimation(.easeIn(duration: 0.1)) {
                                volumeLabelOpacity = 1
                            }
                        } else {
                            // Delay fade-out by 1.5 s after drag ends
                            volumeLabelHideTask = Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        volumeLabelOpacity = 0
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("volume-slider")
                    .padding(.top, 20) // make room for the label above
                }
            }
            .frame(height: 44) // label height (22) + slider height (~22)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
    }

    /// Volume as a 1-decimal-place percentage string (e.g. "73.0%").
    private var volumePercentLabel: String {
        String(format: "%.1f%%", appState.volume * 100)
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
        case .off: return L("repeat_off")
        case .all: return L("repeat_all")
        case .one: return L("repeat_one")
        }
    }

    /// Human-readable description of `appState.playbackState`.
    private var statusText: String {
        // No text when playlist is empty
        guard !appState.playlist.tracks.isEmpty else { return "" }
        switch appState.playbackState {
        case .idle:         return ""
        case .stopped:      return L("status_stopped")
        case .loading:      return L("status_loading")
        case .playing:      return L("status_playing")
        case .paused:       return L("status_paused")
        case .error:        return L("status_stopped")
        }
    }

    /// Formats a `TimeInterval` as `m:ss` (e.g. `3:45`).
    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
