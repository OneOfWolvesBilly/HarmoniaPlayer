//
//  PlaybackController+Navigation.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// Track navigation: next / previous, natural track completion, and the
/// shuffle queue.
extension PlaybackController {

    // MARK: - Navigation

    /// Plays the next track in the playlist.
    ///
    /// Behaviour depends on `repeatMode`:
    /// - `.off`: Advance to next; stop if already at last track.
    /// - `.all`: Advance to next; loop to first if at last track.
    /// - `.one`: Replay current track.
    ///
    /// No-op if playlist is empty.
    func playNextTrack() async {
        guard let context = playlistContext else { return }
        let tracks = context.playlists[context.activePlaylistIndex].tracks
        guard !tracks.isEmpty else { return }

        // repeatMode == .one does NOT intercept Next/Previous button presses.
        // The button should navigate the playlist; repeat-one only applies to
        // natural track completion (trackDidFinishPlaying).

        if isShuffled {
            // Rebuild queue if it's empty or stale
            if shuffleQueue.isEmpty {
                buildShuffleQueue(startingWith: currentTrack?.id)
            }
            let nextIndex = shuffleQueueIndex + 1
            if nextIndex < shuffleQueue.count {
                shuffleQueueIndex = nextIndex
            } else {
                // Queue exhausted — rebuild and start from beginning
                buildShuffleQueue()
                shuffleQueueIndex = 0
            }
            if let trackID = shuffleQueue[safe: shuffleQueueIndex] {
                await play(trackID: trackID)
            }
            return
        }

        guard let current = currentTrack,
              let currentIndex = tracks.firstIndex(where: { $0.id == current.id })
        else {
            await play(trackID: tracks[0].id)
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < tracks.count {
            await play(trackID: tracks[nextIndex].id)
        } else {
            // At last track — always wrap to first regardless of repeatMode.
            // Natural completion (trackDidFinishPlaying) respects repeatMode;
            // manual Next button always wraps for better user experience.
            await play(trackID: tracks[0].id)
        }
    }

    /// Plays the previous track in the playlist.
    ///
    /// If `currentTrack` is the first track, seeks to the beginning
    /// and replays it instead of wrapping around.
    ///
    /// No-op if playlist is empty.
    func playPreviousTrack() async {
        guard let context = playlistContext else { return }
        let tracks = context.playlists[context.activePlaylistIndex].tracks
        guard !tracks.isEmpty else { return }

        if isShuffled {
            if shuffleQueue.isEmpty { buildShuffleQueue(startingWith: currentTrack?.id) }
            let prevIndex = shuffleQueueIndex - 1
            if prevIndex >= 0 {
                shuffleQueueIndex = prevIndex
                if let trackID = shuffleQueue[safe: shuffleQueueIndex] {
                    await play(trackID: trackID)
                }
            } else {
                // At beginning of shuffle queue — restart current track
                if let current = currentTrack {
                    await play(trackID: current.id)
                }
            }
            return
        }

        guard let current = currentTrack,
              let currentIndex = tracks.firstIndex(where: { $0.id == current.id })
        else {
            await play(trackID: tracks[0].id)
            return
        }

        if currentIndex > 0 {
            await play(trackID: tracks[currentIndex - 1].id)
        } else {
            do {
                try await playbackService.seek(to: 0)
                currentTime = 0
            } catch {
                alertCenter.lastError = mapToPlaybackError(error)
            }
            await play(trackID: current.id)
        }
    }

    /// Called when natural playback completion is detected by the polling loop.
    ///
    /// Dispatches based on `repeatMode`:
    /// - `.off`: advance to the next playable track; stop if at last.
    /// - `.all`: advance to the next playable track; loop if at last.
    /// - `.one`: replay the last played track.
    ///
    /// Inaccessible tracks are skipped and listed in the file-not-found
    /// alert. No-op if no track has been played.
    func trackDidFinishPlaying() async {
        guard let context = playlistContext else { return }
        guard let lastID = lastPlayedTrackID else { return }
        guard let playingIndex = context.playlists.firstIndex(where: { $0.id == playingPlaylistID }) else {
            await stop()
            currentTrack = nil
            return
        }
        switch repeatMode {
        case .off:
            if isShuffled {
                // Shuffle mode: advance through queue skipping inaccessible tracks
                // and format-gated tracks (when paywallDismissedThisSession is true).
                var skipped: [String] = []
                var nextIndex = shuffleQueueIndex + 1
                while nextIndex < shuffleQueue.count {
                    guard let trackID = shuffleQueue[safe: nextIndex],
                          let next = context.playlists[playingIndex].tracks.first(where: { $0.id == trackID })
                    else { nextIndex += 1; continue }

                    // Format gate disabled — Pro formats cannot enter the playlist.
                    // Silently skip format-gated tracks if user dismissed paywall this session.
                    // let nextExt = next.url.pathExtension.lowercased()
                    // let isFormatGated = AppState.proOnlyFormats.contains(nextExt) && !settingsStore.featureFlags.supportsFLAC
                    // if isFormatGated && alertCenter.paywallDismissedThisSession {
                    //     nextIndex += 1
                    //     continue
                    // }

                    if next.isAccessible {
                        shuffleQueueIndex = nextIndex
                        await play(trackID: next.id)
                        if case .error(.failedToOpenFile) = playbackState {
                            skipped.append(next.displayName)
                            nextIndex += 1
                            continue
                        }
                        if !skipped.isEmpty {
                            alertCenter.skippedInaccessibleNames = skipped
                            alertCenter.showFileNotFoundAlert = true
                        }
                        return
                    } else {
                        skipped.append(next.displayName)
                    }
                    nextIndex += 1
                }
                // Queue exhausted — show popup and stop.
                if !skipped.isEmpty {
                    alertCenter.skippedInaccessibleNames = skipped
                    alertCenter.showFileNotFoundAlert = true
                }
                await stop()
                currentTrack = nil
                shuffleQueue = []
                shuffleQueueIndex = 0
            } else {
                // Normal mode: skip inaccessible tracks and format-gated tracks
                // (when paywallDismissedThisSession is true).
                guard let currentIndex = context.playlists[playingIndex].tracks.firstIndex(where: { $0.id == lastID })
                else { return }
                var skipped: [String] = []
                var nextIndex = currentIndex + 1
                while nextIndex < context.playlists[playingIndex].tracks.count {
                    let next = context.playlists[playingIndex].tracks[nextIndex]

                    // Format gate disabled — Pro formats cannot enter the playlist.
                    // Silently skip format-gated tracks if user dismissed paywall this session.
                    // let nextExt = next.url.pathExtension.lowercased()
                    // let isFormatGated = AppState.proOnlyFormats.contains(nextExt) && !settingsStore.featureFlags.supportsFLAC
                    // if isFormatGated && alertCenter.paywallDismissedThisSession {
                    //     nextIndex += 1
                    //     continue
                    // }

                    if next.isAccessible {
                        await play(trackID: next.id)
                        if case .error(.failedToOpenFile) = playbackState {
                            skipped.append(next.displayName)
                            nextIndex += 1
                            continue
                        }
                        if !skipped.isEmpty {
                            alertCenter.skippedInaccessibleNames = skipped
                            alertCenter.showFileNotFoundAlert = true
                        }
                        return
                    } else {
                        skipped.append(next.displayName)
                    }
                    nextIndex += 1
                }
                // No more playable tracks — show popup and stop.
                if !skipped.isEmpty {
                    alertCenter.skippedInaccessibleNames = skipped
                    alertCenter.showFileNotFoundAlert = true
                }
                await stop()
                currentTrack = nil
            }
        case .all:
            // Wrap around skipping inaccessible tracks and format-gated tracks
            // (when paywallDismissedThisSession is true).
            guard let currentIndex = context.playlists[playingIndex].tracks.firstIndex(where: { $0.id == lastID })
            else { return }
            let count = context.playlists[playingIndex].tracks.count
            var nextIndex = (currentIndex + 1) % count
            var attempts = 0
            var skipped: [String] = []
            while attempts < count {
                let next = context.playlists[playingIndex].tracks[nextIndex]

                // Format gate disabled — Pro formats cannot enter the playlist.
                // Silently skip format-gated tracks if user dismissed paywall this session.
                // let nextExt = next.url.pathExtension.lowercased()
                // let isFormatGated = AppState.proOnlyFormats.contains(nextExt) && !settingsStore.featureFlags.supportsFLAC
                // if isFormatGated && alertCenter.paywallDismissedThisSession {
                //     nextIndex = (nextIndex + 1) % count
                //     attempts += 1
                //     continue
                // }

                if next.isAccessible {
                    await play(trackID: next.id)
                    if case .error(.failedToOpenFile) = playbackState {
                        skipped.append(next.displayName)
                        nextIndex = (nextIndex + 1) % count
                        attempts += 1
                        continue
                    }
                    if !skipped.isEmpty {
                        alertCenter.skippedInaccessibleNames = skipped
                        alertCenter.showFileNotFoundAlert = true
                    }
                    return
                } else {
                    skipped.append(next.displayName)
                }
                nextIndex = (nextIndex + 1) % count
                attempts += 1
            }
            // All tracks inaccessible — show popup and stop.
            if !skipped.isEmpty {
                alertCenter.skippedInaccessibleNames = skipped
                alertCenter.showFileNotFoundAlert = true
            }
            await stop()
            currentTrack = nil
        case .one:
            guard let current = context.playlists[playingIndex].tracks.first(where: { $0.id == lastID })
            else { return }
            if !current.isAccessible {
                alertCenter.failedTrackName = current.displayName
                alertCenter.showFileNotFoundAlert = true
                await stop()
                currentTrack = nil
            } else {
                await play(trackID: lastID)
            }
        }
    }

    // MARK: - Shuffle queue

    /// Builds a shuffled queue of all accessible track IDs of the active
    /// playlist.
    ///
    /// If `startID` is provided, places it first so the currently playing
    /// track stays at the head of the new queue.
    func buildShuffleQueue(startingWith startID: Track.ID? = nil) {
        guard let context = playlistContext else { return }
        var ids = context.playlists[context.activePlaylistIndex].tracks
            .filter { $0.isAccessible }
            .map { $0.id }
        ids.shuffle()
        if let startID, let idx = ids.firstIndex(of: startID) {
            ids.remove(at: idx)
            ids.insert(startID, at: 0)
        }
        shuffleQueue = ids
        shuffleQueueIndex = 0
    }
}
