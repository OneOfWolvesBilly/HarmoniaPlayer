//
//  PlaylistCollection.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

// MARK: - Persistence Keys

private enum PersistenceKey {
    /// Legacy location of the playlists; read once for migration.
    static let playlists           = "hp.playlists"
    static let activePlaylistIndex = "hp.activePlaylistIndex"
}

/// Store owning the playlist surface: the playlists, the active playlist
/// index, the table selection, the blocking-operation flag, the undo
/// manager, the playlist services, and the playlist persistence.
///
/// Views whose body reads playlist state observe this store directly via
/// `@Environment(PlaylistCollection.self)`. The store holds no playback
/// reference: mutations that affect playback are reported through the
/// root-wired closures, and the playback controller reacts to them.
///
/// **Persistence.** Playlists are written to the `PlaylistStore` and the
/// active index to `UserDefaults` by `saveState()`, which every playlist
/// mutation calls; `init` restores both and marks tracks whose file is
/// gone as inaccessible, then starts the background metadata refresh.
@MainActor @Observable
final class PlaylistCollection: PlaylistContext {

    // MARK: - Observed state

    /// All playlists managed by the app. Never empty.
    ///
    /// Use `newPlaylist(name:)`, `renamePlaylist(at:name:)`,
    /// `deletePlaylist(at:)` to manage.
    var playlists: [Playlist]

    /// Index of the currently visible and active playlist.
    ///
    /// Setting this directly switches the playlist context without
    /// interrupting playback. Transport controls (Next / Previous) always
    /// operate on `playlists[activePlaylistIndex]`.
    var activePlaylistIndex: Int = 0

    /// The currently active playlist — `playlists[activePlaylistIndex]`.
    ///
    /// Read-only from outside; all internal mutations go through
    /// `playlists[activePlaylistIndex].xxx` directly.
    var playlist: Playlist { playlists[activePlaylistIndex] }

    /// IDs of the tracks currently selected in the playlist table.
    ///
    /// Promoted from the view so that the playback controller can start
    /// from the selection when no track is loaded. Selection does not follow
    /// playback — it reflects user clicks only.
    var selectedTrackIDs = Set<Track.ID>()

    /// Whether a batch playlist operation (load or import) is in progress.
    ///
    /// Set to `true` at the start of `load(urls:)` and `importPlaylist(from:)`,
    /// reset to `false` via `defer` when the method returns. Read by the
    /// Commands to disable playlist-mutating menu items and by the playlist
    /// view to reject drops during batch operations. Not persisted — always
    /// starts as `false` on launch.
    var isPerformingBlockingOperation: Bool = false

    // MARK: - Format classification

    /// File extensions supported on the Free tier (and Pro tier).
    static let freeFormats: Set<String>    = ["mp3", "aac", "m4a", "wav", "aiff", "alac"]

    /// File extensions that require the Pro tier (FLAC / DSD).
    static let proOnlyFormats: Set<String> = ["flac", "dsf", "dff"]

    /// File extensions currently allowed for loading into playlists.
    /// Returns `freeFormats`: the Pro-only formats are treated as
    /// unsupported and never enter a playlist.
    static var allowedFormats: Set<String> { freeFormats }

    /// Number of tracks added between incremental saves in batch operations.
    /// Provides crash safety for large imports without saving on every track.
    static let saveBatchSize = 5

    // MARK: - Dependencies

    /// UndoManager for playlist operations (load, removeTrack, moveTrack).
    ///
    /// Injected at init for testability; `levelsOfUndo = 10` retains the ten
    /// most recent track operations only. The Commands reach it through
    /// `undo()` / `redo()` / `canUndo` / `canRedo`.
    let undoManager: UndoManager

    /// Tag reader service. Also read by the composition-root wiring tests.
    let tagReaderService: TagReaderService

    /// File drop service — validates URLs received from drag-and-drop.
    private let fileDropService: FileDropService

