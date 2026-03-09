//
//  AppState.swift
//  HarmoniaPlayer
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

    /// Feature flags (derived from IAP)
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

    // MARK: - Playback State (Slice 4-A)

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

    // WORKAROUND: Xcode 26 beta - swift::TaskLocal::StopLookupScope bug
    // Remove when Xcode 26 stable is released
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
    /// Sets `currentTrack`, calls `playbackService.load(url:)`, updates `duration`,
    /// then calls `playbackService.play()`. Transitions `playbackState` through
    /// `.loading` → `.playing` on success, or `.error` on failure.
    ///
    /// No service calls are made if `trackID` is not found in the playlist.
    ///
    /// - Parameter trackID: The `UUID` of the track to load and play.
    func play(trackID: Track.ID) async {
        guard let track = playlist.tracks.first(where: { $0.id == trackID }) else {
            currentTrack = nil
            return
        }
        currentTrack = track
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

    // MARK: - Private Helpers

    private func mapToPlaybackError(_ error: Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError { return playbackError }
        return .coreError(error.localizedDescription)
    }
}
