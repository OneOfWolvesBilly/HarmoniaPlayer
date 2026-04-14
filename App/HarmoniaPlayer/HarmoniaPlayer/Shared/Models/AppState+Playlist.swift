//
//  AppState+Playlist.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE: Playlist operations (load, remove, move, clear, sort), playlist tab
//  management (new, rename, delete, switch), and undo / redo.
//

import Foundation

extension AppState {

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
    /// On failure, falls back to a URL-derived `Track` and sets `lastError`
    /// to `.failedToOpenFile`.
    ///
    /// - Parameter urls: Audio file URLs to add.
    func load(urls: [URL]) async {
        isPerformingBlockingOperation = true
        defer { isPerformingBlockingOperation = false }
        // Reset skipped lists before each load so alerts re-trigger
        // even if the same files are dropped again.
        skippedDuplicateURLs   = []
        skippedUnsupportedURLs = []
        // Collect existing URLs to prevent duplicates within the same playlist.
        let existingURLs = Set(playlists[activePlaylistIndex].tracks.map { $0.url })
        var skipped: [URL] = []
        var addedIDs: [Track.ID] = [Track.ID]()
        for url in urls {
            if !allowDuplicateTracks && existingURLs.contains(url) {
                skipped.append(url)
                continue
            }

            // Format gate: reject formats not in allowedFormats.
            // v0.1 frozen: allowedFormats == freeFormats only.
            // FLAC/DSF/DFF are treated as unsupported, same as .xyz.
            let ext = url.pathExtension.lowercased()
            if !Self.allowedFormats.contains(ext) {
                skippedUnsupportedURLs.append(url)
                continue
            }

            do {
                let track = try await tagReaderService.readMetadata(for: url)
                playlists[activePlaylistIndex].tracks.append(track)
                addedIDs.append(track.id)
            } catch {
                let track = Track(url: url)
                playlists[activePlaylistIndex].tracks.append(track)
                addedIDs.append(track.id)
                lastError = .failedToOpenFile
            }
            if addedIDs.count % Self.saveBatchSize == 0 {
                saveState()
            }
        }
        if !skipped.isEmpty {
            skippedDuplicateURLs = skipped
        }

        // Update insertionOrder with newly added track IDs.
        // Uses addedIDs collected during the loop so duplicate-allowed tracks
        // are included correctly.
        playlists[activePlaylistIndex].insertionOrder.append(contentsOf: addedIDs)

        // If shuffle is active, insert newly added tracks at random positions
        // in the remaining (unplayed) portion of the shuffleQueue.
        if isShuffled {
            for id in addedIDs {
                // Insert at a random position strictly after the current playing track
                // (shuffleQueueIndex + 1) so the new track can be played in the
                // current round. If we're at the last track, append at the end.
                let afterCurrent = shuffleQueueIndex + 1
                let end = shuffleQueue.count
                let insertIndex = afterCurrent <= end
                    ? Int.random(in: afterCurrent...end)
                    : end
                shuffleQueue.insert(id, at: insertIndex)
            }
        }

        // Register undo: remove the tracks that were just added.
        // Only register when at least one track was actually added.
        if !addedIDs.isEmpty {
            // Capture the full Track values so redo can re-append them in order.
            let addedTracks = playlists[activePlaylistIndex].tracks.filter {
                addedIDs.contains($0.id)
            }
            let targetPlaylistIndex = activePlaylistIndex
            let capturedIDs = addedIDs

            undoManager.registerUndo(withTarget: self) { [addedTracks] state in
                // Undo: remove the added tracks
                let idSet = Set(capturedIDs)
                state.playlists[targetPlaylistIndex].tracks.removeAll { idSet.contains($0.id) }
                state.playlists[targetPlaylistIndex].insertionOrder.removeAll { idSet.contains($0) }

                // Register redo: re-append the same tracks
                state.undoManager.registerUndo(withTarget: state) { inner in
                    inner.playlists[targetPlaylistIndex].tracks.append(contentsOf: addedTracks)
                    inner.playlists[targetPlaylistIndex].insertionOrder
                        .append(contentsOf: addedTracks.map(\.id))
                    inner.saveState()
                }

                state.saveState()
            }
        }

        saveState()
    }

