//
//  AppState.swift
//  HarmoniaPlayer / Shared / Models
//
//  Created on 2026-02-15.
//

import Foundation
import Combine

private extension Array {
    /// Returns the element at `index` if it is within bounds, otherwise `nil`.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Persistence Keys

private enum PersistenceKey {
    static let playlists           = "hp.playlists"
    static let activePlaylistIndex = "hp.activePlaylistIndex"
    static let allowDuplicates     = "hp.allowDuplicateTracks"
    static let volume              = "hp.volume"
    static let selectedLanguage    = "hp.selectedLanguage"
    static let sortKey             = "hp.sortKey"
    static let sortAscending       = "hp.sortAscending"
    static let repeatMode          = "hp.repeatMode"
    static let isShuffled          = "hp.isShuffled"
}

/// Current version of the metadata reading logic.
///
/// Increment this value whenever new fields are added to `Track` that require
/// re-reading from disk. `AppState.refreshMetadataIfNeeded()` uses this to
/// detect tracks populated by older versions and re-reads them in the background.
///
/// Must match `HarmoniaTagReaderAdapter.metadataVersion`.
///
/// History:
/// - 0: legacy (Slices 1–6; no Groups A–E)
/// - 1: Groups A–D added (Slice 7-G)
private let currentMetadataVersion = 1

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

    /// UserDefaults store used for persistence.
    private let userDefaults: UserDefaults

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

    /// All playlists managed by the app.
    ///
    /// Initialised with one empty playlist named "Session".
    /// Use `newPlaylist(name:)`, `renamePlaylist(at:name:)`, `deletePlaylist(at:)` to manage.
    @Published private(set) var playlists: [Playlist]

    /// Index of the currently visible and active playlist.
    ///
    /// Setting this directly switches the playlist context without interrupting playback.
    /// Transport controls (Next/Previous) always operate on `playlists[activePlaylistIndex]`.
    @Published var activePlaylistIndex: Int = 0

    /// The currently active playlist.
    ///
    /// Computed shorthand for `playlists[activePlaylistIndex]`.
    /// Read-only from outside; all internal mutations go through
    /// `playlists[activePlaylistIndex].xxx` directly.
    var playlist: Playlist { playlists[activePlaylistIndex] }

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

    /// ID of the playlist that contains the currently playing track.
    ///
    /// Set to `playlists[activePlaylistIndex].id` when `play(trackID:)` succeeds.
    /// Cleared to `nil` by `stop()` and when the last track finishes naturally.
    /// Uses `Playlist.ID` (UUID) so it remains valid after tab reordering.
    @Published private(set) var playingPlaylistID: Playlist.ID?

    /// Current playback position in seconds.
    ///
    /// Initialised to `0`. Updated on successful `seek(to:)` and
    /// reset to `0` by `stop()`.
    @Published private(set) var currentTime: TimeInterval = 0

    /// Position the user has seeked to while stopped or paused.
    /// Used by play() to resume from the correct position.
    private var pendingSeekTime: TimeInterval = 0

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

    /// Display name of the track that triggered the most recent `failedToOpenFile` error.
    ///
    /// Set to "Title - Artist" when artist is available, otherwise the URL filename.
    /// Cleared when `clearLastError()` is called.
    @Published private(set) var failedTrackName: String?

    /// Controls the file-not-found alert presentation.
    ///
    /// Set to `true` by `setFileNotFoundError(for:)`.
    /// ContentView binds directly to this flag so the alert is not
    /// dependent on `onChange(of: lastError)` timing.
    @Published var showFileNotFoundAlert: Bool = false

    /// Names of tracks skipped during auto-play due to inaccessibility.
    ///
    /// Populated during `trackDidFinishPlaying()` skip logic.
    /// ContentView shows a single alert listing all skipped tracks.
    /// Cleared when the alert is dismissed.
    @Published var skippedInaccessibleNames: [String] = []

    /// URLs that were skipped during the last load() call because they
    /// already exist in the playlist. Non-empty triggers a duplicate alert.
    @Published var skippedDuplicateURLs: [URL] = []

    /// URLs that were skipped during the last importPlaylist(from:) call because
    /// the files were not found on disk. Non-empty triggers a warning alert.
    @Published var skippedImportURLs: [URL] = []

