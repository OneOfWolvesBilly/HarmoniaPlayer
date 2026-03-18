//
//  PlaylistView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Left panel of the main window. Shows the current session playlist and
//  provides all track management interactions available via click and
//  right-click.
//
//  DESIGN NOTES
//  ------------
//  - Single-click sets `selectedTrackID` local state (highlight only).
//    Double-click calls `appState.play(trackID:)`.
//  - Right-click context menu provides Play and Remove from Playlist actions.
//    Remove calls `appState.removeTrack(_:)` and clears `selectedTrackID`
//    if the removed track was selected.
//  - File addition uses `NSOpenPanel` filtered to supported Free tier formats
//    (MP3, AAC/M4A, ALAC, WAV, AIFF). Drag-and-drop accepts `UTType.audio`
//    and `UTType.fileURL` items.
//  - An empty state placeholder is shown when `appState.playlist.tracks`
//    is empty, guiding the user to add music.
//  - No `import HarmoniaCore` — all state access goes through `AppState`.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Left-panel playlist view.
///
/// Displays all tracks in the current session playlist. Supports:
/// - Single-click to select a track (highlight only, no playback)
/// - Double-click to begin playback of a track
/// - Right-click context menu: Play, Remove from Playlist
/// - `+` button and drag-and-drop to add audio files
/// - Empty state guidance when the playlist is empty
struct PlaylistView: View {

    @EnvironmentObject private var appState: AppState

    /// The currently highlighted (selected) track ID.
    /// Selection is a UI-only concept; it does not affect `AppState.currentTrack`.
    @State private var selectedTrackID: Track.ID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Toolbar
            HStack {
                Text("Playlist")
                    .font(.headline)
                Spacer()
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("add-files-button")
                .help("Add files to playlist")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // MARK: Content
            if appState.playlist.tracks.isEmpty {
                emptyStateView
            } else {
                trackListView
            }
        }
        .onDrop(of: [UTType.audio, UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }

    }

    // MARK: - Subviews

    /// Shown when no tracks have been added yet.
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(Color.secondary)
            Text("Add music to get started")
                .font(.callout)
                .foregroundStyle(Color.secondary)
            Text("Click + or drag files here")
                .font(.caption)
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Track list with selection, double-click, and context menu.
    private var trackListView: some View {
        List(appState.playlist.tracks, selection: $selectedTrackID) { track in
            TrackRowView(
                track: track,
                isPlaying: appState.currentTrack?.id == track.id,
                isSelected: selectedTrackID == track.id
            )
            .onTapGesture(count: 2) {
                // Double-click: begin playback immediately
                Task { await appState.play(trackID: track.id) }
            }
            .onTapGesture(count: 1) {
                // Single-click: select only (no playback)
                selectedTrackID = track.id
            }
            .contextMenu {
                Button("Play") {
                    Task { await appState.play(trackID: track.id) }
                }
                Divider()
                Button("Remove from Playlist", role: .destructive) {
                    appState.removeTrack(track.id)
                    if selectedTrackID == track.id { selectedTrackID = nil }
                }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("playlist-list")
    }

    // MARK: - File Picker

    /// Opens `NSOpenPanel` filtered to Free tier audio formats.
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.aiff,
            UTType.wav,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "alac") ?? .audio
        ]
        if panel.runModal() == .OK {
            Task { await appState.load(urls: panel.urls) }
        }
    }

    // MARK: - Drag and Drop

    /// Handles dropped audio files or file URLs.
    ///
    /// Extracts `URL` values from each `NSItemProvider` and forwards them to
    /// `appState.load(urls:)` on the main actor.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                Task { await appState.load(urls: urls) }
            }
        }
        return true
    }
}
