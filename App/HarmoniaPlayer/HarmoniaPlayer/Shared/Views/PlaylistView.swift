//
//  PlaylistView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Left panel of the main window. Shows a tab bar for all playlists,
//  the current playlist tracks, and all track management interactions
//  available via click and right-click.
//
//  DESIGN NOTES
//  ------------
//  - Uses SwiftUI Table for native column resizing, sorting, and
//    horizontal scrolling on macOS.
//  - Sort state is stored in Playlist (Model layer), not in this View.
//    This allows each playlist to have independent sort state.
//  - Column visibility and order are persisted automatically via
//    @AppStorage + TableColumnCustomization.
//  - Fixed columns (cannot be hidden): status icon, title, artist, duration.
//  - Optional columns (hidden by default except album): album, albumArtist,
//    year, trackNumber, discNumber, genre, composer, bpm, bitrate,
//    sampleRate, channels, fileSize, fileFormat, comment.
//  - TableColumn definitions are split across multiple @TableColumnBuilder
//    functions to stay within Swift type-checker complexity limits.
//  - No import HarmoniaCore — all state access goes through AppState.
//  - All UI strings use NSLocalizedString(bundle:appState.languageBundle)
//    for runtime language switching support.
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selectedTrackIDs = Set<Track.ID>()
    @State private var sortOrder: [KeyPathComparator<Track>] = []
    @State private var showShuffleQueue = false

    @State private var renamingIndex: Int? = nil
    @State private var renameText: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    @AppStorage("playlistColumnCustomization")
    private var columnCustomization: TableColumnCustomization<Track>

    // MARK: - Localization helper

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: appState.languageBundle, comment: "")
    }

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
            playlistTabBar
            Divider()
            toolbarRow
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
        .onReceive(NotificationCenter.default.publisher(for: .openFilePicker)) { _ in
            openFilePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameActivePlaylist)) { _ in
            beginRename(at: appState.activePlaylistIndex)
        }
    }

    // MARK: - Playlist Tab Bar

    private var playlistTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.playlists.enumerated()), id: \.element.id) { index, pl in
                    playlistTab(index: index, playlist: pl)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func playlistTab(index: Int, playlist: Playlist) -> some View {
        let isActive   = index == appState.activePlaylistIndex
        let isRenaming = renamingIndex == index
        let isPlaying  = playlist.id == appState.playingPlaylistID

        Button {
            if renamingIndex != nil { commitRename() }
            appState.activePlaylistIndex = index
        } label: {
            HStack(spacing: 4) {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .frame(minWidth: 60, maxWidth: 160)
                        .focused($isRenameFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else {
                    Text(playlist.name)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundStyle(isActive ? Color.accentColor : Color.clear),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playlist-tab-\(index)")
        .contextMenu {
            Button(L("ctx_rename")) { beginRename(at: index) }
            Divider()
            Button(L("ctx_delete"), role: .destructive) {
                appState.deletePlaylist(at: index)
            }
        }
    }

    // MARK: - Toolbar Row

    private var toolbarRow: some View {
        HStack {
            Spacer()
            if !sortOrder.isEmpty {
                Button {
                    sortOrder = []
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .help(L("help_restore_order"))
            }
            if appState.isShuffled {
                Button {
                    showShuffleQueue.toggle()
                } label: {
                    Image(systemName: "list.number")
                }
                .accessibilityIdentifier("shuffle-queue-button")
                .help(L("help_show_shuffle_queue"))
                .popover(isPresented: $showShuffleQueue, arrowEdge: .bottom) {
                    shuffleQueuePopover
                }
            }
            Button {
                openFilePicker()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("add-files-button")
            .help(L("help_add_files"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Table
    //
    // Split into multiple @TableColumnBuilder functions to avoid
    // "unable to type-check expression in reasonable time" compiler error.
    // Swift's result builder type inference degrades exponentially with
    // column count; grouping into sub-functions restores linear inference.

    private var tableView: some View {
        Table(appState.playlist.tracks,
              selection: $selectedTrackIDs,
              sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            coreColumns
            tagColumns
            technicalColumns
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
        .onChange(of: sortOrder) {
            handleSortOrderChange()
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            if let id = ids.first {
                Button(L("ctx_play")) {
                    Task { await appState.play(trackID: id) }
                }
                Button(L("ctx_play_next")) {
                    appState.playNext(id)
                }
                Divider()
                Button(L("ctx_get_info")) {
                    appState.showFileInfo(trackID: id)
                }
                Divider()
                Button(L("ctx_remove"), role: .destructive) {
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

    // ── Group 1: Fixed columns (status icon, title, artist, duration) ─────
    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    private var coreColumns: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("") { track in
            Image(systemName: appState.currentTrack?.id == track.id
                  ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(appState.currentTrack?.id == track.id
                                 ? Color.accentColor : Color.secondary)
                .frame(width: 16)
                .opacity(track.isAccessible ? 1.0 : 0.6)
        }
        .width(24)

        TableColumn(L("col_title"), value: \.title) { track in
            Text(track.title)
                .lineLimit(1)
                .foregroundStyle(track.isAccessible
                                 ? Color.primary
                                 : Color(nsColor: .tertiaryLabelColor))
                .strikethrough(!track.isAccessible)
        }
        .width(min: 120)

        TableColumn(L("col_artist"), value: \.artist) { track in
            Text(track.artist.isEmpty ? "—" : track.artist)
                .lineLimit(1)
                .foregroundStyle(track.isAccessible
                                 ? Color.secondary
                                 : Color(nsColor: .tertiaryLabelColor))
                .strikethrough(!track.isAccessible)
        }
        .width(min: 100)

        TableColumn(L("col_duration"), value: \.duration) { track in
            Text(formatDuration(track.duration))
                .monospacedDigit()
                .foregroundStyle(track.isAccessible
                                 ? Color.secondary
                                 : Color(nsColor: .tertiaryLabelColor))
                .strikethrough(!track.isAccessible)
        }
        .width(min: 52, ideal: 64)
    }

    // ── Group 2: Tag columns (album, albumArtist, year, trackNumber, ──────
    //                          discNumber, genre, composer, bpm, comment)
    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    private var tagColumns: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn(L("col_album"), value: \.album) { track in
            Text(track.album.isEmpty ? "—" : track.album)
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 100)
        .customizationID("col.album")

        TableColumn(L("col_albumArtist"), value: \.albumArtist) { track in
            Text(track.albumArtist.isEmpty ? "—" : track.albumArtist)
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 100)
        .customizationID("col.albumArtist")
        .defaultVisibility(.hidden)

        TableColumn(L("col_year"), value: \.sortYear) { track in
            Text(track.year.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 52, ideal: 60)
        .customizationID("col.year")
        .defaultVisibility(.hidden)

        TableColumn(L("col_trackNumber"), value: \.sortTrackNumber) { track in
            Text(track.trackNumber.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 40, ideal: 48)
        .customizationID("col.trackNumber")
        .defaultVisibility(.hidden)

        TableColumn(L("col_discNumber"), value: \.sortDiscNumber) { track in
            Text(track.discNumber.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 40, ideal: 48)
        .customizationID("col.discNumber")
        .defaultVisibility(.hidden)

        TableColumn(L("col_genre"), value: \.genre) { track in
            Text(track.genre.isEmpty ? "—" : track.genre)
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 80)
        .customizationID("col.genre")
        .defaultVisibility(.hidden)

        TableColumn(L("col_composer"), value: \.composer) { track in
            Text(track.composer.isEmpty ? "—" : track.composer)
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 100)
        .customizationID("col.composer")
        .defaultVisibility(.hidden)

        TableColumn(L("col_bpm"), value: \.sortBpm) { track in
            Text(track.bpm.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 48, ideal: 56)
        .customizationID("col.bpm")
        .defaultVisibility(.hidden)

        TableColumn(L("col_comment"), value: \.comment) { track in
            Text(track.comment.isEmpty ? "—" : track.comment)
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 100)
        .customizationID("col.comment")
        .defaultVisibility(.hidden)
    }

    // ── Group 3: Technical columns (bitrate, sampleRate, channels, ────────
    //                                fileSize, fileFormat)
    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    private var technicalColumns: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn(L("col_bitrate"), value: \.sortBitrate) { track in
            Text(track.bitrate.map { "\($0)" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 56, ideal: 64)
        .customizationID("col.bitrate")
        .defaultVisibility(.hidden)

        TableColumn(L("col_sampleRate"), value: \.sortSampleRate) { track in
            Text(track.sampleRate.map { String(format: "%.0f", $0) } ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 64, ideal: 72)
        .customizationID("col.sampleRate")
        .defaultVisibility(.hidden)

        TableColumn(L("col_channels"), value: \.sortChannels) { track in
            Text(track.channels.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 40, ideal: 52)
        .customizationID("col.channels")
        .defaultVisibility(.hidden)

        TableColumn(L("col_fileSize"), value: \.sortFileSize) { track in
            Text(track.fileSize.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "—")
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .width(min: 72, ideal: 84)
        .customizationID("col.fileSize")
        .defaultVisibility(.hidden)

        TableColumn(L("col_fileFormat"), value: \.fileFormat) { track in
            Text(track.fileFormat.isEmpty ? "—" : track.fileFormat)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 52, ideal: 64)
        .customizationID("col.fileFormat")
        .defaultVisibility(.hidden)
    }

    // MARK: - Sort Order Handler

    private func handleSortOrderChange() {
        guard let first = sortOrder.first else {
            appState.restoreInsertionOrder()
            return
        }
        let key: PlaylistSortKey
        switch first.keyPath {
        case \Track.title:           key = .title
        case \Track.artist:          key = .artist
        case \Track.album:           key = .album
        case \Track.duration:        key = .duration
        case \Track.albumArtist:     key = .albumArtist
        case \Track.composer:        key = .composer
        case \Track.genre:           key = .genre
        case \Track.sortYear:        key = .year
        case \Track.sortTrackNumber: key = .trackNumber
        case \Track.sortDiscNumber:  key = .discNumber
        case \Track.sortBpm:         key = .bpm
        case \Track.sortBitrate:     key = .bitrate
        case \Track.sortSampleRate:  key = .sampleRate
        case \Track.sortChannels:    key = .channels
        case \Track.sortFileSize:    key = .fileSize
        case \Track.fileFormat:      key = .fileFormat
        default:                     key = .none
        }
        let ascending = first.order == .forward
        let sorted = appState.playlist.tracks.sorted(using: sortOrder)
        appState.applySort(sorted, key: key, ascending: ascending)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(Color.secondary)
            Text(L("empty_state_primary"))
                .font(.callout)
                .foregroundStyle(Color.secondary)
            Text(L("empty_state_secondary"))
                .font(.caption)
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            let count = appState.playlist.tracks.count
            let word = count == 1 ? L("footer_track_singular") : L("footer_track_plural")
            Text("\(count) \(word)")
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

    // MARK: - Shuffle Queue Popover

    private var shuffleQueuePopover: some View {
        let queue = appState.shuffleQueue
        let currentIndex = appState.shuffleQueueIndex
        let tracks = queue.compactMap { id in
            appState.playlist.tracks.first { $0.id == id }
        }

        return VStack(alignment: .leading, spacing: 0) {
            Text(L("shuffle_queue_title"))
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        HStack(spacing: 8) {
                            if index == currentIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 16)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 16)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.body)
                                    .fontWeight(index == currentIndex ? .semibold : .regular)
                                    .lineLimit(1)
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
                        .background(index == currentIndex
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear)
                    }
                }
            }
            .frame(width: 280, height: min(CGFloat(tracks.count) * 44 + 16, 320))
        }
    }

    // MARK: - Inline Rename

    private func beginRename(at index: Int) {
        guard appState.playlists.indices.contains(index) else { return }
        renameText = appState.playlists[index].name
        renamingIndex = index
        DispatchQueue.main.async { isRenameFieldFocused = true }
    }

    private func commitRename() {
        guard let index = renamingIndex else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? appState.playlists[index].name : trimmed
        appState.renamePlaylist(at: index, name: finalName)
        isRenameFieldFocused = false
        renamingIndex = nil
    }

    private func cancelRename() {
        isRenameFieldFocused = false
        renamingIndex = nil
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
