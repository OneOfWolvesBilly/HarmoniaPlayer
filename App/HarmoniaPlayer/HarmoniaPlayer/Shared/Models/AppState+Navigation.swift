//
//  AppState+Navigation.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE: Track navigation (next/previous/auto-advance on track completion)
//  and Mini Player playlist switching.
//

import Foundation

extension AppState {

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
        guard !playlists[activePlaylistIndex].tracks.isEmpty else { return }

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
              let currentIndex = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == current.id })
        else {
            await play(trackID: playlists[activePlaylistIndex].tracks[0].id)
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < playlists[activePlaylistIndex].tracks.count {
            await play(trackID: playlists[activePlaylistIndex].tracks[nextIndex].id)
        } else {
            // At last track — always wrap to first regardless of repeatMode.
            // Natural completion (trackDidFinishPlaying) respects repeatMode;
            // manual Next button always wraps for better user experience.
            await play(trackID: playlists[activePlaylistIndex].tracks[0].id)
        }
    }

    /// Plays the previous track in the playlist.
    ///
    /// If `currentTrack` is the first track, seeks to the beginning
    /// and replays it instead of wrapping around.
    ///
    /// No-op if playlist is empty.
    func playPreviousTrack() async {
        guard !playlists[activePlaylistIndex].tracks.isEmpty else { return }

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
              let currentIndex = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == current.id })
        else {
            await play(trackID: playlists[activePlaylistIndex].tracks[0].id)
            return
        }

        if currentIndex > 0 {
            await play(trackID: playlists[activePlaylistIndex].tracks[currentIndex - 1].id)
        } else {
            do {
                try await playbackService.seek(to: 0)
                currentTime = 0
            } catch {
                lastError = mapToPlaybackError(error)
            }
            await play(trackID: current.id)
        }
    }

    /// Called by the View layer when natural playback completion is detected.
    ///
    /// Dispatches based on `repeatMode`:
    /// - `.off`: `playNextTrack()` (stop if at last).
    /// - `.all`: `playNextTrack()` (loop if at last).
    /// - `.one`: `play(trackID:)` for `currentTrack`.
    ///
    /// No-op if `currentTrack` is `nil`.
    func trackDidFinishPlaying() async {
        guard let lastID = lastPlayedTrackID else { return }
        switch repeatMode {
        case .off:
            if isShuffled {
                // Shuffle mode: advance through queue skipping inaccessible tracks
                // and format-gated tracks (when paywallDismissedThisSession is true).
                var skipped: [String] = []
                var nextIndex = shuffleQueueIndex + 1
                while nextIndex < shuffleQueue.count {
                    guard let trackID = shuffleQueue[safe: nextIndex],
                          let next = playlists[activePlaylistIndex].tracks.first(where: { $0.id == trackID })
                    else { nextIndex += 1; continue }

                    // v0.1 frozen: format gate disabled — Pro formats cannot enter playlist.
                    // Silently skip format-gated tracks if user dismissed paywall this session.
                    // let nextExt = next.url.pathExtension.lowercased()
                    // let isFormatGated = Self.proOnlyFormats.contains(nextExt) && !featureFlags.supportsFLAC
                    // if isFormatGated && paywallDismissedThisSession {
                    //     nextIndex += 1
                    //     continue
                    // }

                    if next.isAccessible {
                        shuffleQueueIndex = nextIndex
                        await play(trackID: next.id)
                        if case .error(.failedToOpenFile) = playbackState {
                            skipped.append(displayName(for: next))
                            nextIndex += 1
                            continue
                        }
                        if !skipped.isEmpty {
                            skippedInaccessibleNames = skipped
                            showFileNotFoundAlert = true
                        }
                        return
                    } else {
                        skipped.append(displayName(for: next))
                    }
                    nextIndex += 1
                }
                // Queue exhausted — show popup and stop.
                if !skipped.isEmpty {
                    skippedInaccessibleNames = skipped
                    showFileNotFoundAlert = true
                }
                await stop()
                currentTrack = nil
                shuffleQueue = []
                shuffleQueueIndex = 0
            } else {
                // Normal mode: skip inaccessible tracks and format-gated tracks
                // (when paywallDismissedThisSession is true).
                guard let currentIndex = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == lastID })
                else { return }
                var skipped: [String] = []
                var nextIndex = currentIndex + 1
                while nextIndex < playlists[activePlaylistIndex].tracks.count {
                    let next = playlists[activePlaylistIndex].tracks[nextIndex]

                    // v0.1 frozen: format gate disabled — Pro formats cannot enter playlist.
                    // Silently skip format-gated tracks if user dismissed paywall this session.
                    // let nextExt = next.url.pathExtension.lowercased()
                    // let isFormatGated = Self.proOnlyFormats.contains(nextExt) && !featureFlags.supportsFLAC
                    // if isFormatGated && paywallDismissedThisSession {
                    //     nextIndex += 1
                    //     continue
                    // }

                    if next.isAccessible {
                        await play(trackID: next.id)
                        if case .error(.failedToOpenFile) = playbackState {
                            skipped.append(displayName(for: next))
                            nextIndex += 1
                            continue
                        }
                        if !skipped.isEmpty {
                            skippedInaccessibleNames = skipped
                            showFileNotFoundAlert = true
                        }
                        return
                    } else {
                        skipped.append(displayName(for: next))
                    }
                    nextIndex += 1
                }
                // No more playable tracks — show popup and stop.
                if !skipped.isEmpty {
                    skippedInaccessibleNames = skipped
                    showFileNotFoundAlert = true
                }
                await stop()
                currentTrack = nil
            }
        case .all:
            // Wrap around skipping inaccessible tracks and format-gated tracks
            // (when paywallDismissedThisSession is true).
            guard let currentIndex = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == lastID })
            else { return }
            let count = playlists[activePlaylistIndex].tracks.count
            var nextIndex = (currentIndex + 1) % count
            var attempts = 0
            var skipped: [String] = []
            while attempts < count {
                let next = playlists[activePlaylistIndex].tracks[nextIndex]

                // v0.1 frozen: format gate disabled — Pro formats cannot enter playlist.
                // Silently skip format-gated tracks if user dismissed paywall this session.
                // let nextExt = next.url.pathExtension.lowercased()
                // let isFormatGated = Self.proOnlyFormats.contains(nextExt) && !featureFlags.supportsFLAC
                // if isFormatGated && paywallDismissedThisSession {
                //     nextIndex = (nextIndex + 1) % count
                //     attempts += 1
                //     continue
                // }

                if next.isAccessible {
                    await play(trackID: next.id)
                    if case .error(.failedToOpenFile) = playbackState {
                        skipped.append(displayName(for: next))
                        nextIndex = (nextIndex + 1) % count
                        attempts += 1
                        continue
                    }
                    if !skipped.isEmpty {
                        skippedInaccessibleNames = skipped
                        showFileNotFoundAlert = true
                    }
                    return
                } else {
                    skipped.append(displayName(for: next))
                }
                nextIndex = (nextIndex + 1) % count
                attempts += 1
            }
            // All tracks inaccessible — show popup and stop.
            if !skipped.isEmpty {
                skippedInaccessibleNames = skipped
                showFileNotFoundAlert = true
            }
            await stop()
            currentTrack = nil
        case .one:
            guard let current = playlists[activePlaylistIndex].tracks.first(where: { $0.id == lastID })
            else { return }
            if !current.isAccessible {
                failedTrackName = displayName(for: current)
                showFileNotFoundAlert = true
                await stop()
                currentTrack = nil
            } else {
                await play(trackID: lastID)
            }
        }
    }

    // MARK: - Mini Player

    /// Switches the active playlist from Mini Player and starts playing from the first track.
    ///
    /// Called by MiniPlayerView when the user selects a different playlist.
    /// Stops current playback, switches activePlaylistIndex, then plays the
    /// first track in the new playlist. No-op if index is out of range.
    ///
    /// - Parameter index: Index of the playlist to switch to.
    func switchMiniPlayerPlaylist(to index: Int) async {
        guard playlists.indices.contains(index) else { return }
        await stop()
        activePlaylistIndex = index
        // Clear undo stack: switched playlist context.
        undoManager.removeAllActions()
        if let first = playlists[index].tracks.first {
            await play(trackID: first.id)
        }
    }
}
