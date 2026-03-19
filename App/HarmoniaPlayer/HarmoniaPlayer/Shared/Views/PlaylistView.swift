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
//  - Uses SwiftUI Table for native column resizing, sorting, and
//    horizontal scrolling on macOS.
//  - Sort state is stored in Playlist (Model layer), not in this View.
//    This allows each playlist to have independent sort state.
//  - No import HarmoniaCore — all state access goes through AppState.
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selectedTrackIDs = Set<Track.ID>()
    @State private var sortOrder: [KeyPathComparator<Track>] = []

    // MARK: - Computed

    private var totalDuration: TimeInterval {
        appState.playlist.tracks.map { $0.duration }.reduce(0, +)
    }

    private func formatTotalDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playlist")
                    .font(.headline)
                Spacer()
                if !sortOrder.isEmpty {
                    Button {
                        sortOrder = []
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .help("Restore added order")
                }
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

            if appState.playlist.tracks.isEmpty {
                emptyStateView
            } else {
                tableView
                Divider()
                footerView
            }
        }
        .onDrop(of: [UTType.audio, UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("Already in Playlist", isPresented: Binding(
            get: { !appState.skippedDuplicateURLs.isEmpty },
            set: { if !$0 { appState.skippedDuplicateURLs = [] } }
        )) {
            Button("OK") { appState.skippedDuplicateURLs = [] }
        } message: {
            let names = appState.skippedDuplicateURLs
                .map { $0.lastPathComponent }
                .joined(separator: "\n")
            Text("The following files are already in the playlist and were not added:\n\(names)")
        }
    }

    // MARK: - Table

    private var tableView: some View {
        Table(appState.playlist.tracks, selection: $selectedTrackIDs, sortOrder: $sortOrder) {
            TableColumn("") { track in
                Image(systemName: appState.currentTrack?.id == track.id
                      ? "speaker.wave.2.fill" : "music.note")
                    .foregroundStyle(appState.currentTrack?.id == track.id
                                     ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
            }
            .width(24)

            TableColumn("Title", value: \.title) { track in
                Text(track.title)
                    .lineLimit(1)
            }
            .width(min: 120)

            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "—" : track.artist)
                    .lineLimit(1)
                    .foregroundStyle(Color.secondary)
            }
            .width(min: 100)

            TableColumn("Duration", value: \.duration) { track in
                Text(formatDuration(track.duration))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            .width(min: 52, ideal: 64)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
        .onChange(of: sortOrder) {
            guard let first = sortOrder.first else {
                // User cleared sort — restore insertion order
                appState.restoreInsertionOrder()
                return
            }
            // Map KeyPathComparator back to PlaylistSortKey
            let key: PlaylistSortKey
            switch first.keyPath {
            case \Track.title:    key = .title
            case \Track.artist:   key = .artist
            case \Track.duration: key = .duration
            default:              key = .none
            }
            let ascending = first.order == .forward
            let sorted = appState.playlist.tracks.sorted(using: sortOrder)
            appState.applySort(sorted, key: key, ascending: ascending)
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            if let id = ids.first {
                Button("Play") {
                    Task { await appState.play(trackID: id) }
                }
                Button("Play Next") {
                    appState.playNext(id)
                }
                Divider()
                Button("Remove from Playlist", role: .destructive) {
                    appState.removeTrack(id)
                    selectedTrackIDs.remove(id)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                Task { await appState.play(trackID: id) }
            }
        }
        .accessibilityIdentifier("playlist-list")
    }

    // MARK: - Empty State

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

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            let count = appState.playlist.tracks.count
            Text("\(count) \(count == 1 ? "track" : "tracks")")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Spacer()
            if totalDuration > 0 {
                Text(formatTotalDuration(totalDuration))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - File Picker

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