    // MARK: - File Info Panel

    /// Track currently shown in the File Info panel sheet.
    ///
    /// Set via `showFileInfo(trackID:)`; cleared automatically when the sheet
    /// is dismissed (the sheet binding sets this back to nil).
    /// Not `private(set)` so the sheet's `item` binding can dismiss it.
    @Published var fileInfoTrack: Track? = nil

    // MARK: - Settings

    /// Whether duplicate URLs are allowed in the playlist.
    ///
    /// Default: `false` — duplicates are skipped and reported via `skippedDuplicateURLs`.
    /// When `true`, the duplicate-URL check in `load(urls:)` is bypassed.
    ///
    /// Not `private(set)`: `SettingsView` binds directly via `$appState.allowDuplicateTracks`.
    @Published var allowDuplicateTracks: Bool = false

    // MARK: - Volume State

    /// Current output volume in the range 0.0 (silent) to 1.0 (full).
    ///
    /// Default: `1.0`. Updated by `setVolume(_:)`.
    /// Persisted across launches by Slice 7-E (persistence).
    @Published var volume: Float = 1.0

    // MARK: - Language State

    /// BCP-47 language tag for UI language override, or `"system"` to follow system locale.
    ///
    /// Default: `"system"`. Updated by `SettingsView` language picker.
    /// Persisted across launches via `UserDefaults`.
    /// Changing this value triggers an app restart; the new language takes effect
    /// after relaunch, keeping UI strings and system menus in sync.
    @Published var selectedLanguage: String = "system"

    /// The `Bundle` used for all `NSLocalizedString(bundle:)` calls.
    ///
    /// Fixed at launch from the persisted `hp.selectedLanguage` value so that
    /// UI strings and system menus (which also require a restart) change together.
    /// Not recomputed when `selectedLanguage` changes — the app must restart first.
    let languageBundle: Bundle

    // MARK: - Repeat Mode State

    /// Current repeat mode.
    ///
    /// Defaults to `.off` on launch. Updated by `cycleRepeatMode()`.
    /// Controls behaviour of `playNextTrack()` and `trackDidFinishPlaying()`.
    @Published private(set) var repeatMode: RepeatMode = .off

    /// Whether shuffle mode is enabled. See `ShuffleMode` for semantics.
    @Published private(set) var isShuffled: ShuffleMode = .off

    /// Pre-shuffled track ID order used when shuffle is enabled.
    ///
    /// Contains a permutation of all track IDs in `playlists[activePlaylistIndex].tracks`.
    /// Rebuilt whenever shuffle is toggled on or the playlist changes.
    /// `shuffleQueueIndex` points to the current position in this queue.
    private(set) var shuffleQueue: [Track.ID] = []
    private(set) var shuffleQueueIndex: Int = 0

    /// The ID of the last successfully played track.
    ///
    /// Set after `playbackService.play()` succeeds in `play(trackID:)`.
    /// Used by `trackDidFinishPlaying()` to find the current position in the playlist
    /// when `currentTrack` has been cleared (e.g. after a failed play attempt).
    private var lastPlayedTrackID: Track.ID?

    // MARK: - Polling

    /// Task that polls playback state and currentTime while playing.
    private var pollingTask: Task<Void, Never>?

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
        provider: CoreServiceProviding,
        userDefaults: UserDefaults = .standard
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
        self.playlists = [Playlist(name: "Playlist 1")]
        self.currentTrack = nil

        // Step 7: Store UserDefaults instance
        self.userDefaults = userDefaults

        // Step 8: Resolve languageBundle from persisted setting.
        // Fixed at launch so UI strings and system menus change together after restart.
        let persistedLang = userDefaults.string(forKey: "hp.selectedLanguage") ?? "en"
        if persistedLang != "system",
           let path = Bundle.main.path(forResource: persistedLang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.languageBundle = bundle
        } else {
            self.languageBundle = .main
        }