    /// Durable store for the playlist collection, kept outside UserDefaults
    /// because playlists exceed the UserDefaults single-value size limit.
    private let playlistStore: PlaylistStore

    /// Alert store the load and import paths write their skip lists and
    /// errors to; module-internal so the M3U8 extension in its own file can
    /// reach it.
    let alertCenter: AlertCenter

    /// Settings store; `allowDuplicateTracks` gates the duplicate check.
    private let settingsStore: SettingsStore

    /// UserDefaults store used for the active-index key and the legacy
    /// playlists migration.
    private let userDefaults: UserDefaults

    // MARK: - Root-wired notifications

    /// Called by `load(urls:)` with the ids of the tracks it added, in
    /// playlist order, when at least one track was added.
    @ObservationIgnored var onTracksAppended: (([Track.ID]) -> Void)?

    /// Called by `removeTrack(_:)` when a track was removed.
    @ObservationIgnored var onTrackRemoved: ((Track.ID) -> Void)?

    /// Called by `removeTracks(_:)` with the ids actually removed.
    @ObservationIgnored var onTracksRemoved: ((Set<Track.ID>) -> Void)?

    /// Called by `clearPlaylist()` after the tracks are cleared.
    @ObservationIgnored var onPlaylistCleared: (() -> Void)?

    /// Called by `deletePlaylist(at:)` with the deleted playlist's id.
    @ObservationIgnored var onPlaylistDeleted: ((Playlist.ID) -> Void)?

    /// Called by `playNext(_:afterCurrent:)` with the re-queued track's id.
    @ObservationIgnored var onTrackQueuedNext: ((Track.ID) -> Void)?

    // MARK: - Init

    /// Creates the store, restores the persisted playlists and active index,
    /// and starts the background metadata refresh.
    init(
        tagReaderService: TagReaderService,
        fileDropService: FileDropService,
        playlistStore: PlaylistStore,
        undoManager: UndoManager,
        alertCenter: AlertCenter,
        settingsStore: SettingsStore,
        userDefaults: UserDefaults
    ) {
        self.tagReaderService = tagReaderService
        self.fileDropService = fileDropService
        self.playlistStore = playlistStore
        self.undoManager = undoManager
        self.alertCenter = alertCenter
        self.settingsStore = settingsStore
        self.userDefaults = userDefaults
        self.playlists = [Playlist(name: "Playlist 1")]

        // Retain the 10 most recent track operations only; NSUndoManager
        // automatically discards the oldest when the limit is exceeded.
        undoManager.levelsOfUndo = 10

        restoreState()
    }

    // MARK: - Playlist Operations

    /// Handles URLs received from a drag-and-drop operation.
    ///
    /// Delegates URL validation to `FileDropService`, then forwards
    /// valid audio file URLs to `load(urls:)`.
    /// Invalid or non-audio URLs are silently ignored.
    func handleFileDrop(urls: [URL]) async {
        let valid = fileDropService.validate(urls)
        guard !valid.isEmpty else { return }
        await load(urls: valid)
    }

