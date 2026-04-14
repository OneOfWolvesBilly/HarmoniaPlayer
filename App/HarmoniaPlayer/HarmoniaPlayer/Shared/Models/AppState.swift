//
//  AppState.swift
//  HarmoniaPlayer / Shared / Models
//
//  Created on 2026-02-15.
//

import Foundation
import Combine

extension Array {
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
    static let replayGainMode      = "hp.replayGainMode"
}

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
    private(set) var featureFlags: CoreFeatureFlags

    /// UndoManager for playlist operations (load, removeTrack, moveTrack).
    ///
    /// Injected at init for testability; production code passes a fresh
    /// `UndoManager()` by default. `HarmoniaPlayerCommands` wires ⌘Z / ⌘⇧Z
    /// to `undoManager.undo()` / `undoManager.redo()`.
    let undoManager: UndoManager

    // MARK: - Services

    /// Playback service
    let playbackService: PlaybackService

    /// Tag reader service
    let tagReaderService: TagReaderService

    /// File drop service — validates URLs received from drag-and-drop.
    let fileDropService: FileDropService

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
    @Published var playlists: [Playlist]

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
    @Published var currentTrack: Track?

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
    @Published var playbackState: PlaybackState = .idle

    /// ID of the playlist that contains the currently playing track.
    ///
    /// Set to `playlists[activePlaylistIndex].id` when `play(trackID:)` succeeds.
    /// Cleared to `nil` by `stop()` and when the last track finishes naturally.
    /// Uses `Playlist.ID` (UUID) so it remains valid after tab reordering.
    @Published var playingPlaylistID: Playlist.ID?

    /// Current playback position in seconds.
    ///
    /// Initialised to `0`. Updated on successful `seek(to:)` and
    /// reset to `0` by `stop()`.
    @Published var currentTime: TimeInterval = 0

    /// Position the user has seeked to while stopped or paused.
    /// Used by play() to resume from the correct position.
    var pendingSeekTime: TimeInterval = 0

    /// Duration of the currently loaded track in seconds.
    ///
    /// Initialised to `0`. Updated after a successful `load` in `play(trackID:)`.
    @Published var duration: TimeInterval = 0

    // MARK: - Error State

    /// Most recent playback error.
    ///
    /// `nil` on init. Set by playback logic when an error occurs.
    /// Views observe this to present error banners or alerts.
    @Published var lastError: PlaybackError?

    /// Display name of the track that triggered the most recent `failedToOpenFile` error.
    ///
    /// Set to "Title - Artist" when artist is available, otherwise the URL filename.
    /// Cleared when `clearLastError()` is called.
    @Published var failedTrackName: String?

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

    /// URLs skipped during load() because their format is not supported by
    /// HarmoniaPlayer at any tier. Non-empty triggers an unsupported-format alert.
    @Published var skippedUnsupportedURLs: [URL] = []

    // MARK: - Blocking Operation

    /// Whether a batch playlist operation (load or import) is in progress.
    ///
    /// Set to `true` at the start of `load(urls:)` and `importPlaylist(from:)`,
    /// reset to `false` via `defer` when the method returns.
    /// Used by HarmoniaPlayerCommands to disable playlist-mutating menu items
    /// and by PlaylistView to reject drops during batch operations.
    /// Not persisted — always starts as `false` on launch.
    @Published var isPerformingBlockingOperation: Bool = false

    // MARK: - File Info Panel

    /// Track currently shown in the File Info panel sheet.
    ///
    /// Set via `showFileInfo(trackID:)`; cleared automatically when the sheet
    /// is dismissed (the sheet binding sets this back to nil).
    /// Not `private(set)` so the sheet's `item` binding can dismiss it.
    @Published var fileInfoTrack: Track? = nil

    // MARK: - Paywall

    /// Whether the Pro paywall sheet is currently presented.
    ///
    /// Set to `true` by `showPaywallIfNeeded()` when a Free-tier user
    /// triggers a Pro-only action. The sheet binding resets it to `false`
    /// on dismissal.
    @Published var showPaywall: Bool = false

    /// Whether the user has chosen to silently skip Pro-only format tracks
    /// during auto-play for this session.
    ///
    /// Set to `true` when the user dismisses the Paywall with the
    /// "skip session" checkbox checked. Resets to `false` on every app
    /// launch (not persisted). When `true`, `trackDidFinishPlaying()`
    /// silently advances past format-gated tracks without showing the Paywall.
    /// Manual track selection always shows the Paywall regardless of this flag.
    @Published var paywallDismissedThisSession: Bool = false

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
    @Published var repeatMode: RepeatMode = .off

    /// Whether shuffle mode is enabled. See `ShuffleMode` for semantics.
    @Published var isShuffled: ShuffleMode = .off

    // MARK: - ReplayGain State

    /// Current ReplayGain application mode.
    ///
    /// Defaults to `.off`. Updated by `SettingsView` picker.
    /// Persisted across launches via `UserDefaults`.
    /// Applied in `play(trackID:)` to adjust the effective playback volume.
    @Published var replayGainMode: ReplayGainMode = .off

    /// Pre-shuffled track ID order used when shuffle is enabled.
    ///
    /// Contains a permutation of all track IDs in `playlists[activePlaylistIndex].tracks`.
    /// Rebuilt whenever shuffle is toggled on or the playlist changes.
    /// `shuffleQueueIndex` points to the current position in this queue.
    var shuffleQueue: [Track.ID] = []
    var shuffleQueueIndex: Int = 0

    /// The ID of the last successfully played track.
    ///
    /// Set after `playbackService.play()` succeeds in `play(trackID:)`.
    /// Used by `trackDidFinishPlaying()` to find the current position in the playlist
    /// when `currentTrack` has been cleared (e.g. after a failed play attempt).
    var lastPlayedTrackID: Track.ID?

    // MARK: - Format Classification

    /// File extensions supported on the Free tier (and Pro tier).
    static let freeFormats: Set<String>    = ["mp3", "aac", "m4a", "wav", "aiff", "alac"]

    /// File extensions that require the Pro tier (FLAC / DSD).
    static let proOnlyFormats: Set<String> = ["flac", "dsf", "dff"]

    /// File extensions currently allowed for loading into playlists.
    ///
    /// v0.1 frozen: returns freeFormats only. FLAC/DSF/DFF are treated as
    /// unsupported (same as .xyz) — not added to playlist, no Paywall.
    /// v0.2: restore to `isProUnlocked ? freeFormats.union(proOnlyFormats) : freeFormats`
    static var allowedFormats: Set<String> { freeFormats }

    /// Number of tracks added between incremental saves in batch operations.
    /// Provides crash safety for large imports without saving on every track.
    static let saveBatchSize = 5

    // MARK: - Polling

    /// Task that polls playback state and currentTime while playing.
    var pollingTask: Task<Void, Never>?

    /// Combine subscriptions retained for the lifetime of AppState.
    private var cancellables = Set<AnyCancellable>()

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
        userDefaults: UserDefaults = .standard,
        undoManager: UndoManager? = nil
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
        self.fileDropService = FileDropService()

        // Step 5: Store UndoManager.
        // Default parameter uses nil instead of UndoManager() to avoid
        // calling a @MainActor initializer from a nonisolated context (Swift 6).
        // levelsOfUndo = 10: retain the 10 most recent track operations only;
        // NSUndoManager automatically discards the oldest when the limit is exceeded.
        self.undoManager = undoManager ?? UndoManager()
        self.undoManager.levelsOfUndo = 10

        // Step 6: Expose Pro unlock state
        self.isProUnlocked = iapManager.isProUnlocked

        // Step 7: Initialise playlist state
        self.playlists = [Playlist(name: "Playlist 1")]
        self.currentTrack = nil

        // Step 8: Store UserDefaults instance
        self.userDefaults = userDefaults

        // Step 9: Resolve languageBundle from persisted setting.
        // Fixed at launch so UI strings and system menus change together after restart.
        let persistedLang = userDefaults.string(forKey: "hp.selectedLanguage") ?? "en"
        if persistedLang != "system",
           let path = Bundle.main.path(forResource: persistedLang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.languageBundle = bundle
        } else {
            self.languageBundle = .main
        }

        // Step 10: Restore persisted state (overrides Step 7 defaults if data exists)
        restoreState()

        // Step 11: React to replayGainMode changes during active playback.
        // When the user switches mode in Settings, immediately re-apply the
        // effective volume so the change is audible without restarting the track.
        $replayGainMode
            .dropFirst()            // skip the initial emission at subscription time
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.applyReplayGainVolume(requiresActivePlayback: true) }
            }
            .store(in: &cancellables)

        // Step 12: Persist replayGainMode and selectedLanguage whenever they
        // change. SettingsView must not call saveState() directly — persistence
        // is AppState's responsibility.
        $replayGainMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.saveState() }
            .store(in: &cancellables)

        $selectedLanguage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.saveState() }
            .store(in: &cancellables)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}

    // MARK: - Display Name

    /// Returns a human-readable display name for a track.
    ///
    /// Priority:
    /// 1. title + artist → "title - artist"
    /// 2. title only    → "title"
    /// 3. artist only   → "artist"
    /// 4. neither       → filename from originalPath (no extension)
    func displayName(for track: Track) -> String {
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

    // MARK: - Error Helpers

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

    // MARK: - Paywall

    /// Shows the Pro paywall sheet if the user is on the Free tier.
    ///
    /// Sets `showPaywall = true` and returns `true` when `isProUnlocked == false`.
    /// Returns `false` (and does not show the paywall) when Pro is already unlocked.
    ///
    /// Call this guard before any Pro-only action:
    /// ```swift
    /// guard !showPaywallIfNeeded() else { return }
    /// // proceed with Pro action
    /// ```
    @discardableResult
    func showPaywallIfNeeded() -> Bool {
        guard !isProUnlocked else { return false }
        showPaywall = true
        return true
    }

    // MARK: - IAP

    /// Initiates the Pro purchase flow via `IAPManager`.
    ///
    /// On success, `isProUnlocked` is refreshed from `iapManager.isProUnlocked`.
    /// Throws `IAPError` on failure or user cancellation.
    func purchasePro() async throws {
        try await iapManager.purchasePro()
        isProUnlocked = iapManager.isProUnlocked
        featureFlags = CoreFeatureFlags(iapManager: iapManager)
    }

    /// Refreshes Pro entitlements from the App Store via `IAPManager`.
    ///
    /// Updates `isProUnlocked` from `iapManager.isProUnlocked` after completion.
    /// Call at app launch to verify cached purchase state.
    func refreshEntitlements() async {
        await iapManager.refreshEntitlements()
        isProUnlocked = iapManager.isProUnlocked
        featureFlags = CoreFeatureFlags(iapManager: iapManager)
    }

    // MARK: - Persistence

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
        userDefaults.set(replayGainMode.rawValue, forKey: PersistenceKey.replayGainMode)
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
        if let raw = userDefaults.string(forKey: PersistenceKey.replayGainMode),
           let mode = ReplayGainMode(rawValue: raw) {
            replayGainMode = mode
        }

        // Background metadata refresh: re-reads fields for tracks that were
        // saved by an older version of the metadata reading logic.
        Task { await refreshMetadataIfNeeded() }
    }

    /// Re-reads metadata for any track whose `metadataVersion` is lower than
    /// `tagReaderService.currentSchemaVersion`.
    ///
    /// Runs in the background after `restoreState()`. Only tracks restored from
    /// older saves (version 0) are affected. New fields are written back and
    /// `saveState()` is called so the refresh only happens once per track.
    private func refreshMetadataIfNeeded() async {
        var didRefreshAny = false

        // Snapshot track IDs and URLs that need refresh, so we don't
        // rely on indices that may become stale across await points.
        struct RefreshCandidate {
            let id: Track.ID
            let url: URL
        }

        var candidates: [RefreshCandidate] = []
        for playlist in playlists {
            for track in playlist.tracks {
                if track.isAccessible,
                   track.metadataVersion < tagReaderService.currentSchemaVersion {
                    candidates.append(RefreshCandidate(id: track.id, url: track.url))
                }
            }
        }

        for candidate in candidates {
            guard let refreshed = try? await tagReaderService.readMetadata(for: candidate.url)
            else { continue }

            // Re-locate the track by ID after the async suspension.
            // The user may have reordered, removed, or added tracks while
            // readMetadata was running, so stale indices are unsafe.
            guard let pi = playlists.firstIndex(where: { $0.tracks.contains { $0.id == candidate.id } }),
                  let ti = playlists[pi].tracks.firstIndex(where: { $0.id == candidate.id })
            else { continue }

            // Merge: update only new-field groups; preserve core fields
            // (title, artist, album, duration) from the stored version
            // so user-visible data is not unexpectedly replaced.
            playlists[pi].tracks[ti].albumArtist     = refreshed.albumArtist
            playlists[pi].tracks[ti].composer        = refreshed.composer
            playlists[pi].tracks[ti].genre           = refreshed.genre
            playlists[pi].tracks[ti].year            = refreshed.year
            playlists[pi].tracks[ti].trackNumber     = refreshed.trackNumber
            playlists[pi].tracks[ti].trackTotal      = refreshed.trackTotal
            playlists[pi].tracks[ti].discNumber      = refreshed.discNumber
            playlists[pi].tracks[ti].discTotal       = refreshed.discTotal
            playlists[pi].tracks[ti].bpm             = refreshed.bpm
            playlists[pi].tracks[ti].replayGainTrack = refreshed.replayGainTrack
            playlists[pi].tracks[ti].replayGainAlbum = refreshed.replayGainAlbum
            playlists[pi].tracks[ti].comment         = refreshed.comment
            playlists[pi].tracks[ti].bitrate         = refreshed.bitrate
            playlists[pi].tracks[ti].sampleRate      = refreshed.sampleRate
            playlists[pi].tracks[ti].channels        = refreshed.channels
            playlists[pi].tracks[ti].fileSize        = refreshed.fileSize
            playlists[pi].tracks[ti].fileFormat      = refreshed.fileFormat
            playlists[pi].tracks[ti].metadataVersion = tagReaderService.currentSchemaVersion

            didRefreshAny = true
        }

        if didRefreshAny { saveState() }
    }
}