    /// Removes all tracks from the active playlist.
    func clearPlaylist() {
        playlists[activePlaylistIndex].tracks = []
        currentTrack = nil
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
    /// If deleting the last playlist, inserts an empty `"Session"` playlist
    /// before removing so `playlists` is never empty.
    /// Adjusts `activePlaylistIndex` to remain valid after deletion:
    /// - deleted index < activePlaylistIndex → decrement by 1
    /// - deleted index >= activePlaylistIndex → clamp to new last index
    ///
    /// - Parameter index: Index of the playlist to delete.
    func deletePlaylist(at index: Int) {
        guard playlists.indices.contains(index) else { return }

        // If deleting the playlist that is currently playing, stop playback first.
        if playlists[index].id == playingPlaylistID {
            Task {
                await stop()
                currentTrack = nil
            }
        }

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
    /// No-op if `trackID` is not found. Sets `currentTrack` to `nil`
    /// if the removed track was selected.
    ///
    /// - Parameter trackID: The `UUID` of the track to remove.
    func removeTrack(_ trackID: Track.ID) {
        let wasPlaying = currentTrack?.id == trackID && playbackState == .playing
        let wasCurrentTrack = currentTrack?.id == trackID

        // Capture position and value BEFORE mutation so undo can restore them.
        let removalIndex = playlists[activePlaylistIndex].tracks
            .firstIndex(where: { $0.id == trackID })
        let removedTrack = removalIndex.map { playlists[activePlaylistIndex].tracks[$0] }
        let targetPlaylistIndex = activePlaylistIndex

        playlists[activePlaylistIndex].tracks.removeAll { $0.id == trackID }
        playlists[activePlaylistIndex].insertionOrder.removeAll { $0 == trackID }

        if wasCurrentTrack {
            if wasPlaying {
                // Find the next track to play before clearing currentTrack.
                // After removal, the track that was at the next index is now
                // at the same index (or we wrap to first if it was the last).
                let nextTrackID: Track.ID? = {
                    guard !playlists[activePlaylistIndex].tracks.isEmpty else { return nil }
                    if isShuffled, let nextIdx = shuffleQueue[safe: shuffleQueueIndex] {
                        return nextIdx
                    }
                    // In normal mode, find the original index of removed track.
                    // After removal, that index now points to the next track.
                    // If removed track was the last one, there is no next track
                    // (unless repeatMode == .all wraps to first).
                    guard let removedIdx = playlists[activePlaylistIndex].insertionOrder.firstIndex(of: trackID)
                    else { return playlists[activePlaylistIndex].tracks.first?.id }

                    if removedIdx < playlists[activePlaylistIndex].tracks.count {
                        // There is a track at this index (the one that shifted up)
                        return playlists[activePlaylistIndex].tracks[removedIdx].id
                    } else if repeatMode == .all {
                        // Removed track was last — wrap to first if repeat all
                        return playlists[activePlaylistIndex].tracks.first?.id
                    } else {
                        // Removed track was last — stop
                        return nil
                    }
                }()

                Task {
                    await playbackService.stop()
                    currentTrack = nil
                    if playlists[activePlaylistIndex].tracks.isEmpty || nextTrackID == nil {
                        playbackState = .stopped
                        currentTime = 0
                    } else if let nextID = nextTrackID {
                        await play(trackID: nextID)
                    }
                }
            } else {
                currentTrack = nil
            }
        }

        // Remove from shuffleQueue and adjust index if needed.
        if isShuffled, let removedIdx = shuffleQueue.firstIndex(of: trackID) {
            shuffleQueue.remove(at: removedIdx)
            // If removed track was before current position, shift index back
            // so shuffleQueueIndex still points to the same track.
            if removedIdx < shuffleQueueIndex {
                shuffleQueueIndex = max(0, shuffleQueueIndex - 1)
            }
            // If removed track was the current position, index stays the same
            // (now pointing to the next track in queue).
        }

        // Register undo: re-insert the track at its original index.
        if let track = removedTrack, let idx = removalIndex {
            undoManager.registerUndo(withTarget: self) { [track, idx] state in
                let insertAt = min(idx, state.playlists[targetPlaylistIndex].tracks.count)
                state.playlists[targetPlaylistIndex].tracks.insert(track, at: insertAt)
                state.playlists[targetPlaylistIndex].insertionOrder.insert(track.id, at: insertAt)

                // Register redo: remove it again
                state.undoManager.registerUndo(withTarget: state) { inner in
                    inner.playlists[targetPlaylistIndex].tracks.removeAll { $0.id == track.id }
                    inner.playlists[targetPlaylistIndex].insertionOrder.removeAll { $0 == track.id }
                    inner.saveState()
                }

                state.saveState()
            }
        }

        saveState()
    }

    /// Inserts a track immediately after the currently playing track.
    ///
    /// Allows the user to queue a specific track to play next without
    /// interrupting current playback. If shuffle is active, also inserts
    /// the track at the next position in the shuffle queue.
    ///
    /// - Parameter trackID: The `UUID` of the track to play next.
    func playNext(_ trackID: Track.ID) {
        guard let track = playlists[activePlaylistIndex].tracks.first(where: { $0.id == trackID }) else { return }

        // Find current playing position in playlist
        let currentIndex = currentTrack.flatMap { ct in
            playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == ct.id })
        } ?? -1

        let insertIndex = currentIndex + 1

        // Remove from current position if already in playlist
        playlists[activePlaylistIndex].tracks.removeAll { $0.id == trackID }

        // Re-insert after current track
        let clampedIndex = min(insertIndex, playlists[activePlaylistIndex].tracks.count)
        playlists[activePlaylistIndex].tracks.insert(track, at: clampedIndex)

        // Keep insertionOrder in sync with the new track order
        playlists[activePlaylistIndex].insertionOrder = playlists[activePlaylistIndex].tracks.map { $0.id }

        // If shuffle is active, also insert at next position in queue
        if isShuffled {
            shuffleQueue.removeAll { $0 == trackID }
            let nextQueueIndex = min(shuffleQueueIndex + 1, shuffleQueue.count)
            shuffleQueue.insert(trackID, at: nextQueueIndex)
        }

        saveState()
    }