    /// Appends enriched tracks to the playlist by reading metadata for each URL.
    ///
    /// Calls `TagReaderService.readMetadata(for:)` per URL and appends the
    /// returned `Track` (title, artist, album, duration) in order.
    /// On failure, falls back to a URL-derived `Track` and sets the alert
    /// store's `lastError` to `.failedToOpenFile`. Reports the added ids
    /// through `onTracksAppended`.
    ///
    /// - Parameter urls: Audio file URLs to add.
    func load(urls: [URL]) async {
        isPerformingBlockingOperation = true
        defer { isPerformingBlockingOperation = false }
        // Reset skipped lists before each load so alerts re-trigger
        // even if the same files are dropped again.
        alertCenter.skippedDuplicateURLs   = []
        alertCenter.skippedUnsupportedURLs = []
        // Collect existing URLs to prevent duplicates within the same playlist.
        let existingURLs = Set(playlists[activePlaylistIndex].tracks.map { $0.url })
        var skipped: [URL] = []
        var addedIDs: [Track.ID] = [Track.ID]()
        for url in urls {
            if !settingsStore.allowDuplicateTracks && existingURLs.contains(url) {
                skipped.append(url)
                continue
            }

            // Format gate: reject formats not in allowedFormats. The Pro-only
            // formats are treated as unsupported, same as an unknown extension.
            let ext = url.pathExtension.lowercased()
            if !Self.allowedFormats.contains(ext) {
                alertCenter.skippedUnsupportedURLs.append(url)
                continue
            }

            // Per-iteration security-scoped access.
            //
            // The user-selected URL holds an in-process sandbox extension issued
            // by NSOpenPanel / drag-drop. start/stop scope here ensures Track
            // encode (which calls URL.bookmarkData(.withSecurityScope) inside
            // tagReaderService.readMetadata or, on failure, the Track(url:)
            // fallback) captures that extension into the persisted bookmark.
            //
            // Swift's defer is bound to the enclosing for-body scope, so stop
            // fires at the end of each iteration — the start/stop pair scopes
            // exactly one URL and never accumulates across iterations.
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let track = try await tagReaderService.readMetadata(for: url)
                playlists[activePlaylistIndex].tracks.append(track)
                addedIDs.append(track.id)
            } catch {
                let track = Track(url: url)
                playlists[activePlaylistIndex].tracks.append(track)
                addedIDs.append(track.id)
                alertCenter.lastError = .failedToOpenFile
            }
            if addedIDs.count % Self.saveBatchSize == 0 {
                saveState()
            }
        }
        if !skipped.isEmpty {
            alertCenter.skippedDuplicateURLs = skipped
        }

        // Update insertionOrder with newly added track IDs.
        // Uses addedIDs collected during the loop so duplicate-allowed tracks
        // are included correctly.
        playlists[activePlaylistIndex].insertionOrder.append(contentsOf: addedIDs)

        // Let the playback controller fold the new tracks into its shuffle
        // queue, and register undo: remove the tracks that were just added.
        // Only when at least one track was actually added.
        if !addedIDs.isEmpty {
            onTracksAppended?(addedIDs)

            // Capture the full Track values so redo can re-append them in order.
            let addedTracks = playlists[activePlaylistIndex].tracks.filter {
                addedIDs.contains($0.id)
            }
            let targetPlaylistIndex = activePlaylistIndex
            let capturedIDs = addedIDs

            undoManager.registerUndo(withTarget: self) { [addedTracks] store in
                // Undo: remove the added tracks
                let idSet = Set(capturedIDs)
                store.playlists[targetPlaylistIndex].tracks.removeAll { idSet.contains($0.id) }
                store.playlists[targetPlaylistIndex].insertionOrder.removeAll { idSet.contains($0) }

                // Register redo: re-append the same tracks
                store.undoManager.registerUndo(withTarget: store) { inner in
                    inner.playlists[targetPlaylistIndex].tracks.append(contentsOf: addedTracks)
                    inner.playlists[targetPlaylistIndex].insertionOrder
                        .append(contentsOf: addedTracks.map(\.id))
                    inner.saveState()
                }

                store.saveState()
            }
        }