        // Step 9: Restore persisted state (overrides Step 6 defaults if data exists)
        restoreState()
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}

    // MARK: - Persistence

    /// Returns a human-readable display name for a track.
    ///
    /// Priority:
    /// 1. title + artist → "title - artist"
    /// 2. title only    → "title"
    /// 3. artist only   → "artist"
    /// 4. neither       → filename from originalPath (no extension)
    private func displayName(for track: Track) -> String {
        let hasTitle = !track.title.isEmpty
        let hasArtist = !track.artist.isEmpty
        switch (hasTitle, hasArtist) {
        case (true, true):   return "\(track.title) - \(track.artist)"
        case (true, false):  return track.title
        case (false, true):  return track.artist
        case (false, false): return URL(fileURLWithPath: track.originalPath)
                                 .deletingPathExtension().lastPathComponent
        }
    }

    /// Clears the last playback error. Called when the user dismisses an error alert.
    func clearLastError() {
        lastError = nil
        failedTrackName = nil
        showFileNotFoundAlert = false
        skippedInaccessibleNames = []
        if case .error = playbackState {
            playbackState = .stopped
        }
    }

    /// Presents the File Info panel for the track with the given ID.
    ///
    /// Sets `fileInfoTrack` to the matching track, which triggers the sheet
    /// in `ContentView`. If no matching track is found, the call is a no-op.
    func showFileInfo(trackID: Track.ID) {
        fileInfoTrack = playlist.tracks.first { $0.id == trackID }
    }

    /// Saves playlist, activePlaylistIndex, allowDuplicateTracks, and volume to UserDefaults.
    ///
    /// Called by the app entry point when `NSApplication.willTerminateNotification` fires.
    func saveState() {
        if let data = try? JSONEncoder().encode(playlists) {
            userDefaults.set(data, forKey: PersistenceKey.playlists)
        }
        userDefaults.set(activePlaylistIndex, forKey: PersistenceKey.activePlaylistIndex)
        userDefaults.set(allowDuplicateTracks, forKey: PersistenceKey.allowDuplicates)
        userDefaults.set(volume, forKey: PersistenceKey.volume)
        userDefaults.set(selectedLanguage, forKey: PersistenceKey.selectedLanguage)
        if let repeatData = try? JSONEncoder().encode(repeatMode) {
            userDefaults.set(repeatData, forKey: PersistenceKey.repeatMode)
        }
        userDefaults.set(isShuffled, forKey: PersistenceKey.isShuffled)
    }

    /// Restores previously saved state from UserDefaults.
    ///
    /// Called once in `init` after services are wired.
    /// When no persisted data exists, the default values set in `init` are preserved.
    func restoreState() {
        if let data = userDefaults.data(forKey: PersistenceKey.playlists) {
            do {
                let decoded = try JSONDecoder().decode([Playlist].self, from: data)
                if !decoded.isEmpty {
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
            } catch {
                // Decode failure is non-fatal; app starts with default empty playlist.
            }
        }
        if userDefaults.object(forKey: PersistenceKey.allowDuplicates) != nil {
            allowDuplicateTracks = userDefaults.bool(forKey: PersistenceKey.allowDuplicates)
        }
        if userDefaults.object(forKey: PersistenceKey.volume) != nil {
            volume = userDefaults.float(forKey: PersistenceKey.volume)
        }
        if let lang = userDefaults.string(forKey: PersistenceKey.selectedLanguage) {
            selectedLanguage = lang
        }
        if let repeatData = userDefaults.data(forKey: PersistenceKey.repeatMode),
           let decoded = try? JSONDecoder().decode(RepeatMode.self, from: repeatData) {
            repeatMode = decoded
        }
        if userDefaults.object(forKey: PersistenceKey.isShuffled) != nil {
            isShuffled = userDefaults.bool(forKey: PersistenceKey.isShuffled)
        }

        // Background metadata refresh: re-reads fields for tracks that were
        // saved by an older version of the metadata reading logic.
        Task { await refreshMetadataIfNeeded() }
    }

    /// Re-reads metadata for any track whose `metadataVersion` is lower than
    /// `currentMetadataVersion`.
    ///
    /// Runs in the background after `restoreState()`. Only tracks restored from
    /// older saves (version 0) are affected. New fields are written back and
    /// `saveState()` is called so the refresh only happens once per track.
    private func refreshMetadataIfNeeded() async {
        var didRefreshAny = false

        for i in playlists.indices {
            for j in playlists[i].tracks.indices {
                let track = playlists[i].tracks[j]

                guard track.isAccessible,
                      track.metadataVersion < currentMetadataVersion
                else { continue }

                guard let refreshed = try? await tagReaderService.readMetadata(for: track.url)
                else { continue }

                // Merge: update only new-field groups; preserve core fields
                // (title, artist, album, duration) from the stored version
                // so user-visible data is not unexpectedly replaced.
                playlists[i].tracks[j].albumArtist     = refreshed.albumArtist
                playlists[i].tracks[j].composer        = refreshed.composer
                playlists[i].tracks[j].genre           = refreshed.genre
                playlists[i].tracks[j].year            = refreshed.year
                playlists[i].tracks[j].trackNumber     = refreshed.trackNumber
                playlists[i].tracks[j].trackTotal      = refreshed.trackTotal
                playlists[i].tracks[j].discNumber      = refreshed.discNumber
                playlists[i].tracks[j].discTotal       = refreshed.discTotal
                playlists[i].tracks[j].bpm             = refreshed.bpm
                playlists[i].tracks[j].replayGainTrack = refreshed.replayGainTrack
                playlists[i].tracks[j].replayGainAlbum = refreshed.replayGainAlbum
                playlists[i].tracks[j].comment         = refreshed.comment
                playlists[i].tracks[j].bitrate         = refreshed.bitrate
                playlists[i].tracks[j].sampleRate      = refreshed.sampleRate
                playlists[i].tracks[j].channels        = refreshed.channels
                playlists[i].tracks[j].fileSize        = refreshed.fileSize
                playlists[i].tracks[j].fileFormat      = refreshed.fileFormat
                playlists[i].tracks[j].metadataVersion = currentMetadataVersion

                didRefreshAny = true
            }
        }

        if didRefreshAny { saveState() }
    }

    // MARK: - Playlist Operations

    /// Appends enriched tracks to the playlist by reading metadata for each URL.
    ///
    /// Calls `TagReaderService.readMetadata(for:)` per URL and appends the
    /// returned `Track` (title, artist, album, duration) in order.\
    /// On failure, falls back to a URL-derived `Track` and sets `lastError`
    /// to `.failedToOpenFile`.
    ///
    /// - Parameter urls: Audio file URLs to add.
    func load(urls: [URL]) async {
        // Reset skipped list before each load so the alert re-triggers
        // even if the same files are dropped again.
        skippedDuplicateURLs = []
        // Collect existing URLs to prevent duplicates within the same playlist.
        let existingURLs = Set(playlists[activePlaylistIndex].tracks.map { $0.url })
        var skipped: [URL] = []
        var addedIDs: [Track.ID] = []
        for url in urls {
            if !allowDuplicateTracks && existingURLs.contains(url) {
                skipped.append(url)
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

        saveState()
    }

    /// Resets the playlist to empty and clears `currentTrack`.
    func clearPlaylist() {
        playlists[activePlaylistIndex].tracks = []
        currentTrack = nil
        saveState()
    }

    // MARK: - Playlist Management

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
                    guard let removedIndex = playlists[activePlaylistIndex].insertionOrder.firstIndex(of: trackID)
                    else { return playlists[activePlaylistIndex].tracks.first?.id }

                    if removedIndex < playlists[activePlaylistIndex].tracks.count {
                        // There is a track at this index (the one that shifted up)
                        return playlists[activePlaylistIndex].tracks[removedIndex].id
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
        saveState()
    }

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

        // Step 2b: Format gate — reject Pro-only formats on the Free tier.
        let ext = track.url.pathExtension.lowercased()
        if (ext == "flac" || ext == "dsf" || ext == "dff") && !featureFlags.supportsFLAC {
            currentTrack = nil
            lastError = .unsupportedFormat
            playbackState = .error(.unsupportedFormat)
            return
        }

        // Step 3–6: Standard load-and-play flow.
        stopPolling()
        await playbackService.stop()
        playbackState = .loading

        do {
            try await playbackService.load(url: track.url)
            duration = await playbackService.duration()
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
    private func buildShuffleQueue(startingWith startID: Track.ID? = nil) {
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
                // Shuffle mode: advance through queue skipping inaccessible tracks.
                var skipped: [String] = []
                var nextIndex = shuffleQueueIndex + 1
                while nextIndex < shuffleQueue.count {
                    guard let trackID = shuffleQueue[safe: nextIndex],
                          let next = playlists[activePlaylistIndex].tracks.first(where: { $0.id == trackID })
                    else { nextIndex += 1; continue }
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
                // Normal mode: skip inaccessible tracks, collect names, show one popup, stop at end.
                guard let currentIndex = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == lastID })
                else { return }
                var skipped: [String] = []
                var nextIndex = currentIndex + 1
                while nextIndex < playlists[activePlaylistIndex].tracks.count {
                    let next = playlists[activePlaylistIndex].tracks[nextIndex]
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
                // No more accessible tracks — show popup and stop.
                if !skipped.isEmpty {
                    skippedInaccessibleNames = skipped
                    showFileNotFoundAlert = true
                }
                await stop()
                currentTrack = nil
            }
        case .all:
            // Wrap around skipping inaccessible tracks, collect names, show one popup.
            guard let currentIndex = playlists[activePlaylistIndex].tracks.firstIndex(where: { $0.id == lastID })
            else { return }
            let count = playlists[activePlaylistIndex].tracks.count
            var nextIndex = (currentIndex + 1) % count
            var attempts = 0
            var skipped: [String] = []
            while attempts < count {
                let next = playlists[activePlaylistIndex].tracks[nextIndex]
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

    // MARK: - M3U8 Import / Export

    /// Generates M3U8 content for the active playlist and writes it to the given URL.
    ///
    /// Called by `HarmoniaPlayerCommands` after `NSSavePanel` resolves the destination.
    ///
    /// - Parameters:
    ///   - url: Destination file URL (provided by NSSavePanel).
    ///   - pathStyle: Whether to write absolute or relative paths.
    /// - Throws: If the file cannot be written.
    func writeExport(to url: URL, pathStyle: M3U8PathStyle) throws {
        let service = M3U8Service()
        let content = service.export(playlist: playlist, pathStyle: pathStyle)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads an M3U8 file, creates a new playlist tab named after the filename,
    /// and re-reads metadata via `TagReaderService` for each resolved URL.
    ///
    /// Files not found on disk are skipped and recorded in `skippedImportURLs`,
    /// which the view layer observes to present a warning alert.
    ///
    /// Called by `HarmoniaPlayerCommands` after `NSOpenPanel` resolves the source URL.
    ///
    /// - Parameter url: Source `.m3u8` file URL (provided by NSOpenPanel).
    func importPlaylist(from url: URL) async {
        skippedImportURLs = []

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            lastError = .failedToOpenFile
            return
        }

        let service = M3U8Service()
        let urls = service.parse(m3u8: content, baseURL: url)

        // Create new playlist tab named after the .m3u8 filename (without extension)
        let tabName = url.deletingPathExtension().lastPathComponent
        newPlaylist(name: tabName)

        var skipped: [URL] = []
        for fileURL in urls {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                skipped.append(fileURL)
                continue
            }
            do {
                let track = try await tagReaderService.readMetadata(for: fileURL)
                playlists[activePlaylistIndex].tracks.append(track)
                playlists[activePlaylistIndex].insertionOrder.append(track.id)
            } catch {
                let track = Track(url: fileURL)
                playlists[activePlaylistIndex].tracks.append(track)
                playlists[activePlaylistIndex].insertionOrder.append(track.id)
            }
        }

        if !skipped.isEmpty {
            skippedImportURLs = skipped
        }
    }

    // MARK: - Private Helpers

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

    /// Maps any thrown error to a `PlaybackError` for UI consumption.
    ///
    /// If the error is already a `PlaybackError`, it is returned as-is.
    /// Otherwise, the error's localized description is wrapped in `.coreError`.
    private func mapToPlaybackError(_ error: Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError { return playbackError }
        let desc = error.localizedDescription
        // HarmoniaCore.CoreError error 3 = notFound / cannot open file
        // Map file-related core errors to user-friendly failedToOpenFile
        if desc.contains("CoreError error 3") ||
           desc.contains("notFound") ||
           desc.contains("not found") ||
           desc.contains("No such file") {
            return .failedToOpenFile
        }
        return .coreError(desc)
    }
}
