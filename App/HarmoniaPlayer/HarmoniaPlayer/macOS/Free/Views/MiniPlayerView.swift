//
//  MiniPlayerView.swift
//  HarmoniaPlayer / macOS / Free / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Compact floating player window (400×160pt fixed).
//  Opened via Window → Mini Player (⌘M).
//
//  LAYOUT
//  ------
//  ┌─────────────────────────────────────────────┐
//  │           [Playlist 1 ▾]                    │  ← playlist picker
//  ├─────────────────────────────────────────────┤
//  │ ┌──────┐  Title (MarqueeText)               │
//  │ │  🎵  │  Artist (MarqueeText)              │
//  │ │ art  │  ─────────────────────────────     │  ← seek slider
//  │ └──────┘  0:42                        3:30  │
//  │                                             │
//  │          ◀◀   ⏸   ▶▶   🔁   🔀              │
//  │  🔈  ────────●────────────────────  🔊      │  ← volume slider
//  └─────────────────────────────────────────────┘
//
//  DESIGN NOTES
//  ------------
//  - Shares AppState via @EnvironmentObject; full/mini player always in sync.
//  - FloatingWindowController sets window.level based on hp.miniPlayerAlwaysOnTop.
//  - WindowCloseObserver brings Full Player to front when Mini Player closes.
//  - Playlist switch: stop → change activePlaylistIndex → play first track.
//  - Right-click context menu opens MarqueeSettingsPopover (speed/pause sliders).
//  - No import HarmoniaCore.
//

import SwiftUI
import AppKit

// MARK: - FloatingWindowController