        saveState()
    }

    /// Removes all tracks from the active playlist.
    func clearPlaylist() {
        playlists[activePlaylistIndex].tracks = []
        onPlaylistCleared?()
        selectedTrackIDs.removeAll()
        // Clear undo stack: no meaningful undo target after playlist is wiped.
        undoManager.removeAllActions()
        saveState()
    }

    // MARK: - Playlist Management

    /// Switches the active playlist tab without affecting playback.
    ///
    /// Encapsulates tab-switching logic so Views do not need to mutate
    /// `activePlaylistIndex` directly or manage the undo stack themselves.
    ///
    /// - Clears the undo stack so prior operations on a different playlist
    ///   cannot be accidentally applied to the new context.
    /// - No-op if `index` is out of range or already active.
    ///
    /// - Parameter index: Target playlist index.
    func switchPlaylist(to index: Int) {
        guard playlists.indices.contains(index) else { return }
        guard index != activePlaylistIndex else { return }
        activePlaylistIndex = index
        selectedTrackIDs.removeAll()
        undoManager.removeAllActions()
    }

    // MARK: - Undo / Redo

    /// Whether the undo stack has an available undo action.
    var canUndo: Bool { undoManager.canUndo }

    /// Whether the undo stack has an available redo action.
    var canRedo: Bool { undoManager.canRedo }

    /// Performs the most recent undoable playlist operation.
    func undo() { undoManager.undo() }

    /// Re-applies the most recently undone playlist operation.
    func redo() { undoManager.redo() }

    /// Appends a new empty playlist and switches to it.
    ///
    /// If `name` is empty, generates the next available "Playlist N" name
    /// by finding the lowest unused number across all existing playlists.
    ///
    /// - Parameter name: Display name for the new playlist.
    func newPlaylist(name: String) {
        let resolvedName = name.isEmpty ? nextAvailablePlaylistName() : name
        playlists.append(Playlist(name: resolvedName))
        activePlaylistIndex = playlists.count - 1
        // Clear undo stack: switched to a new playlist context.
        undoManager.removeAllActions()
        saveState()
    }

    /// Returns the next available "Playlist N" name by finding the lowest
    /// unused number across all existing playlists.
    private func nextAvailablePlaylistName() -> String {
        let usedNumbers = Set(playlists.compactMap { pl -> Int? in
            guard pl.name.hasPrefix("Playlist ") else { return nil }
            return Int(pl.name.dropFirst("Playlist ".count))
        })
        let next = (1...).first { !usedNumbers.contains($0) } ?? (playlists.count + 1)
        return "Playlist \(next)"
    }

    /// Renames the playlist at the given index.
    ///
    /// No-op if `index` is out of range.
    ///
    /// - Parameters:
    ///   - index: Index of the playlist to rename.
    ///   - name: New display name.
    func renamePlaylist(at index: Int, name: String) {
        guard playlists.indices.contains(index) else { return }
        playlists[index].name = name
        saveState()
    }

    /// Deletes the playlist at the given index.
    ///
    /// No-op if `index` is out of range.
    /// Reports the deleted playlist's id through `onPlaylistDeleted` so the
    /// playback controller can stop if it was the playing one.
    /// If deleting the last playlist, inserts an empty `"Playlist 1"` playlist
    /// before removing so `playlists` is never empty.
    /// Adjusts `activePlaylistIndex` to remain valid after deletion:
    /// - deleted index < activePlaylistIndex → decrement by 1
    /// - deleted index >= activePlaylistIndex → clamp to new last index
    ///
    /// - Parameter index: Index of the playlist to delete.
    func deletePlaylist(at index: Int) {
        guard playlists.indices.contains(index) else { return }

        onPlaylistDeleted?(playlists[index].id)

        if playlists.count == 1 {
            playlists.append(Playlist(name: "Playlist 1"))
        }
        playlists.remove(at: index)
        if index < activePlaylistIndex {
            activePlaylistIndex -= 1
        } else {
            activePlaylistIndex = min(activePlaylistIndex, playlists.count - 1)
        }
        // Clear undo stack: playlist context changed, prior track operations
        // no longer have a valid target.
        selectedTrackIDs.removeAll()
        undoManager.removeAllActions()
        saveState()
    }

    /// Removes the track with the given ID from the playlist.
    ///
    /// No-op if `trackID` is not found. Reports the removal through
    /// `onTrackRemoved` so the playback controller can stop or advance when
    /// the removed track was the current one.
    ///
    /// - Parameter trackID: The `UUID` of the track to remove.
    func removeTrack(_ trackID: Track.ID) {
        // Capture position and value BEFORE mutation so undo can restore them.
        let removalIndex = playlists[activePlaylistIndex].tracks
            .firstIndex(where: { $0.id == trackID })
        let removedTrack = removalIndex.map { playlists[activePlaylistIndex].tracks[$0] }
        let targetPlaylistIndex = activePlaylistIndex

        playlists[activePlaylistIndex].tracks.removeAll { $0.id == trackID }
        playlists[activePlaylistIndex].insertionOrder.removeAll { $0 == trackID }

        if removedTrack != nil {
            onTrackRemoved?(trackID)
        }

        // Register undo: re-insert the track at its original index.
        if let track = removedTrack, let idx = removalIndex {
            undoManager.registerUndo(withTarget: self) { [track, idx] store in
                let insertAt = min(idx, store.playlists[targetPlaylistIndex].tracks.count)
                store.playlists[targetPlaylistIndex].tracks.insert(track, at: insertAt)
                store.playlists[targetPlaylistIndex].insertionOrder.insert(track.id, at: insertAt)

                // Register redo: remove it again
                store.undoManager.registerUndo(withTarget: store) { inner in
                    inner.playlists[targetPlaylistIndex].tracks.removeAll { $0.id == track.id }
                    inner.playlists[targetPlaylistIndex].insertionOrder.removeAll { $0 == track.id }
                    inner.saveState()
                }

                store.saveState()
            }
        }

        saveState()
    }

    /// Removes every track whose ID is in `ids` from the active playlist
    /// as a single undoable batch.
    ///
    /// Used by the multi-select "Remove from Playlist" context-menu action.
    /// Only IDs present in the active playlist are removed; unknown IDs are
    /// ignored. No-op (no undo registered, no notification) when no ID in
    /// the set matches a track in the active playlist.
    ///
    /// Reports the removed ids through `onTracksRemoved` so the playback
    /// controller can stop when the current track was among them. The whole
    /// batch is one undo action that restores `tracks` and `insertionOrder`
    /// together.
    ///
    /// - Parameter ids: The set of track IDs to remove.
    func removeTracks(_ ids: Set<Track.ID>) {
        let targetPlaylistIndex = activePlaylistIndex

        // Snapshot before mutation so the whole batch undoes atomically.
        let beforeTracks = playlists[targetPlaylistIndex].tracks
        let beforeInsertionOrder = playlists[targetPlaylistIndex].insertionOrder

        // Restrict to IDs that actually exist in the active playlist.
        let removedIDs = Set(beforeTracks.map(\.id).filter { ids.contains($0) })
        guard !removedIDs.isEmpty else { return }

        // Remove from tracks + insertionOrder in a single pass.
        playlists[targetPlaylistIndex].tracks.removeAll { removedIDs.contains($0.id) }
        playlists[targetPlaylistIndex].insertionOrder.removeAll { removedIDs.contains($0) }

        onTracksRemoved?(removedIDs)

        // Snapshot after mutation for redo.
        let afterTracks = playlists[targetPlaylistIndex].tracks
        let afterInsertionOrder = playlists[targetPlaylistIndex].insertionOrder

        // Register ONE undo for the whole batch.
        undoManager.registerUndo(withTarget: self) {
            [beforeTracks, beforeInsertionOrder] store in
            store.playlists[targetPlaylistIndex].tracks = beforeTracks
            store.playlists[targetPlaylistIndex].insertionOrder = beforeInsertionOrder

            // Register redo: re-apply the batch removal.
            store.undoManager.registerUndo(withTarget: store) {
                [afterTracks, afterInsertionOrder] inner in
                inner.playlists[targetPlaylistIndex].tracks = afterTracks
                inner.playlists[targetPlaylistIndex].insertionOrder = afterInsertionOrder
                inner.saveState()
            }

            store.saveState()
        }

        saveState()
    }

    /// Inserts a track immediately after the current track.
    ///
    /// Allows the user to queue a specific track to play next without
    /// interrupting current playback. The caller passes the current track's
    /// id, because the store does not read playback state; the playback
    /// controller is told through `onTrackQueuedNext` so it can re-queue the
    /// track in shuffle mode.
    ///
    /// - Parameters:
    ///   - trackID: The `UUID` of the track to play next.
    ///   - currentID: The current track's id, or `nil` to insert at the front.
    func playNext(_ trackID: Track.ID, afterCurrent currentID: Track.ID?) {
        guard let track = playlists[activePlaylistIndex].tracks.first(where: { $0.id == trackID }) else { return }

        // Find current playing position in playlist
        let currentIndex = currentID.flatMap { id in
            playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == id })
        } ?? -1

        let insertIndex = currentIndex + 1

        // Remove from current position if already in playlist
        playlists[activePlaylistIndex].tracks.removeAll { $0.id == trackID }

        // Re-insert after current track
        let clampedIndex = min(insertIndex, playlists[activePlaylistIndex].tracks.count)
        playlists[activePlaylistIndex].tracks.insert(track, at: clampedIndex)

        // Keep insertionOrder in sync with the new track order
        playlists[activePlaylistIndex].insertionOrder = playlists[activePlaylistIndex].tracks.map { $0.id }

        onTrackQueuedNext?(trackID)

        saveState()
    }

    /// Applies a sorted track order and records the sort state in the playlist.
    ///
    /// Called by the playlist view when the user clicks a column header.
    /// Reorders `playlists[activePlaylistIndex].tracks` so playback follows
    /// the sorted order. The shuffle queue is an independent playback order
    /// and is not touched by column sorting.
    func applySort(_ sorted: [Track], key: PlaylistSortKey, ascending: Bool) {
        playlists[activePlaylistIndex].tracks = sorted
        playlists[activePlaylistIndex].sortKey = key
        playlists[activePlaylistIndex].sortAscending = ascending
        saveState()
    }

    /// Restores insertion order and clears sort state.
    func restoreInsertionOrder() {
        let ordered = playlists[activePlaylistIndex].insertionOrder.compactMap { id in
            playlists[activePlaylistIndex].tracks.first { $0.id == id }
        }
        playlists[activePlaylistIndex].tracks = ordered
        playlists[activePlaylistIndex].sortKey = .none
        playlists[activePlaylistIndex].sortAscending = true
        saveState()
    }

    /// Reorders tracks in the playlist.
    ///
    /// Signature is compatible with SwiftUI's `onMove` callback.
    /// Implemented without SwiftUI import to maintain module boundary.
    ///
    /// - Parameters:
    ///   - fromOffsets: Source indices
    ///   - toOffset: Destination offset
    func moveTrack(fromOffsets: IndexSet, toOffset: Int) {
        // Capture snapshot before mutation so undo can restore previous order.
        let beforeTracks = playlists[activePlaylistIndex].tracks
        let targetPlaylistIndex = activePlaylistIndex

        let itemsToMove = fromOffsets.map { playlists[activePlaylistIndex].tracks[$0] }
        var result = playlists[activePlaylistIndex].tracks.enumerated()
            .filter { !fromOffsets.contains($0.offset) }
            .map { $0.element }
        let adjustedOffset = toOffset - fromOffsets.filter { $0 < toOffset }.count
        result.insert(contentsOf: itemsToMove, at: min(adjustedOffset, result.count))
        playlists[activePlaylistIndex].tracks = result
        // Keep insertionOrder in sync with the new track order so that
        // restoreInsertionOrder() reflects the user's manual reorder.
        playlists[activePlaylistIndex].insertionOrder = result.map { $0.id }

        // Capture snapshot after mutation for redo.
        let afterTracks = playlists[activePlaylistIndex].tracks

        // Register undo: restore previous order.
        undoManager.registerUndo(withTarget: self) { [beforeTracks, afterTracks] store in
            store.playlists[targetPlaylistIndex].tracks = beforeTracks
            store.playlists[targetPlaylistIndex].insertionOrder = beforeTracks.map(\.id)

            // Register redo: re-apply the move.
            store.undoManager.registerUndo(withTarget: store) { inner in
                inner.playlists[targetPlaylistIndex].tracks = afterTracks
                inner.playlists[targetPlaylistIndex].insertionOrder = afterTracks.map(\.id)
                inner.saveState()
            }

            store.saveState()
        }

        saveState()
    }

    /// Moves the dragged track so it sits immediately before `targetID`,
    /// or to the end of the playlist when `targetID` is `nil`.
    ///
    /// UI-facing entry point for drag-to-reorder: it resolves indices from
    /// track IDs and delegates to `moveTrack(fromOffsets:toOffset:)`, so undo
    /// and `insertionOrder` sync reuse the existing path. The view passes IDs
    /// only and performs no index math.
    ///
    /// No-op when a column sort is active (`sortKey != .none`), when the row is
    /// dropped onto itself, or when `draggedID` is not in the active playlist.
    ///
    /// - Parameters:
    ///   - draggedID: The track being dragged.
    ///   - targetID: The row to drop before, or `nil` to append to the end.
    func moveTrack(id draggedID: Track.ID, before targetID: Track.ID?) {
        // Manual reorder is disabled while a column sort is active.
        guard playlists[activePlaylistIndex].sortKey == .none else { return }
        // Dropping a row onto itself changes nothing.
        guard draggedID != targetID else { return }

        let tracks = playlists[activePlaylistIndex].tracks
        guard let fromIndex = tracks.firstIndex(where: { $0.id == draggedID }) else { return }

        // toOffset uses the source-array indexing expected by
        // moveTrack(fromOffsets:toOffset:): the dragged track is inserted
        // before the target's current index, or appended when there is no
        // (resolvable) target.
        let toOffset: Int
        if let targetID, let targetIndex = tracks.firstIndex(where: { $0.id == targetID }) {
            toOffset = targetIndex
        } else {
            toOffset = tracks.count
        }

        moveTrack(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
    }

    // MARK: - File Info

    /// Requests the File Info window to open for the track with the given ID.
    ///
    /// Looks the track up in the active playlist and hands the request to
    /// `alertCenter.presentFileInfo(_:)`. If no matching track is found,
    /// the call is a no-op and the pending request remains unchanged.
    func showFileInfo(trackID: Track.ID) {
        guard let track = playlist.tracks.first(where: { $0.id == trackID }) else { return }
        alertCenter.presentFileInfo(track)
    }

    // MARK: - Persistence

    /// Saves the playlists to the playlist store and `activePlaylistIndex`
    /// to UserDefaults.
    ///
    /// Called by every playlist mutation and by the composition root's
    /// terminate-time save-all.
    func saveState() {
        try? playlistStore.save(playlists)
        userDefaults.set(activePlaylistIndex, forKey: PersistenceKey.activePlaylistIndex)
    }

    /// Restores previously saved playlist state.
    ///
    /// Called once at the end of `init`. When no persisted data exists, the
    /// default values set in `init` are preserved.
    func restoreState() {
        // Load playlists from the file-backed store. When the store has nothing
        // yet, migrate playlists previously kept in UserDefaults and remove the
        // legacy key so the migration runs only once.
        var restoredPlaylists = try? playlistStore.load()
        if restoredPlaylists == nil,
           let legacyData = userDefaults.data(forKey: PersistenceKey.playlists),
           let legacy = try? JSONDecoder().decode([Playlist].self, from: legacyData) {
            restoredPlaylists = legacy
            try? playlistStore.save(legacy)
            userDefaults.removeObject(forKey: PersistenceKey.playlists)
        }
        if let decoded = restoredPlaylists, !decoded.isEmpty {
            playlists = decoded
            let savedIndex = userDefaults.integer(forKey: PersistenceKey.activePlaylistIndex)
            activePlaylistIndex = max(0, min(savedIndex, playlists.count - 1))

            // Application Layer accessibility check: mark tracks inaccessible
            // if the file no longer exists at its original stored path, or is in Trash.
            // Use originalPath (urlPath stored at encode time), not url.path
            // which bookmark may have resolved to Trash or another location.
            for i in playlists.indices {
                for j in playlists[i].tracks.indices {
                    let path = playlists[i].tracks[j].originalPath
                    if path.isEmpty
                        || path.contains("/.Trash/")
                        || !FileManager.default.fileExists(atPath: path) {
                        playlists[i].tracks[j].isAccessible = false
                    }
                }
            }
        }
        // Background metadata refresh: re-reads fields for tracks that were
        // saved by an older version of the metadata reading logic.
        Task { await refreshMetadataIfNeeded() }
    }

    /// Re-reads metadata for any track whose `metadataVersion` is lower than
    /// `tagReaderService.currentSchemaVersion`.
    ///
    /// Runs in the background after `restoreState()`. Only tracks restored from
    /// older saves (version 0) are affected. New fields are written back and
    /// `saveState()` is called so the refresh only happens once per track.
    func refreshMetadataIfNeeded() async {
        var didRefreshAny = false

        // Snapshot track IDs and URLs that need refresh, so we don't
        // rely on indices that may become stale across await points.
        struct RefreshCandidate {
            let id: Track.ID
            let url: URL
        }

        var candidates: [RefreshCandidate] = []
        for playlist in playlists {
            for track in playlist.tracks {
                if track.isAccessible,
                   track.metadataVersion < tagReaderService.currentSchemaVersion
                       || track.artworkData == nil {
                    candidates.append(RefreshCandidate(id: track.id, url: track.url))
                }
            }
        }

        for candidate in candidates {
            guard let refreshed = try? await tagReaderService.readMetadata(for: candidate.url)
            else { continue }

            // Re-locate the track by ID after the async suspension.
            // The user may have reordered, removed, or added tracks while
            // readMetadata was running, so stale indices are unsafe.
            guard let pi = playlists.firstIndex(where: { $0.tracks.contains { $0.id == candidate.id } }),
                  let ti = playlists[pi].tracks.firstIndex(where: { $0.id == candidate.id })
            else { continue }

            // Merge: update only new-field groups; preserve core fields
            // (title, artist, album, duration) from the stored version
            // so user-visible data is not unexpectedly replaced.
            playlists[pi].tracks[ti].albumArtist     = refreshed.albumArtist
            playlists[pi].tracks[ti].composer        = refreshed.composer
            playlists[pi].tracks[ti].genre           = refreshed.genre
            playlists[pi].tracks[ti].year            = refreshed.year
            playlists[pi].tracks[ti].trackNumber     = refreshed.trackNumber
            playlists[pi].tracks[ti].trackTotal      = refreshed.trackTotal
            playlists[pi].tracks[ti].discNumber      = refreshed.discNumber
            playlists[pi].tracks[ti].discTotal       = refreshed.discTotal
            playlists[pi].tracks[ti].bpm             = refreshed.bpm
            playlists[pi].tracks[ti].replayGainTrack = refreshed.replayGainTrack
            playlists[pi].tracks[ti].replayGainAlbum = refreshed.replayGainAlbum
            playlists[pi].tracks[ti].comment         = refreshed.comment
            playlists[pi].tracks[ti].bitrate         = refreshed.bitrate
            playlists[pi].tracks[ti].sampleRate      = refreshed.sampleRate
            playlists[pi].tracks[ti].channels        = refreshed.channels
            playlists[pi].tracks[ti].fileSize        = refreshed.fileSize
            playlists[pi].tracks[ti].fileFormat      = refreshed.fileFormat
            playlists[pi].tracks[ti].codec           = refreshed.codec
            playlists[pi].tracks[ti].encoding        = refreshed.encoding
            playlists[pi].tracks[ti].artworkData     = refreshed.artworkData
            playlists[pi].tracks[ti].lyrics          = refreshed.lyrics
            playlists[pi].tracks[ti].metadataVersion = tagReaderService.currentSchemaVersion

            didRefreshAny = true
        }

        if didRefreshAny { saveState() }
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}
}