    /// Applies a sorted track order to the playlist.
    ///
    /// Called by PlaylistView when the user clicks a column header.
    /// Reorders `playlists[activePlaylistIndex].tracks` so playback follows the sorted order.
    /// Applies a sorted track order and records the sort state in the playlist.
    func applySort(_ sorted: [Track], key: PlaylistSortKey, ascending: Bool) {
        playlists[activePlaylistIndex].tracks = sorted
        playlists[activePlaylistIndex].sortKey = key
        playlists[activePlaylistIndex].sortAscending = ascending
        // Do NOT rebuild shuffleQueue here — sort only changes the visual display
        // order in PlaylistView. shuffleQueue is an independent playback order
        // and must not be affected by column sorting.
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
        // Do NOT rebuild shuffleQueue here — same reason as applySort().
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
        undoManager.registerUndo(withTarget: self) { [beforeTracks, afterTracks] state in
            state.playlists[targetPlaylistIndex].tracks = beforeTracks
            state.playlists[targetPlaylistIndex].insertionOrder = beforeTracks.map(\.id)

            // Register redo: re-apply the move.
            state.undoManager.registerUndo(withTarget: state) { inner in
                inner.playlists[targetPlaylistIndex].tracks = afterTracks
                inner.playlists[targetPlaylistIndex].insertionOrder = afterTracks.map(\.id)
                inner.saveState()
            }

            state.saveState()
        }

        saveState()
    }
}
