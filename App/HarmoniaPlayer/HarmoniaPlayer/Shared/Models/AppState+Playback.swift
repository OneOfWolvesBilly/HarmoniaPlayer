//
//  AppState+Playback.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE: Transport controls (play/pause/stop/seek/volume), track selection
//  (play by trackID), repeat/shuffle mode, polling, ReplayGain volume
//  adjustment, and error mapping.
//

import Foundation

extension AppState {

    // MARK: - Transport Controls

    /// Start playback of the currently loaded track.
    ///
    /// No-op if no track has been loaded via `play(trackID:)`.
    /// Resumes playback of the current track, or plays the first track if
    /// nothing is loaded yet.
    ///
    /// On error: sets `lastError` and `playbackState = .error(mapped)`.
    func play() async {
        // If no track is loaded, play the first track in the playlist.
        if currentTrack == nil {
            if let first = playlists[activePlaylistIndex].tracks.first {
                await play(trackID: first.id)
            }
            return
        }

        // If playbackService is stopped (e.g. after stop() was called, or after
        // the last track finished naturally), reload and resume.
        if case .stopped = playbackService.state {
            // After natural completion of the last track with repeatMode == .off,
            // pressing Play restarts from the first track in the playlist.
            let isLastTrack: Bool = {
                guard let current = currentTrack,
                      let idx = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == current.id })
                else { return false }
                return idx == playlists[activePlaylistIndex].tracks.count - 1
            }()

            if isLastTrack && repeatMode == .off && pendingSeekTime <= 0.1 {
                if let first = playlists[activePlaylistIndex].tracks.first {
                    await play(trackID: first.id)
                }
                return
            }

