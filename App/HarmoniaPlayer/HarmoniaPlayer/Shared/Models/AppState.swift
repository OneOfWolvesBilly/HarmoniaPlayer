//
//  AppState.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation
import Combine

/// Application state container (composition root)
///
/// **Responsibilities:**
/// - Wire all dependencies (IAP → Flags → Factory → Services)
/// - Expose minimal published state for UI
/// - **No behavior** - wiring only
/// - Playlist state and operations
/// - Track selection
///
/// **Design:**
/// - Single source of truth for app-wide state
/// - Uses dependency injection via initializer
/// - All services created through CoreFactory
///
/// **Usage:**
/// ```swift
/// let iapManager = MockIAPManager(isProUnlocked: false)
/// let appState = AppState(iapManager: iapManager, provider: FakeCoreProvider())
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

    /// Whether Pro features are unlocked
    ///
    /// Derived from feature flags. UI can observe this for Pro gating.
    @Published private(set) var isProUnlocked: Bool

    // MARK: - Playlist State

    /// Session playlist
    ///
    /// Initialised as an empty playlist named "Session".
    /// Operations: `load(urls:)`, `clearPlaylist()`, `removeTrack(_:)`, `moveTrack(fromOffsets:toOffset:)`.
    @Published private(set) var playlist: Playlist

    /// Currently selected track
    ///
    /// `nil` when no track is selected, or after the selected track
    /// is removed from the playlist or the playlist is cleared.
    ///
    /// Set via `play(trackID:)`. Does **not** trigger audio playback.
    @Published private(set) var currentTrack: Track?

    // MARK: - Initialization

    /// Initialize AppState with dependencies
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
    }

    // WORKAROUND: Xcode 26 beta - swift::TaskLocal::StopLookupScope bug
    // Remove when Xcode 26 stable is released
    nonisolated deinit {}

    // MARK: - Playlist Operations

    /// Load audio files into the playlist
    ///
    /// Creates `Track` instances with URL-derived titles and appends them to
    /// the existing playlist. Additive: calling this multiple times accumulates
    /// tracks.
    ///
    /// - Parameter urls: Audio file URLs to add
    ///
    /// **Notes:**
    /// - Titles are derived from the filename (without extension).
    /// - No format validation or metadata extraction is performed here.
    func load(urls: [URL]) {
        let newTracks = urls.map { Track(url: $0) }
        playlist.tracks.append(contentsOf: newTracks)
    }

    /// Clear all tracks from the playlist
    ///
    /// Resets the playlist to an empty state and clears `currentTrack`.
    func clearPlaylist() {
        playlist.tracks = []
        currentTrack = nil
    }

    /// Remove a specific track by ID
    ///
    /// - Parameter trackID: The `UUID` of the track to remove
    ///
    /// **Behaviour:**
    /// - No-op if `trackID` is not found in the playlist.
    /// - Sets `currentTrack` to `nil` if the removed track was selected.
    func removeTrack(_ trackID: Track.ID) {
        if currentTrack?.id == trackID {
            currentTrack = nil
        }
        playlist.tracks.removeAll { $0.id == trackID }
    }

    /// Reorder tracks (for SwiftUI `List` drag-and-drop support)
    ///
    /// - Parameters:
    ///   - fromOffsets: Source indices
    ///   - toOffset: Destination offset
    ///
    /// **Note:** Implemented without SwiftUI import to maintain module boundary.
    /// The signature is compatible with SwiftUI's `onMove` callback.
    func moveTrack(fromOffsets: IndexSet, toOffset: Int) {
        let itemsToMove = fromOffsets.map { playlist.tracks[$0] }
        var result = playlist.tracks.enumerated()
            .filter { !fromOffsets.contains($0.offset) }
            .map { $0.element }
        let adjustedOffset = toOffset - fromOffsets.filter { $0 < toOffset }.count
        result.insert(contentsOf: itemsToMove, at: min(adjustedOffset, result.count))
        playlist.tracks = result
    }

    // MARK: - Track Selection

    /// Select a track by ID
    ///
    /// - Parameter trackID: The `UUID` of the track to select
    ///
    /// Sets `currentTrack` to the matching track, or `nil` if the ID is
    /// not found in the playlist.
    ///
    /// **Note:** Does **not** start audio playback.
    func play(trackID: Track.ID) {
        currentTrack = playlist.tracks.first { $0.id == trackID }
    }
}