/// Reads hp.miniPlayerAlwaysOnTop from @AppStorage and sets window.level
/// to .floating (true) or .normal (false). Reacts immediately to changes.
private struct FloatingWindowController: NSViewRepresentable {

    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyLevel(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyLevel(to: nsView.window)
        }
    }

    private func applyLevel(to window: NSWindow?) {
        guard let window else { return }
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

// MARK: - WindowCloseObserver

/// Listens for the Mini Player window closing and brings Full Player to front.
private struct WindowCloseObserver: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @objc func windowWillClose(_ notification: Notification) {
            DispatchQueue.main.async {
                // Bring Full Player (main WindowGroup) to front.
                NSApp.windows
                    .filter { $0.identifier?.rawValue == "main" || $0.title == "HarmoniaPlayer" }
                    .first?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - MarqueeSettingsPopover

private struct MarqueeSettingsPopover: View {

    @AppStorage("hp.marqueeSpeed") private var speed: Double = 40.0
    @AppStorage("hp.marqueePause") private var pause: Double = 1.0

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("marquee_settings_title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("settings_marquee_speed"))
                    Spacer()
                    Text("\(Int(speed)) pt/s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $speed, in: 10...120, step: 5)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("settings_marquee_pause"))
                    Spacer()
                    Text(String(format: "%.1f s", pause))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $pause, in: 0...5, step: 0.5)
            }

            HStack {
                Spacer()
                Button(L("settings_marquee_reset")) {
                    speed = 40.0
                    pause = 1.0
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - WindowDragArea

/// Makes the entire Mini Player window draggable by overriding mouseDownCanMoveWindow.
/// Required because .windowStyle(.plain) removes the title bar drag area.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - MiniPlayerView

struct MiniPlayerView: View {

    @EnvironmentObject private var appState: AppState

    @AppStorage("hp.miniPlayerAlwaysOnTop") private var alwaysOnTop: Bool = true

    @State private var isSeeking = false
    @State private var seekValue: Double = 0
    @State private var showMarqueeSettings = false
    @State private var showTrackList = false

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: appState.languageBundle, comment: "")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Closes Mini Player and brings Full Player back to front.
    private func closeMiniPlayer() {
        NSApp.windows
            .first { $0.identifier?.rawValue == "mini-player" }?
            .close()
        NSApp.windows
            .filter { $0.title == "HarmoniaPlayer" }
            .first?
            .makeKeyAndOrderFront(nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            playlistPickerRow
            Divider()
            mainRow
            transportRow
            volumeRow
        }
        .frame(width: 400, height: 160)
        .background(.ultraThinMaterial)
        .background(WindowDragArea())
        .background(FloatingWindowController(alwaysOnTop: alwaysOnTop))
        .background(WindowCloseObserver())
        .contextMenu {
            Button(L("menu_marquee_settings")) {
                showMarqueeSettings = true
            }
        }
        .popover(isPresented: $showMarqueeSettings, arrowEdge: .bottom) {
            MarqueeSettingsPopover()
        }
        // When AppState triggers a Pro-format gate, close MiniPlayer so the
        // Paywall sheet can appear on the main window.
        .onReceive(NotificationCenter.default.publisher(for: .bringMainWindowToFront)) { _ in
            closeMiniPlayer()
        }
    }

    // MARK: - Playlist Picker Row

    private var playlistPickerRow: some View {
        HStack(spacing: 0) {
            // Expand button — closes Mini Player and returns to Full Player
            Button {
                closeMiniPlayer()
            } label: {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .help(L("mini_player_expand"))

            Spacer()

            Menu {
                ForEach(Array(appState.playlists.enumerated()), id: \.offset) { index, pl in
                    Button {
                        Task { await appState.switchMiniPlayerPlaylist(to: index) }
                    } label: {
                        HStack {
                            if index == appState.activePlaylistIndex {
                                Image(systemName: "checkmark")
                            }
                            Text(pl.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(appState.playlist.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
            // Balance spacer so playlist menu stays centred
            Color.clear
                .frame(width: 30, height: 1)
        }
        .frame(height: 28)
        .padding(.trailing, 10)
    }

    // MARK: - Main Row (art + metadata + seek)

    private var mainRow: some View {
        HStack(spacing: 10) {
            albumArtView

            VStack(alignment: .leading, spacing: 2) {
                if let track = appState.currentTrack {
                    MarqueeText(
                        text: track.title.isEmpty
                            ? URL(fileURLWithPath: track.originalPath).lastPathComponent
                            : track.title,
                        font: .system(size: 12, weight: .semibold)
                    )
                    .frame(height: 16)

                    MarqueeText(
                        text: track.artist.isEmpty ? "—" : track.artist,
                        font: .system(size: 11)
                    )
                    .foregroundStyle(.secondary)
                    .frame(height: 14)
                } else {
                    Text(L("mini_player_no_track"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                    Spacer().frame(height: 14)
                }

                seekSlider

                HStack {
                    Text(formatTime(isSeeking ? seekValue : appState.currentTime))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(appState.duration))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Album Art

    private var albumArtView: some View {
        Group {
            if let data = appState.currentTrack?.artworkData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Seek Slider

    private var seekSlider: some View {
        Slider(
            value: Binding(
                get: { isSeeking ? seekValue : appState.currentTime },
                set: { seekValue = $0 }
            ),
            in: 0...max(appState.duration, 1)
        ) { editing in
            if editing {
                isSeeking = true
                seekValue = appState.currentTime
            } else {
                isSeeking = false
                Task { await appState.seek(to: seekValue) }
            }
        }
        .controlSize(.mini)
    }

    // MARK: - Transport Row

    private var transportRow: some View {
        HStack(spacing: 16) {
            Spacer()

            Button { Task { await appState.playPreviousTrack() } } label: {
                Image(systemName: "backward.fill").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(appState.playlist.tracks.isEmpty)

            Button {
                Task {
                    if appState.playbackState == .playing {
                        await appState.pause()
                    } else {
                        await appState.play()
                    }
                }
            } label: {
                Image(systemName: appState.playbackState == .playing
                      ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(appState.playlist.tracks.isEmpty)

            Button { Task { await appState.playNextTrack() } } label: {
                Image(systemName: "forward.fill").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(appState.playlist.tracks.isEmpty)

            // Repeat
            Button { appState.cycleRepeatMode() } label: {
                Image(systemName: appState.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.repeatMode != .off
                                     ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)

            // Shuffle
            Button { appState.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.isShuffled
                                     ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)

            // Track list — opens a popover showing all tracks in the current playlist.
            // Format-gated tracks (Pro-only formats on Free tier) show a lock icon.
            Button {
                showTrackList.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
                    .foregroundStyle(showTrackList ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(appState.playlist.tracks.isEmpty)
            .popover(isPresented: $showTrackList, arrowEdge: .top) {
                trackListPopover
            }

            Spacer()
        }
        .frame(height: 28)
    }

    // MARK: - Track List Popover

    /// Popover listing all tracks in the current playlist.
    /// Format-gated tracks show a lock icon and cannot be played on the Free tier.
    private var trackListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appState.playlist.name)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appState.playlist.tracks) { track in
                        let isFormatGated = AppState.proOnlyFormats
                            .contains(track.url.pathExtension.lowercased())
                            && !appState.isProUnlocked
                        let isCurrent = appState.currentTrack?.id == track.id

                        Button {
                            showTrackList = false
                            Task { await appState.play(trackID: track.id) }
                        } label: {
                            HStack(spacing: 8) {
                                // Playing indicator or lock icon
                                Group {
                                    if isCurrent {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundStyle(Color.accentColor)
                                    } else if isFormatGated {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(Color.secondary)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 16)
                                .font(.system(size: 11))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.body)
                                        .fontWeight(isCurrent ? .semibold : .regular)
                                        .lineLimit(1)
                                        .foregroundStyle(isFormatGated
                                            ? Color(nsColor: .tertiaryLabelColor)
                                            : Color.primary)
                                        .strikethrough(isFormatGated)
                                    if !track.artist.isEmpty {
                                        Text(track.artist)
                                            .font(.caption)
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isCurrent
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 280, height: min(
                CGFloat(appState.playlist.tracks.count) * 44 + 16,
                320
            ))
        }
    }

    // MARK: - Volume Row

    private var volumeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(appState.volume) },
                    set: { newValue in
                        let snapped = Float((newValue * 1000).rounded() / 1000)
                        Task { await appState.setVolume(snapped) }
                    }
                ),
                in: 0.0...1.0
            )
            .controlSize(.mini)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(height: 24)
    }
}
