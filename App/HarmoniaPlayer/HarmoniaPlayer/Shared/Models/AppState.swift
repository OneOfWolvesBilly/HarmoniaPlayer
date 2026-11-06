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
    static let sortKey             = "hp.sortKey"
    static let sortAscending       = "hp.sortAscending"
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

    /// UserDefaults store used for persistence.
    private let userDefaults: UserDefaults

    /// Durable store for the playlist collection, kept outside UserDefaults
    /// because playlists exceed the UserDefaults single-value size limit.
    private let playlistStore: PlaylistStore

    /// UndoManager for playlist operations (load, removeTrack, moveTrack).
    ///
    /// Injected at init for testability; production code passes a fresh
    /// `UndoManager()` by default. `HarmoniaPlayerCommands` wires ⌘Z / ⌘⇧Z
    /// to `undoManager.undo()` / `undoManager.redo()`.
    let undoManager: UndoManager

    // MARK: - Stores

    /// Alert-surface store — owns the alert, paywall, and File Info request
    /// presentation state. Views whose body reads alert state observe it via
    /// `@Environment(AlertCenter.self)`; AppState's same-named facade
    /// forwarders keep internal call sites writing through it.
    let alertCenter: AlertCenter

    /// Lyrics store — owns the lyrics panel visibility, the current track's
    /// lyrics resolution, and the lyrics service dependencies. Views whose
    /// body reads lyrics state observe it via
    /// `@Environment(LyricsStore.self)`.
    let lyricsStore: LyricsStore

    /// Settings store — owns the user settings, the Free/Pro tier state,
    /// and the UI string bundle. Views whose body reads settings state
    /// observe it via `@Environment(SettingsStore.self)`.
    let settingsStore: SettingsStore

    /// Playback controller — owns the transport state, the playback
    /// service, the repeat / shuffle modes, and the playback persistence
    /// keys. Views whose body reads playback state observe it via
    /// `@Environment(PlaybackController.self)`.
    let playbackController: PlaybackController

    // MARK: - Services

    /// Playback service. Read-only forwarder to
    /// `playbackController.playbackService`; the playlist code calls
    /// `playbackService.stop()` when it removes the playing track.
    var playbackService: PlaybackService { playbackController.playbackService }

    /// Tag reader service
    let tagReaderService: TagReaderService

    /// File drop service — validates URLs received from drag-and-drop.
    let fileDropService: FileDropService

    /// EQ coordinator — owns all observable EQ state (Slice 9-K commit 6).
    ///
    /// AppState holds only this reference; views read EQ state via
    /// `appState.eqCoordinator.…`. AppState itself has no EQ-specific
    /// `@Published` properties or methods.
    let eqCoordinator: EQCoordinator

    /// NowPlaying coordinator — owns all wiring between the playback
    /// controller's publishers, its transport methods, and the system
    /// Now Playing surface (Control Center widget, lock screen,
    /// AirPods, media keys, Siri).
    ///
    /// AppState holds only this reference. The coordinator is built from
    /// `playbackController`'s publishers and seven action closures that
    /// capture the controller; it receives one direct notification —
    /// `notifySeekCompleted(at:)` — through the controller's
    /// `onSeekCompleted` closure after a successful seek. The controller is
    /// constructed first, so the coordinator can be a `let`.
    let nowPlayingCoordinator: NowPlayingCoordinator

    // MARK: - Published State

    /// Whether Pro features are unlocked.
    /// Read-only forwarder to `settingsStore.isProUnlocked`.
    var isProUnlocked: Bool { settingsStore.isProUnlocked }

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

    /// IDs of tracks currently selected in PlaylistView's Table.
    ///
    /// Promoted from PlaylistView `@State` so that `play()` can access
    /// the playlist selection when `currentTrack` is nil (e.g. after stop).
    /// Selection does NOT follow playback — it reflects user clicks only.
    @Published var selectedTrackIDs = Set<Track.ID>()

    // MARK: - Playback State (facade → PlaybackController)

    /// Currently selected track. Forwards to `playbackController.currentTrack`;
    /// the playlist code clears it when the playing track is removed.
    var currentTrack: Track? {
        get { playbackController.currentTrack }
        set { playbackController.currentTrack = newValue }
    }

    /// Current playback state. Forwards to `playbackController.playbackState`.
    var playbackState: PlaybackState {
        get { playbackController.playbackState }
        set { playbackController.playbackState = newValue }
    }

    /// Current playback position in seconds. Forwards to
    /// `playbackController.currentTime`.
    var currentTime: TimeInterval {
        get { playbackController.currentTime }
        set { playbackController.currentTime = newValue }
    }

    /// ID of the playlist that contains the currently playing track.
    /// Read-only forwarder to `playbackController.playingPlaylistID`.
    var playingPlaylistID: Playlist.ID? { playbackController.playingPlaylistID }

    /// Current repeat mode. Read-only forwarder to
    /// `playbackController.repeatMode`.
    var repeatMode: RepeatMode { playbackController.repeatMode }

    /// Whether shuffle mode is enabled. Read-only forwarder to
    /// `playbackController.isShuffled`.
    var isShuffled: ShuffleMode { playbackController.isShuffled }

    /// Pre-shuffled track ID order used when shuffle is enabled. Forwards to
    /// `playbackController.shuffleQueue`; the playlist code keeps the queue
    /// in step with track insertions and removals.
    var shuffleQueue: [Track.ID] {
        get { playbackController.shuffleQueue }
        set { playbackController.shuffleQueue = newValue }
    }

    /// Current position in `shuffleQueue`. Forwards to
    /// `playbackController.shuffleQueueIndex`.
    var shuffleQueueIndex: Int {
        get { playbackController.shuffleQueueIndex }
        set { playbackController.shuffleQueueIndex = newValue }
    }

    // MARK: - Error State (facade → AlertCenter)

    /// Most recent playback error. Forwards to `alertCenter.lastError`.
    var lastError: PlaybackError? {
        get { alertCenter.lastError }
        set { alertCenter.lastError = newValue }
    }

    /// One-line diagnostic summary accompanying `lastError`.
    /// Forwards to `alertCenter.lastErrorDetail`.
    var lastErrorDetail: String? {
        get { alertCenter.lastErrorDetail }
        set { alertCenter.lastErrorDetail = newValue }
    }

    /// Display name of the track that triggered the most recent
    /// `failedToOpenFile` error. Forwards to `alertCenter.failedTrackName`.
    var failedTrackName: String? {
        get { alertCenter.failedTrackName }
        set { alertCenter.failedTrackName = newValue }
    }

    /// Controls the file-not-found alert presentation.
    /// Forwards to `alertCenter.showFileNotFoundAlert`.
    var showFileNotFoundAlert: Bool {
        get { alertCenter.showFileNotFoundAlert }
        set { alertCenter.showFileNotFoundAlert = newValue }
    }

    /// Names of tracks skipped during auto-play due to inaccessibility.
    /// Forwards to `alertCenter.skippedInaccessibleNames`.
    var skippedInaccessibleNames: [String] {
        get { alertCenter.skippedInaccessibleNames }
        set { alertCenter.skippedInaccessibleNames = newValue }
    }

    /// URLs skipped by the last load because they already exist in the
    /// playlist. Forwards to `alertCenter.skippedDuplicateURLs`.
    var skippedDuplicateURLs: [URL] {
        get { alertCenter.skippedDuplicateURLs }
        set { alertCenter.skippedDuplicateURLs = newValue }
    }

    /// URLs skipped by the last playlist import because the files were not
    /// found on disk. Forwards to `alertCenter.skippedImportURLs`.
    var skippedImportURLs: [URL] {
        get { alertCenter.skippedImportURLs }
        set { alertCenter.skippedImportURLs = newValue }
    }

    /// URLs skipped by the last load because their format is not supported
    /// at any tier. Forwards to `alertCenter.skippedUnsupportedURLs`.
    var skippedUnsupportedURLs: [URL] {
        get { alertCenter.skippedUnsupportedURLs }
        set { alertCenter.skippedUnsupportedURLs = newValue }
    }

    // MARK: - Blocking Operation

    /// Whether a batch playlist operation (load or import) is in progress.
    ///
    /// Set to `true` at the start of `load(urls:)` and `importPlaylist(from:)`,
    /// reset to `false` via `defer` when the method returns.
    /// Used by HarmoniaPlayerCommands to disable playlist-mutating menu items
    /// and by PlaylistView to reject drops during batch operations.
    /// Not persisted — always starts as `false` on launch.
    @Published var isPerformingBlockingOperation: Bool = false

    // MARK: - File Info Panel (facade → AlertCenter)

    /// One-shot signal requesting the File Info window to open for a track.
    /// Forwards to `alertCenter.fileInfoTrack`.
    var fileInfoTrack: Track? {
        get { alertCenter.fileInfoTrack }
        set { alertCenter.fileInfoTrack = newValue }
    }

    // MARK: - Paywall (facade → AlertCenter)

    /// Whether the Pro paywall sheet is currently presented.
    /// Forwards to `alertCenter.showPaywall`.
    var showPaywall: Bool {
        get { alertCenter.showPaywall }
        set { alertCenter.showPaywall = newValue }
    }

    /// Whether the user has chosen to silently skip Pro-only format tracks
    /// during auto-play for this session.
    /// Forwards to `alertCenter.paywallDismissedThisSession`.
    var paywallDismissedThisSession: Bool {
        get { alertCenter.paywallDismissedThisSession }
        set { alertCenter.paywallDismissedThisSession = newValue }
    }

    // MARK: - Settings (facade → SettingsStore)

    /// Whether duplicate URLs are allowed in the playlist.
    /// Forwards to `settingsStore.allowDuplicateTracks`; read by the
    /// duplicate-URL check in `load(urls:)`.
    var allowDuplicateTracks: Bool {
        get { settingsStore.allowDuplicateTracks }
        set { settingsStore.allowDuplicateTracks = newValue }
    }

    // MARK: - Language (facade → SettingsStore)

    /// The `Bundle` used for all `NSLocalizedString(bundle:)` calls.
    /// Read-only forwarder to `settingsStore.languageBundle`.
    var languageBundle: Bundle { settingsStore.languageBundle }

    // MARK: - ReplayGain (facade → SettingsStore)

    /// Current ReplayGain application mode.
    /// Forwards to `settingsStore.replayGainMode`; applied in
    /// `play(trackID:)` to adjust the effective playback volume.
    var replayGainMode: ReplayGainMode {
        get { settingsStore.replayGainMode }
        set { settingsStore.replayGainMode = newValue }
    }

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

    // MARK: - Transport (facade → PlaybackController)

    /// Stops playback. Forwards to `playbackController.stop()`; called by
    /// the playlist code when the playing playlist is deleted or switched
    /// from the Mini Player.
    func stop() async {
        await playbackController.stop()
    }

    /// Loads and plays the track matching `trackID`. Forwards to
    /// `playbackController.play(trackID:)`; called by the playlist code
    /// after removing the playing track and by the Mini Player switch.
    func play(trackID: Track.ID) async {
        await playbackController.play(trackID: trackID)
    }

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
    /// SettingsStore (CoreFeatureFlags derived)
    ///     ↓
    /// CoreFactory (with flags)
    ///     ↓
    /// Services (created via factory)
    /// ```
    init(
        iapManager: IAPManager,
        provider: CoreServiceProviding,
        userDefaults: UserDefaults = .standard,
        playlistStore: PlaylistStore? = nil,
        undoManager: UndoManager? = nil,
        lyricsPreferenceStore: LyricsPreferenceStore? = nil,
        eqCoordinator: EQCoordinator? = nil
    ) {
        // Step 0: Construct the alert store first — it has no dependencies,
        // and every later step may surface an alert through it.
        self.alertCenter = AlertCenter()

        // Step 1: Construct the settings store. It takes ownership of the
        // IAP manager, derives the feature flags, and restores the persisted
        // settings from the injected UserDefaults.
        self.settingsStore = SettingsStore(
            iapManager: iapManager,
            userDefaults: userDefaults
        )

        // Step 3: Create factory with the settings store's flags
        let coreFactory = CoreFactory(
            featureFlags: settingsStore.featureFlags,
            provider: provider
        )

        // Step 4: Create services via factory
        let playbackService = coreFactory.makePlaybackService()
        self.tagReaderService = coreFactory.makeTagReaderService()
        self.fileDropService = FileDropService()
        let lyricsService = coreFactory.makeLyricsService()
        let lyricsPreferenceStore = lyricsPreferenceStore
            ?? DefaultLyricsPreferenceStore(userDefaults: userDefaults)

        // Step 4b: Create EQ coordinator. The injected variant is used by
        // tests that need a pre-seeded coordinator; the default builds
        // from the same provider's EQService and an EQPersistenceStore
        // backed by the same UserDefaults instance.
        self.eqCoordinator = eqCoordinator
            ?? EQCoordinator(
                service: coreFactory.makeEQService(),
                store: EQPersistenceStore(defaults: userDefaults)
            )

        // Step 4c: Construct the lyrics store, which takes ownership of the
        // lyrics service and preference store created in Step 4.
        self.lyricsStore = LyricsStore(
            lyricsService: lyricsService,
            lyricsPreferenceStore: lyricsPreferenceStore
        )

        // Step 4d: Construct the playback controller from the playback
        // service and the stores it reports to. It restores its own
        // persistence keys. Its playlist context is assigned at the end of
        // init, once `self` is fully initialised.
        let playbackController = PlaybackController(
            playbackService: playbackService,
            alertCenter: self.alertCenter,
            settingsStore: self.settingsStore,
            userDefaults: userDefaults
        )
        self.playbackController = playbackController

        // Step 4e: Construct the NowPlayingCoordinator from the controller's
        // publishers and transport methods. The coordinator never holds an
        // AppState reference; it sees only the publishers, the currentTime
        // getter, and the seven action closures, which capture the
        // controller. Production resolves the NowPlayingService factory to
        // MPNowPlayingAdapter; tests resolve it to FakeNowPlayingService via
        // FakeCoreProvider.
        self.nowPlayingCoordinator = NowPlayingCoordinator(
            service: coreFactory.makeNowPlayingService(),
            currentTrackPublisher: playbackController.currentTrackPublisher,
            playbackStatePublisher: playbackController.playbackStatePublisher,
            currentTimeProvider: { playbackController.currentTime },
            play: { await playbackController.play() },
            pause: { await playbackController.pause() },
            stop: { await playbackController.stop() },
            seek: { seconds in await playbackController.seek(to: seconds) },
            next: { await playbackController.playNextTrack() },
            previous: { await playbackController.playPreviousTrack() },
            togglePlayPause: {
                if playbackController.playbackState == .playing {
                    await playbackController.pause()
                } else {
                    await playbackController.play()
                }
            }
        )

        // Step 5: Store UndoManager.
        // Default parameter uses nil instead of UndoManager() to avoid
        // calling a @MainActor initializer from a nonisolated context (Swift 6).
        // levelsOfUndo = 10: retain the 10 most recent track operations only;
        // NSUndoManager automatically discards the oldest when the limit is exceeded.
        self.undoManager = undoManager ?? UndoManager()
        self.undoManager.levelsOfUndo = 10

        // Step 7: Initialise playlist state
        self.playlists = [Playlist(name: "Playlist 1")]

        // Step 8: Store UserDefaults instance
        self.userDefaults = userDefaults

        // Step 8b: Build the durable playlist store. The parameter defaults to
        // nil and the real store is constructed here, because a @MainActor
        // initializer cannot be called from the nonisolated default-argument
        // context (same constraint as undoManager below).
        self.playlistStore = playlistStore ?? FilePlaylistStore()

        // Step 10: Restore persisted state (overrides Step 7 defaults if data exists)
        restoreState()

        // Step 11: Wire the stores' notifications. Every closure captures the
        // store it targets, never `self`.
        //
        // - The playback controller reads and writes playlist state through
        //   its PlaylistContext, which is AppState until the playlist state
        //   moves into its own store.
        // - A ReplayGain mode change re-applies the effective volume during
        //   active playback, so the change is audible without restarting the
        //   track.
        // - A current-track change refreshes the lyrics store's resolution.
        // - A completed seek re-anchors the system Now Playing scrubber.
        // - Dismissing an error alert returns playback from .error to .stopped.
        // - A paywall request is presented through the alert store.
        playbackController.playlistContext = self
        settingsStore.onReplayGainModeChanged = { _ in
            Task { @MainActor in
                await playbackController.applyReplayGainVolume(requiresActivePlayback: true)
            }
        }
        playbackController.onCurrentTrackChanged = { [lyricsStore] track in
            lyricsStore.updateResolution(for: track)
        }
        playbackController.onSeekCompleted = { [weak nowPlayingCoordinator] seconds in
            nowPlayingCoordinator?.notifySeekCompleted(at: seconds)
        }
        alertCenter.onErrorCleared = {
            playbackController.recoverFromError()
        }
        settingsStore.onPaywallRequested = { [weak alertCenter = self.alertCenter] in
            alertCenter?.presentPaywall()
        }
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}

    // MARK: - File Info

    /// Requests the File Info window to open for the track with the given ID.
    ///
    /// Looks the track up in the active playlist (the lookup needs
    /// `playlist`, so it stays in the facade) and hands the request to
    /// `alertCenter.presentFileInfo(_:)`. If no matching track is found,
    /// the call is a no-op and the pending request remains unchanged.
    func showFileInfo(trackID: Track.ID) {
        guard let track = playlist.tracks.first(where: { $0.id == trackID }) else { return }
        alertCenter.presentFileInfo(track)
    }

    // MARK: - Paywall (facade → SettingsStore)

    /// Shows the Pro paywall sheet if the user is on the Free tier.
    ///
    /// Forwards to `settingsStore.showPaywallIfNeeded()`, whose paywall
    /// request reaches `alertCenter.presentPaywall()` through the
    /// `onPaywallRequested` closure wired in `init`. Returns `true` when the
    /// paywall was requested, `false` when Pro is already unlocked.
    @discardableResult
    func showPaywallIfNeeded() -> Bool {
        settingsStore.showPaywallIfNeeded()
    }

    // MARK: - Persistence

    /// Saves playlists, activePlaylistIndex, and — through
    /// `playbackController.saveVolume()` — the volume. Settings keys, repeat
    /// mode, and shuffle mode are persisted by their stores at change time.
    ///
    /// Called by the app entry point when `NSApplication.willTerminateNotification` fires.
    func saveState() {
        playbackController.saveVolume()
        try? playlistStore.save(playlists)
        userDefaults.set(activePlaylistIndex, forKey: PersistenceKey.activePlaylistIndex)
    }

    /// Restores previously saved playlist state.
    ///
    /// Called once in `init` after services are wired. The playback
    /// controller restores its own keys in its init.
    /// When no persisted data exists, the default values set in `init` are preserved.
    func restoreState() {
        // Load playlists from the file-backed store. When the store has nothing
        // yet, migrate playlists previously kept in UserDefaults and remove the
        // legacy key so the migration runs only once.
        var restoredPlaylists = try? playlistStore.load()
        if restoredPlaylists == nil,
           let legacyData = userDefaults.data(forKey: PersistenceKey.playlists),
           let legacy = try? JSONDecoder().decode([Playlist].self, from: legacyData) {
            restoredPlaylists = legacy
            try? playlistStore.save(legacy)
            userDefaults.removeObject(forKey: PersistenceKey.playlists)
        }
        if let decoded = restoredPlaylists, !decoded.isEmpty {
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
    func refreshMetadataIfNeeded() async {
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
                   track.metadataVersion < tagReaderService.currentSchemaVersion
                       || track.artworkData == nil {
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
            playlists[pi].tracks[ti].codec           = refreshed.codec
            playlists[pi].tracks[ti].encoding        = refreshed.encoding
            playlists[pi].tracks[ti].artworkData     = refreshed.artworkData
            playlists[pi].tracks[ti].lyrics          = refreshed.lyrics
            playlists[pi].tracks[ti].metadataVersion = tagReaderService.currentSchemaVersion

            didRefreshAny = true
        }

        if didRefreshAny { saveState() }
    }
}
