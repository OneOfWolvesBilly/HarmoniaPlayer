//
//  PlaybackController.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Combine
import Foundation

// MARK: - Persistence Keys

private enum PersistenceKey {
    static let volume     = "hp.volume"
    static let repeatMode = "hp.repeatMode"
    static let isShuffled = "hp.isShuffled"
}

/// Store owning the playback surface: transport state, the playback
/// service, repeat / shuffle modes and the shuffle queue, the volume, and
/// the playback persistence keys.
///
/// Extracted from `AppState`, which keeps same-named facade forwarders
/// only for the members its playlist code still reads. Views whose body
/// reads playback state observe this store directly via
/// `@Environment(PlaybackController.self)`, so a `currentTime` tick
/// re-renders only the views that read it.
///
/// Dependencies are written to directly: error paths write the alert
/// store's playback-error surface, and ReplayGain reads the settings
/// store's mode. Playlist state is reached through `playlistContext`.
/// Upward effects — a current-track change, a completed seek — go through
/// closures wired by the composition root; the store holds no reference to
/// the lyrics store or the Now Playing coordinator.
///
/// **Persistence.** `repeatMode` and `isShuffled` write their keys on
/// change. `volume` is written only by `saveVolume()`, which the
/// composition root calls at terminate. `init` restores all three keys
/// before its stored properties without defaults are initialised, so the
/// restore assignments go through the `@Observable` init accessors and run
/// neither `didSet` nor the closures.
@MainActor @Observable
final class PlaybackController {

    // MARK: - Transport state

    /// Currently selected track.
    ///
    /// `nil` when no track is selected, or after the selected track is
    /// removed from the playlist or the playlist is cleared. Set via
    /// `play(trackID:)`. Every assignment feeds the Now Playing publisher
    /// and `onCurrentTrackChanged`.
    var currentTrack: Track? {
        didSet {
            currentTrackSubject.send(currentTrack)
            onCurrentTrackChanged?(currentTrack)
        }
    }

    /// Current playback state.
    ///
    /// Initialised to `.idle`. Updated by the transport methods and the
    /// polling loop. Every assignment feeds the Now Playing publisher.
    var playbackState: PlaybackState = .idle {
        didSet { playbackStateSubject.send(playbackState) }
    }

    /// ID of the playlist that contains the currently playing track.
    ///
    /// Set to the owning playlist's id when `play(trackID:)` succeeds.
    /// Cleared to `nil` by `stop()` and when the last track finishes
    /// naturally. Uses `Playlist.ID` (UUID) so it remains valid after tab
    /// reordering.
    var playingPlaylistID: Playlist.ID?

    /// Current playback position in seconds.
    ///
    /// Initialised to `0`. Updated by the polling loop and on successful
    /// `seek(to:)`; reset to `0` by `stop()`.
    var currentTime: TimeInterval = 0

    /// Duration of the currently loaded track in seconds.
    ///
    /// Initialised to `0`. Updated after a successful `load` in `play(trackID:)`.
    var duration: TimeInterval = 0

    // MARK: - Persisted playback settings

    /// Current output volume in the range 0.0 (silent) to 1.0 (full).
    ///
    /// Default: `1.0`. Updated by `setVolume(_:)`; written to
    /// `UserDefaults` by `saveVolume()`.
    var volume: Float = 1.0

    /// Current repeat mode.
    ///
    /// Defaults to `.off`. Updated by `cycleRepeatMode()`; persisted on
    /// change. Controls `playNextTrack()` and `trackDidFinishPlaying()`.
    var repeatMode: RepeatMode = .off {
        didSet {
            if let data = try? JSONEncoder().encode(repeatMode) {
                userDefaults.set(data, forKey: PersistenceKey.repeatMode)
            }
        }
    }

    /// Whether shuffle mode is enabled. See `ShuffleMode` for semantics.
    /// Persisted on change.
    var isShuffled: ShuffleMode = .off {
        didSet { userDefaults.set(isShuffled, forKey: PersistenceKey.isShuffled) }
    }

    // MARK: - Shuffle queue

    /// Pre-shuffled track ID order used when shuffle is enabled.
    ///
    /// Contains a permutation of the accessible track IDs of the active
    /// playlist. Rebuilt whenever shuffle is toggled on or the playlist
    /// changes. `shuffleQueueIndex` points to the current position.
    var shuffleQueue: [Track.ID] = []
    var shuffleQueueIndex: Int = 0

    // MARK: - Non-observed state

    /// Position the user has seeked to while stopped or paused.
    /// Used by `play()` to resume from the correct position.
    @ObservationIgnored var pendingSeekTime: TimeInterval = 0

