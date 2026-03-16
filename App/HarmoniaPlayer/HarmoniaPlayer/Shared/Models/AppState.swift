//
//  AppState.swift
//  HarmoniaPlayer / Shared / Models
//
//  Created on 2026-02-15.
//

import Foundation
import Combine

/// Central application state container.
///
/// Wires all dependencies (IAP → FeatureFlags → CoreFactory → Services)
/// and exposes published state for SwiftUI views to observe.
/// All services are created through CoreFactory via dependency injection.
///
/// **Usage:**
/// ```swift
/// let appState = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider())
///
/// // In SwiftUI
/// ContentView()
///     .environmentObject(appState)
/// ```
@MainActor
final class AppState: ObservableObject {

    // MARK: - Dependencies

    /// IAP manager (determines Free/Pro)
    private let iapManager: IAPManager

    /// Feature flags (derived from IAP).
    /// Exposes tier-specific capabilities used by format gating and UI.
    let featureFlags: CoreFeatureFlags

    // MARK: - Services

    /// Playback service
    let playbackService: PlaybackService

    /// Tag reader service
    let tagReaderService: TagReaderService

    // MARK: - Published State

    /// Whether Pro features are unlocked.
    ///
    /// Derived from feature flags. UI can observe this for Pro gating.
    @Published private(set) var isProUnlocked: Bool

    // MARK: - Playlist State

    /// Session playlist.
    ///
    /// Initialised as an empty playlist named "Session".
    /// Operations: `load(urls:)`, `clearPlaylist()`, `removeTrack(_:)`, `moveTrack(fromOffsets:toOffset:)`.
    @Published private(set) var playlist: Playlist

    /// Currently selected track.
    ///
    /// `nil` when no track is selected, or after the selected track
    /// is removed from the playlist or the playlist is cleared.
    /// Set via `play(trackID:)`. Does not trigger audio playback.
    @Published private(set) var currentTrack: Track?

    // MARK: - UI Preference State

    /// UI layout and visibility preferences.
    ///
    /// Initialised to `.defaultPreferences` at app launch.
    /// Mutable so views and actions can update it directly:
    /// ```swift
    /// appState.viewPreferences.layoutPreset = .compact
    /// ```
    @Published var viewPreferences: ViewPreferences = .defaultPreferences

    // MARK: - Playback State

    /// Current playback state.
    ///
    /// Initialised to `.idle`. Updated by playback control methods
    /// (`play()`, `pause()`, `stop()`, `play(trackID:)`).
    @Published private(set) var playbackState: PlaybackState = .idle

    /// Current playback position in seconds.
    ///
    /// Initialised to `0`. Updated on successful `seek(to:)` and
    /// reset to `0` by `stop()`.
    @Published private(set) var currentTime: TimeInterval = 0

    /// Duration of the currently loaded track in seconds.
    ///
    /// Initialised to `0`. Updated after a successful `load` in `play(trackID:)`.
    @Published private(set) var duration: TimeInterval = 0

    // MARK: - Error State

    /// Most recent playback error.
    ///
    /// `nil` on init. Set by playback logic when an error occurs.
    /// Views observe this to present error banners or alerts.
    @Published private(set) var lastError: PlaybackError?

    // MARK: - Repeat Mode State

    /// Current repeat mode.
    ///
    /// Defaults to `.off` on launch. Updated by `cycleRepeatMode()`.
    /// Controls behaviour of `playNextTrack()` and `trackDidFinishPlaying()`.
    @Published private(set) var repeatMode: RepeatMode = .off

    // MARK: - Initialization

    /// Creates AppState and wires all dependencies.
    ///
    /// - Parameters:
    ///   - iapManager: IAP manager
    ///   - provider: Service provider
    ///
    /// **Wiring flow:**
    /// ```
    /// IAPManager
    ///     ↓
    /// CoreFeatureFlags (derived)
    ///     ↓
    /// CoreFactory (with flags)
    ///     ↓
    /// Services (created via factory)
    /// ```
    init(
        iapManager: IAPManager,
        provider: CoreServiceProviding
    ) {
        // Step 1: Store IAP manager
        self.iapManager = iapManager

        // Step 2: Derive feature flags from IAP
        self.featureFlags = CoreFeatureFlags(iapManager: iapManager)

        // Step 3: Create factory with flags
        let coreFactory = CoreFactory(
            featureFlags: featureFlags,
            provider: provider
        )

        // Step 4: Create services via factory
        self.playbackService = coreFactory.makePlaybackService()
        self.tagReaderService = coreFactory.makeTagReaderService()

        // Step 5: Expose Pro unlock state
        self.isProUnlocked = iapManager.isProUnlocked

        // Step 6: Initialise playlist state
        self.playlist = Playlist(name: "Session")
        self.currentTrack = nil

        // Note: viewPreferences and lastError use property-level defaults;
        // no explicit assignment needed in init.
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}