            if let track = currentTrack {
                let targetTime = pendingSeekTime
                await play(trackID: track.id)
                if targetTime > 0.1 {
                    await seek(to: targetTime)
                }
            }
            return
        }

        do {
            try await playbackService.play()
            playbackState = .playing
            startPolling()
        } catch {
            let mapped = mapToPlaybackError(error)
            lastError = mapped
            playbackState = .error(mapped)
        }
    }

    /// Pause playback. Playback position is preserved.
    func pause() async {
        await playbackService.pause()
        playbackState = .paused
    }

    /// Stop playback. Resets `currentTime` to 0.
    func stop() async {
        stopPolling()
        await playbackService.stop()
        playbackState = .stopped
        currentTime = 0
        pendingSeekTime = 0
        playingPlaylistID = nil
    }

    /// Seek to an absolute position in the current track.
    ///
    /// On success: updates `currentTime`.
    /// On error: sets `lastError`. `playbackState` is not changed.
    ///
    /// - Parameter seconds: Target playback position in seconds.
    func seek(to seconds: TimeInterval) async {
        do {
            try await playbackService.seek(to: seconds)
            currentTime = seconds
        } catch {
            lastError = mapToPlaybackError(error)
        }
    }

    /// Sets the output volume.
    ///
    /// Clamps `volume` to 0.0–1.0 before updating the published property
    /// and forwarding to `PlaybackService`.
    ///
    /// - Parameter volume: Desired volume. Out-of-range values are silently clamped.
    func setVolume(_ volume: Float) async {
        let clamped = max(0.0, min(1.0, volume))
        self.volume = clamped
        await playbackService.setVolume(clamped)
    }

    // MARK: - Track Selection

    /// Loads and plays the track matching `trackID`.
    ///
    /// **Execution order:**
    /// 1. Resolve `trackID` in the playlist. Set `currentTrack`, or set it to `nil`
    ///    and return if not found.
    /// 2. **Format gate:** If the track's extension is `flac`, `dsf`, or
    ///    `dff` AND `featureFlags.supportsFLAC` is `false` (Free tier), set
    ///    `lastError = .unsupportedFormat`, `playbackState = .error(.unsupportedFormat)`,
    ///    and return. `playbackService.load` is never reached for gated formats.
    /// 3. Set `playbackState = .loading`.
    /// 4. Call `playbackService.load(url:)` and update `duration`.
    /// 5. Call `playbackService.play()` and set `playbackState = .playing`.
    /// 6. On any error: map to `PlaybackError`, set `lastError` and `playbackState = .error`.
    ///
    /// - Parameter trackID: The `UUID` of the track to load and play.
    func play(trackID: Track.ID) async {
        // Step 1: Resolve track across all playlists.
        // Search activePlaylistIndex first, then other playlists.
        // If found in a different playlist, switch activePlaylistIndex to that playlist.
        var resolvedTrack: Track? = playlists[activePlaylistIndex].tracks.first(where: { $0.id == trackID })
        var resolvedPlaylistIndex = activePlaylistIndex

        if resolvedTrack == nil {
            for (i, playlist) in playlists.enumerated() where i != activePlaylistIndex {
                if let found = playlist.tracks.first(where: { $0.id == trackID }) {
                    resolvedTrack = found
                    resolvedPlaylistIndex = i
                    break
                }
            }
        }

        guard let track = resolvedTrack else {
            currentTrack = nil
            return
        }

        // Switch to the playlist that owns this track.
        if resolvedPlaylistIndex != activePlaylistIndex {
            activePlaylistIndex = resolvedPlaylistIndex
        }

        // If shuffle is active, sync shuffleQueueIndex to the manually selected track
        // so Next/Previous continue from the correct position in the queue.
        if isShuffled {
            if let idx = shuffleQueue.firstIndex(of: trackID) {
                shuffleQueueIndex = idx
            } else {
                // Track not in queue (e.g. added after shuffle) — rebuild queue
                buildShuffleQueue(startingWith: trackID)
            }
        }

        // Step 2: Accessibility gate — reject inaccessible tracks BEFORE setting currentTrack
        // so PlayerView is never updated with a track that cannot be played.
        if !track.isAccessible {
            // Stop current playback so the playing track does not continue.
            stopPolling()
            await playbackService.stop()
            currentTrack = nil
            lastError = .failedToOpenFile
            failedTrackName = displayName(for: track)
            showFileNotFoundAlert = true
            playbackState = .error(.failedToOpenFile)
            // Write back so PlaylistView re-renders with strikethrough.
            if let idx = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                playlists[activePlaylistIndex].tracks[idx].isAccessible = false
            }
            return
        }

        // v0.1 frozen: Pro format gate disabled. FLAC/DSF/DFF cannot enter
        // the playlist, so this code path is unreachable. Re-enable in v0.2.
        // Step 2b: Format gate — reject Pro-only formats on the Free tier.
        // Post bringMainWindowToFront so MiniPlayerView closes itself and brings
        // the main window to front before the Paywall sheet appears.
        // let ext = track.url.pathExtension.lowercased()
        // if (ext == "flac" || ext == "dsf" || ext == "dff") && !featureFlags.supportsFLAC {
        //     NotificationCenter.default.post(name: .bringMainWindowToFront, object: nil)
        //     showPaywallIfNeeded()
        //     currentTrack = nil
        //     return
        // }

        // Step 3–6: Standard load-and-play flow.
        stopPolling()
        await playbackService.stop()
        playbackState = .loading

        do {
            try await playbackService.load(url: track.url)
            duration = await playbackService.duration()

            await applyReplayGainVolume(for: track)

            try await playbackService.play()
            currentTrack = track
            lastPlayedTrackID = track.id
            playbackState = .playing
            playingPlaylistID = playlists[activePlaylistIndex].id
            startPolling()
        } catch {
            let mapped = mapToPlaybackError(error)
            currentTrack = nil
            lastError = mapped
            playbackState = .error(mapped)
            if mapped == .failedToOpenFile {
                failedTrackName = displayName(for: track)
                showFileNotFoundAlert = true
                if let idx = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                    playlists[activePlaylistIndex].tracks[idx].isAccessible = false
                }
            }
        }
    }

    // MARK: - Repeat Mode Control

    /// Cycles repeat mode: off → all → one → off.
    ///
    /// Synchronous. Safe to call directly from SwiftUI button actions.
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// Toggles shuffle mode on or off.
    ///
    /// Synchronous. Safe to call directly from SwiftUI button actions.
    func toggleShuffle() {
        isShuffled = !isShuffled
        if isShuffled {
            buildShuffleQueue(startingWith: currentTrack?.id)
        } else {
            shuffleQueue = []
            shuffleQueueIndex = 0
        }
    }

    /// Builds a shuffled queue of all track IDs.
    ///
    /// If `startID` is provided, places it first so the currently playing
    /// track stays at the head of the new queue.
    func buildShuffleQueue(startingWith startID: Track.ID? = nil) {
        var ids = playlists[activePlaylistIndex].tracks
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

    // MARK: - Polling

    /// Starts a polling loop that updates `currentTime` and detects
    /// natural playback completion while `playbackState == .playing`.
    private func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                guard !Task.isCancelled else { break }
                let serviceState = self.playbackService.state
                let time = await self.playbackService.currentTime()
                await MainActor.run {
                    self.currentTime = time
                    // Detect natural completion: service stopped but we think we're playing.
                    // Ignore .buffering — that is the drain state used by DefaultPlaybackService
                    // during EOF drain; we must not trigger completion until .stopped.
                    if case .stopped = serviceState, self.playbackState == .playing {
                        self.playbackState = .stopped
                        Task { await self.trackDidFinishPlaying() }
                    }
                }
                // Only break out of polling when truly stopped (not buffering/draining).
                if case .stopped = serviceState { break }
            }
        }
    }

    /// Cancels the polling loop.
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - ReplayGain

    /// Calculates and applies the effective playback volume for the current track.
    ///
    /// Called in two places:
    /// 1. `play(trackID:)` — once when a new track starts.
    /// 2. The `$replayGainMode` Combine sink — whenever the user changes mode in Settings.
    ///
    /// Gain logic:
    /// - `.off`  → use `volume` unchanged
    /// - `.track` → `replayGainTrack` dB; fallback to `replayGainAlbum` if absent
    /// - `.album` → `replayGainAlbum` dB; fallback to `replayGainTrack` if absent
    /// - Both nil → use `volume` unchanged
    /// - Result is clamped to [0, 1].
    func applyReplayGainVolume(for explicitTrack: Track? = nil, requiresActivePlayback: Bool = false) async {
        if requiresActivePlayback {
            guard playbackState == .playing || playbackState == .paused else { return }
        }
        // explicitTrack is passed from play(trackID:) before currentTrack is set.
        // Combine sink passes nil and falls back to currentTrack instead.
        let track = explicitTrack ?? currentTrack

        let gainDB: Double? = {
            switch replayGainMode {
            case .off:   return nil
            case .track: return track?.replayGainTrack ?? track?.replayGainAlbum
            case .album: return track?.replayGainAlbum ?? track?.replayGainTrack
            }
        }()
        let effectiveVolume: Float = {
            guard let db = gainDB else { return volume }
            let linear = pow(10.0, db / 20.0)
            return Float(min(1.0, Double(volume) * linear))
        }()
        await playbackService.setVolume(effectiveVolume)
    }

    // MARK: - Error Mapping

    /// Maps any thrown error to a `PlaybackError` for UI consumption.
    ///
    /// In the normal flow, `HarmoniaPlaybackServiceAdapter` already converts
    /// `CoreError` to `PlaybackError` before it reaches AppState, so this
    /// method acts as a passthrough. The fallback exists only as a safety
    /// net for unexpected non-`PlaybackError` errors.
    func mapToPlaybackError(_ error: Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError { return playbackError }
        return .invalidState
    }
}