    /// The ID of the last successfully played track.
    ///
    /// Set after `playbackService.play()` succeeds in `play(trackID:)`.
    /// Used by `trackDidFinishPlaying()` to find the current position in
    /// the playlist when `currentTrack` has been cleared.
    @ObservationIgnored var lastPlayedTrackID: Track.ID?

    /// Task that polls playback state and `currentTime` while playing.
    @ObservationIgnored var pollingTask: Task<Void, Never>?

    /// Whether playback was active at the moment the system began sleeping.
    ///
    /// Recorded by `handleSystemWillSleep()` and consumed (then cleared) by
    /// `handleSystemDidWake()`. Captured at the will-sleep notification
    /// rather than inferred from the polling loop, because the ordering of
    /// the did-wake notification against a polling tick is undefined.
    @ObservationIgnored private(set) var wasPlayingBeforeSleep = false

    // MARK: - Dependencies

    /// Playback service. Also read by the composition root's forwarder.
    let playbackService: PlaybackService

    /// Alert store the error paths write to; module-internal so the
    /// navigation extension in its own file can reach it.
    let alertCenter: AlertCenter
    private let settingsStore: SettingsStore
    private let userDefaults: UserDefaults

    /// Playlist state the controller resolves tracks in and switches the
    /// active playlist of. Assigned by the composition root once it is
    /// fully initialised (the root is itself the context, so it cannot be
    /// an init argument). Context-dependent methods are no-ops while `nil`.
    @ObservationIgnored weak var playlistContext: (any PlaylistContext)?

    // MARK: - Root-wired notifications

    /// Called from `currentTrack`'s `didSet` on every assignment.
    @ObservationIgnored var onCurrentTrackChanged: ((Track?) -> Void)?

    /// Called after a successful `seek(to:)` with the target position, so
    /// the system Now Playing widget can re-anchor its scrubber.
    @ObservationIgnored var onSeekCompleted: ((TimeInterval) -> Void)?

    // MARK: - Now Playing bridge

