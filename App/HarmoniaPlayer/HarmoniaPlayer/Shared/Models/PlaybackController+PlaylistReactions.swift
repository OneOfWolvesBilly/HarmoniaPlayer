//
//  PlaybackController+PlaylistReactions.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// Reactions to playlist mutations, reached through the playlist
/// collection's root-wired closures: shuffle-queue upkeep, and stopping or
/// advancing when the playing track or playlist goes away.
extension PlaybackController {

    // MARK: - Tracks added

    /// Folds newly added tracks into the shuffle queue.
    ///
    /// When shuffle is active, each id is inserted at a random position
    /// strictly after the current playing position (`shuffleQueueIndex + 1`)
    /// so the new track can be played in the current round; at the last
    /// position it is appended. Nothing happens when shuffle is off.
    func handleTracksAppended(_ ids: [Track.ID]) {
        guard isShuffled else { return }
        for id in ids {
            let afterCurrent = shuffleQueueIndex + 1
            let end = shuffleQueue.count
            let insertIndex = afterCurrent <= end
                ? Int.random(in: afterCurrent...end)
                : end
            shuffleQueue.insert(id, at: insertIndex)
        }
    }

    // MARK: - Track removed

    /// Reacts to the removal of one track from the active playlist.
    ///
    /// When the removed track is the current one: if it was playing, the
    /// service is stopped and playback continues with the next track — the
    /// queue entry at `shuffleQueueIndex` under shuffle, otherwise the first
    /// track of the active playlist — or stops when the playlist is empty or
    /// no next track resolves; if it was not playing, `currentTrack` is
    /// cleared. In shuffle mode the id is then removed from the queue and
    /// `shuffleQueueIndex` shifts back when the removed position was before
    /// it.
    func handleTrackRemoved(_ id: Track.ID) {
        let wasCurrentTrack = currentTrack?.id == id
        let wasPlaying = wasCurrentTrack && playbackState == .playing

        if wasCurrentTrack {
            if wasPlaying {
                // Resolve the next track before the queue is edited.
                let tracks = playlistContext.playlists[playlistContext.activePlaylistIndex].tracks
                let nextTrackID: Track.ID? = {
                    guard !tracks.isEmpty else { return nil }
                    if isShuffled, let next = shuffleQueue[safe: shuffleQueueIndex] {
                        return next
                    }
                    return tracks.first?.id
                }()

                Task {
                    await playbackService.stop()
                    currentTrack = nil
                    let remaining = playlistContext.playlists[playlistContext.activePlaylistIndex].tracks
                    if remaining.isEmpty || nextTrackID == nil {
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

        // Remove from the shuffle queue and adjust the index if needed.
        if isShuffled, let removedIdx = shuffleQueue.firstIndex(of: id) {
            shuffleQueue.remove(at: removedIdx)
            // If the removed track was before the current position, shift the
            // index back so it still points to the same track. If it was the
            // current position, the index stays (now pointing to the next
            // track in the queue).
            if removedIdx < shuffleQueueIndex {
                shuffleQueueIndex = max(0, shuffleQueueIndex - 1)
            }
        }
    }

    // MARK: - Tracks removed

    /// Reacts to a batch removal from the active playlist.
    ///
    /// In shuffle mode the removed ids leave the queue and the index is
    /// clamped. When the current track is among them, the service is stopped
    /// and the transport shows the stopped state.
    func handleTracksRemoved(_ ids: Set<Track.ID>) {
        if isShuffled {
            shuffleQueue.removeAll { ids.contains($0) }
            shuffleQueueIndex = min(shuffleQueueIndex, max(0, shuffleQueue.count - 1))
        }

        let removingCurrentTrack = currentTrack.map { ids.contains($0.id) } ?? false
        if removingCurrentTrack {
            Task {
                await playbackService.stop()
                currentTrack = nil
                currentTime = 0
                playbackState = .stopped
            }
        }
    }

    // MARK: - Playlist cleared / deleted

    /// Reacts to the active playlist being cleared: the current track is
    /// cleared; the playback state and the service are left as they are.
    func handlePlaylistCleared() {
        currentTrack = nil
    }

    /// Reacts to a playlist being deleted: stops playback when it was the
    /// playing playlist.
    func handlePlaylistDeleted(_ id: Playlist.ID) {
        guard id == playingPlaylistID else { return }
        Task {
            await stop()
        }
    }

    // MARK: - Track queued next

    /// Reacts to a track being queued to play next: in shuffle mode the id
    /// moves to the position right after the current one in the queue.
    func handleTrackQueuedNext(_ id: Track.ID) {
        guard isShuffled else { return }
        shuffleQueue.removeAll { $0 == id }
        let nextQueueIndex = min(shuffleQueueIndex + 1, shuffleQueue.count)
        shuffleQueue.insert(id, at: nextQueueIndex)
    }
}