    // MARK: - Playlist Operations

    /// Appends enriched tracks to the playlist by reading metadata for each URL.
    ///
    /// Calls `TagReaderService.readMetadata(for:)` per URL and appends the
    /// returned `Track` (title, artist, album, duration) in order.
    /// On failure, falls back to a URL-derived `Track` and sets `lastError`
    /// to `.failedToOpenFile`.
    ///
    /// - Parameter urls: Audio file URLs to add.
    func load(urls: [URL]) async {
        for url in urls {
            do {
                let track = try await tagReaderService.readMetadata(for: url)
                playlist.tracks.append(track)
            } catch {
                playlist.tracks.append(Track(url: url))
                lastError = .failedToOpenFile
            }
        }
    }

    /// Resets the playlist to empty and clears `currentTrack`.
    func clearPlaylist() {
        playlist.tracks = []
        currentTrack = nil
    }

    /// Removes the track with the given ID from the playlist.
    ///
    /// No-op if `trackID` is not found. Sets `currentTrack` to `nil`
    /// if the removed track was selected.
    ///
    /// - Parameter trackID: The `UUID` of the track to remove.
    func removeTrack(_ trackID: Track.ID) {
        if currentTrack?.id == trackID {
            currentTrack = nil
        }
        playlist.tracks.removeAll { $0.id == trackID }
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
        let itemsToMove = fromOffsets.map { playlist.tracks[$0] }
        var result = playlist.tracks.enumerated()
            .filter { !fromOffsets.contains($0.offset) }
            .map { $0.element }
        let adjustedOffset = toOffset - fromOffsets.filter { $0 < toOffset }.count
        result.insert(contentsOf: itemsToMove, at: min(adjustedOffset, result.count))
        playlist.tracks = result
    }

    // MARK: - Transport Controls

    /// Start playback of the currently loaded track.
    ///
    /// No-op if no track has been loaded via `play(trackID:)`.
    /// On error: sets `lastError` and `playbackState = .error(mapped)`.
    func play() async {
        do {
            try await playbackService.play()
            playbackState = .playing
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
        await playbackService.stop()
        playbackState = .stopped
        currentTime = 0
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
        // Step 1: Resolve track in playlist. Nil currentTrack and bail if not found.
        guard let track = playlist.tracks.first(where: { $0.id == trackID }) else {
            currentTrack = nil
            return
        }
        currentTrack = track

        // Step 2: Format gate — reject Pro-only formats on the Free tier.
        // The gate fires BEFORE playbackState is changed and BEFORE any service call.
        let ext = track.url.pathExtension.lowercased()
        if (ext == "flac" || ext == "dsf" || ext == "dff") && !featureFlags.supportsFLAC {
            lastError = .unsupportedFormat
            playbackState = .error(.unsupportedFormat)
            return  // playbackService.load is never called for gated formats.
        }

        // Step 3–6: Standard load-and-play flow.
        playbackState = .loading

        do {
            try await playbackService.load(url: track.url)
            duration = await playbackService.duration()
            try await playbackService.play()
            playbackState = .playing
        } catch {
            let mapped = mapToPlaybackError(error)
            lastError = mapped
            playbackState = .error(mapped)
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
        guard !playlist.tracks.isEmpty else { return }

        if repeatMode == .one, let current = currentTrack {
            await play(trackID: current.id)
            return
        }

        guard let current = currentTrack,
              let currentIndex = playlist.tracks.firstIndex(where: { $0.id == current.id })
        else {
            await play(trackID: playlist.tracks[0].id)
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < playlist.tracks.count {
            await play(trackID: playlist.tracks[nextIndex].id)
        } else if repeatMode == .all {
            await play(trackID: playlist.tracks[0].id)
        } else {
            await stop()
        }
    }

    /// Plays the previous track in the playlist.
    ///
    /// If `currentTrack` is the first track, seeks to the beginning
    /// and replays it instead of wrapping around.
    ///
    /// No-op if playlist is empty.
    func playPreviousTrack() async {
        guard !playlist.tracks.isEmpty else { return }

        guard let current = currentTrack,
              let currentIndex = playlist.tracks.firstIndex(where: { $0.id == current.id })
        else {
            await play(trackID: playlist.tracks[0].id)
            return
        }

        if currentIndex > 0 {
            await play(trackID: playlist.tracks[currentIndex - 1].id)
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
        guard let current = currentTrack else { return }
        switch repeatMode {
        case .off, .all:
            await playNextTrack()
        case .one:
            await play(trackID: current.id)
        }
    }

    // MARK: - Private Helpers

    /// Maps any thrown error to a `PlaybackError` for UI consumption.
    ///
    /// If the error is already a `PlaybackError`, it is returned as-is.
    /// Otherwise, the error's localized description is wrapped in `.coreError`.
    private func mapToPlaybackError(_ error: Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError { return playbackError }
        return .coreError(error.localizedDescription)
    }
}