    @ObservationIgnored private let currentTrackSubject = CurrentValueSubject<Track?, Never>(nil)
    @ObservationIgnored private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)

    /// Emits `currentTrack` on every assignment (current value first).
    var currentTrackPublisher: AnyPublisher<Track?, Never> {
        currentTrackSubject.eraseToAnyPublisher()
    }

    /// Emits `playbackState` on every assignment (current value first).
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    /// Creates the controller and restores the three playback keys from
    /// `userDefaults`. A missing key keeps the default; undecodable repeat
    /// data keeps `.off`.
    init(
        playbackService: PlaybackService,
        alertCenter: AlertCenter,
        settingsStore: SettingsStore,
        userDefaults: UserDefaults
    ) {
        // Restore before the stored properties without defaults are set:
        // these assignments go through the init accessors and skip didSet.
        if userDefaults.object(forKey: PersistenceKey.volume) != nil {
            volume = userDefaults.float(forKey: PersistenceKey.volume)
        }
        if let repeatData = userDefaults.data(forKey: PersistenceKey.repeatMode),
           let decoded = try? JSONDecoder().decode(RepeatMode.self, from: repeatData) {
            repeatMode = decoded
        }
        if userDefaults.object(forKey: PersistenceKey.isShuffled) != nil {
            isShuffled = userDefaults.bool(forKey: PersistenceKey.isShuffled)
        }

        self.playbackService = playbackService
        self.alertCenter = alertCenter
        self.settingsStore = settingsStore
        self.userDefaults = userDefaults
    }

    // MARK: - Transport Controls

    /// Start playback of the currently loaded track.
    ///
    /// No-op if no track has been loaded via `play(trackID:)`.
    /// Resumes playback of the current track, or starts playback from the
    /// selected track (or first track) if nothing is loaded yet.
    ///
    /// When `currentTrack` is nil (e.g. after stop):
    /// 1. Active playlist has a selection → play the first selected track
    ///    (in playlist order).
    /// 2. No selection but playlist has tracks → play the first track.
    /// 3. Playlist empty → no-op.
    ///
    /// On error: sets `lastError` and `playbackState = .error(mapped)`.
    func play() async {
        guard let context = playlistContext else { return }

        // If no track is loaded, resolve from selection or first track.
        if currentTrack == nil {
            let tracks = context.playlists[context.activePlaylistIndex].tracks
            let selectedTrackIDs = context.selectedTrackIDs
            if !selectedTrackIDs.isEmpty,
               let selected = tracks.first(where: { selectedTrackIDs.contains($0.id) }) {
                await play(trackID: selected.id)
            } else if let first = tracks.first {
                await play(trackID: first.id)
            }
            return
        }

        // If playbackService is stopped (e.g. after stop() was called, or after
        // the last track finished naturally), reload and resume.
        if case .stopped = playbackService.state {
            // After natural completion of the last track with repeatMode == .off,
            // pressing Play restarts from the first track in the playlist.
            let activeTracks = context.playlists[context.activePlaylistIndex].tracks
            let isLastTrack: Bool = {
                guard let current = currentTrack,
                      let idx = activeTracks.firstIndex(where: { $0.id == current.id })
                else { return false }
                return idx == activeTracks.count - 1
            }()

            if isLastTrack && repeatMode == .off && pendingSeekTime <= 0.1 {
                if let first = activeTracks.first {
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
            alertCenter.lastError = mapped
            alertCenter.lastErrorDetail = makeErrorDetail(code: mapped, track: nil)
            playbackState = .error(mapped)
        }
    }

    /// Pause playback. Playback position is preserved.
    func pause() async {
        await playbackService.pause()
        playbackState = .paused
    }

    /// Stop playback. Resets `currentTime` to 0 and clears `currentTrack`.
    func stop() async {
        stopPolling()
        await playbackService.stop()
        playbackState = .stopped
        currentTrack = nil
        currentTime = 0
        pendingSeekTime = 0
        playingPlaylistID = nil
    }

    /// Seek to an absolute position in the current track.
    ///
    /// On success: updates `currentTime` and calls `onSeekCompleted` so the
    /// system Now Playing widget re-anchors its scrubber position (seek
    /// success is not derivable from `playbackStatePublisher`).
    /// On error: sets `lastError`. `playbackState` is not changed.
    ///
    /// - Parameter seconds: Target playback position in seconds.
    func seek(to seconds: TimeInterval) async {
        do {
            try await playbackService.seek(to: seconds)
            currentTime = seconds
            onSeekCompleted?(seconds)
        } catch {
            let mapped = mapToPlaybackError(error)
            alertCenter.lastError = mapped
            alertCenter.lastErrorDetail = makeErrorDetail(code: mapped, track: nil)
        }
    }

    /// Sets the output volume.
    ///
    /// Clamps `volume` to 0.0–1.0 before updating the property and
    /// forwarding to `PlaybackService`.
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
    /// 1. Resolve `trackID` across the context's playlists, switching the
    ///    active playlist to the owning one. Set `currentTrack`, or set it
    ///    to `nil` and return if not found.
    /// 2. **Accessibility gate:** an inaccessible track stops playback,
    ///    raises the file-not-found alert, and is marked inaccessible in
    ///    the context.
    /// 3. Set `playbackState = .loading`.
    /// 4. Call `playbackService.load(url:)` and update `duration`.
    /// 5. Call `playbackService.play()` and set `playbackState = .playing`.
    /// 6. On any error: map to `PlaybackError`, set `lastError` and `playbackState = .error`.
    ///
    /// - Parameter trackID: The `UUID` of the track to load and play.
    func play(trackID: Track.ID) async {
        guard let context = playlistContext else { return }

        // Step 1: Resolve track across all playlists.
        // Search activePlaylistIndex first, then other playlists.
        // If found in a different playlist, switch activePlaylistIndex to that playlist.
        var resolvedTrack: Track? = context.playlists[context.activePlaylistIndex].tracks.first(where: { $0.id == trackID })
        var resolvedPlaylistIndex = context.activePlaylistIndex

        if resolvedTrack == nil {
            for (i, playlist) in context.playlists.enumerated() where i != context.activePlaylistIndex {
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
        if resolvedPlaylistIndex != context.activePlaylistIndex {
            context.activePlaylistIndex = resolvedPlaylistIndex
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
            alertCenter.lastError = .failedToOpenFile
            alertCenter.lastErrorDetail = makeErrorDetail(code: .failedToOpenFile, track: track)
            alertCenter.failedTrackName = track.displayName
            alertCenter.showFileNotFoundAlert = true
            playbackState = .error(.failedToOpenFile)
            // Write back so PlaylistView re-renders with strikethrough.
            if let idx = context.playlists[context.activePlaylistIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                context.playlists[context.activePlaylistIndex].tracks[idx].isAccessible = false
            }
            return
        }

        // Pro format gate disabled: FLAC/DSF/DFF cannot enter the playlist,
        // so this code path is unreachable.
        // Step 2b: Format gate — reject Pro-only formats on the Free tier.
        // Post bringMainWindowToFront so MiniPlayerView closes itself and brings
        // the main window to front before the Paywall sheet appears.
        // let ext = track.url.pathExtension.lowercased()
        // if (ext == "flac" || ext == "dsf" || ext == "dff") && !settingsStore.featureFlags.supportsFLAC {
        //     NotificationCenter.default.post(name: .bringMainWindowToFront, object: nil)
        //     settingsStore.showPaywallIfNeeded()
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
            playingPlaylistID = context.playlists[context.activePlaylistIndex].id
            startPolling()
        } catch {
            let mapped = mapToPlaybackError(error)
            currentTrack = nil
            alertCenter.lastError = mapped
            alertCenter.lastErrorDetail = makeErrorDetail(code: mapped, track: track)
            playbackState = .error(mapped)
            if mapped == .failedToOpenFile {
                alertCenter.failedTrackName = track.displayName
                alertCenter.showFileNotFoundAlert = true
                if let idx = context.playlists[context.activePlaylistIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                    context.playlists[context.activePlaylistIndex].tracks[idx].isAccessible = false
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

    // MARK: - Polling

    /// Starts a polling loop that updates `currentTime` and detects
    /// natural playback completion while `playbackState == .playing`.
    private func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                } catch {
                    break // CancellationError — exit loop cleanly
                }
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
                    // Reflect a service-side pause the app did not initiate
                    // (e.g. the audio output was invalidated during system
                    // sleep and the service retained the position).
                    if case .paused = serviceState, self.playbackState == .playing {
                        self.playbackState = .paused
                        self.stopPolling()
                    }
                    // Reflect a service-side error the app has not observed
                    // through a thrown call.
                    if case .error(let serviceError) = serviceState, self.playbackState == .playing {
                        self.playbackState = .error(serviceError)
                        self.alertCenter.lastError = serviceError
                        self.stopPolling()
                    }
                }
                // Only break out of polling when truly stopped (not buffering/draining).
                if case .stopped = serviceState { break }
            }
        }
    }

    /// Cancels the polling loop.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - ReplayGain

    /// Calculates and applies the effective playback volume for the current track.
    ///
    /// Called in two places:
    /// 1. `play(trackID:)` — once when a new track starts.
    /// 2. The `settingsStore.onReplayGainModeChanged` closure wired by the
    ///    composition root — whenever the user changes mode in Settings.
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
        // The mode-change closure passes nil and falls back to currentTrack instead.
        let track = explicitTrack ?? currentTrack

        let gainDB: Double? = {
            switch settingsStore.replayGainMode {
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
    /// `CoreError` to `PlaybackError` before it reaches the controller, so
    /// this method acts as a passthrough. The fallback exists only as a
    /// safety net for unexpected non-`PlaybackError` errors.
    func mapToPlaybackError(_ error: Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError { return playbackError }
        return .invalidState
    }

    /// Builds a one-line diagnostic summary for `lastErrorDetail`.
    ///
    /// Format: `"<errorCode>: <track.url.path>"` when a specific track is
    /// associated with the failure, or `"<errorCode>: (no active track)"`
    /// when the error site cannot identify which track was involved
    /// (e.g. `play()` catch, `seek()` catch).
    ///
    /// Used by Report Issue button to prefill the mailto body with enough
    /// context for developer triage without dragging in PII beyond the
    /// local file path.
    func makeErrorDetail(code: PlaybackError, track: Track?) -> String {
        let suffix = track.map { $0.url.path } ?? "(no active track)"
        return "\(code): \(suffix)"
    }

    /// Returns playback from `.error` to `.stopped`; no-op in any other
    /// state. Called through the alert store's `onErrorCleared` closure
    /// when the user dismisses an error alert.
    func recoverFromError() {
        if case .error = playbackState {
            playbackState = .stopped
        }
    }

    // MARK: - Sleep / Wake

    /// Records whether playback is active at the moment the system sleeps.
    ///
    /// Called by `AppDelegate` when `NSWorkspace.willSleepNotification`
    /// fires.
    func handleSystemWillSleep() {
        wasPlayingBeforeSleep = (playbackState == .playing)
    }

    /// Resumes playback after the system wakes if it was playing before
    /// sleep.
    ///
    /// Called by `AppDelegate` when `NSWorkspace.didWakeNotification`
    /// fires. Clears `wasPlayingBeforeSleep` in all cases; when it was
    /// `true`, calls `play()` — re-preparation of the audio pipeline
    /// happens inside the playback service, so no further call is needed.
    func handleSystemDidWake() async {
        let shouldResume = wasPlayingBeforeSleep
        wasPlayingBeforeSleep = false
        if shouldResume {
            await play()
        }
    }

    // MARK: - Persistence

    /// Writes `hp.volume`. Called by the composition root when
    /// `NSApplication.willTerminateNotification` fires; `repeatMode` and
    /// `isShuffled` are already persisted at change time.
    func saveVolume() {
        userDefaults.set(volume, forKey: PersistenceKey.volume)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}
}
