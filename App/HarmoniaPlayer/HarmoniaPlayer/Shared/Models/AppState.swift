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

/// Composition root of the application state.
///
/// Wires all dependencies (IAP → SettingsStore → CoreFactory → Services →
/// feature stores) and connects the stores' notifications to one another.
/// Views observe the feature stores directly via `@Environment`; AppState is
/// still injected as an `@EnvironmentObject` for the UI string bundle and
/// the EQ coordinator, and as the focused scene object for the Commands.
///
/// **Usage:**
/// ```swift
/// let appState = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider())
///
/// // In SwiftUI
/// ContentView()
///     .environmentObject(appState)
///     .environment(appState.playlistCollection)
///     .environment(appState.playbackController)
/// ```
@MainActor
final class AppState: ObservableObject {

    // MARK: - Stores

    /// Alert-surface store — owns the alert, paywall, and File Info request
    /// presentation state. Views whose body reads alert state observe it via
    /// `@Environment(AlertCenter.self)`.
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

    /// Playlist collection — owns the playlists, the active playlist index,
    /// the table selection, the blocking-operation flag, the undo manager,
    /// the playlist services, and the playlist persistence. Views whose
    /// body reads playlist state observe it via
    /// `@Environment(PlaylistCollection.self)`.
    let playlistCollection: PlaylistCollection

    /// Playback controller — owns the transport state, the playback
    /// service, the repeat / shuffle modes, and the playback persistence
    /// keys. Views whose body reads playback state observe it via
    /// `@Environment(PlaybackController.self)`.
    let playbackController: PlaybackController

    // MARK: - Coordinators

    /// EQ coordinator — owns all observable EQ state.
    ///
    /// AppState holds only this reference; views read EQ state via
    /// `appState.eqCoordinator.…` or `@EnvironmentObject`.
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
    /// `onSeekCompleted` closure after a successful seek.
    let nowPlayingCoordinator: NowPlayingCoordinator

    // MARK: - Language (facade → SettingsStore)

    /// The `Bundle` used for all `NSLocalizedString(bundle:)` calls.
    /// Read-only forwarder to `settingsStore.languageBundle`.
    var languageBundle: Bundle { settingsStore.languageBundle }

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
    ///     ↓
    /// PlaylistCollection → PlaybackController → NowPlayingCoordinator
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

        // Step 2: Create factory with the settings store's flags
        let coreFactory = CoreFactory(
            featureFlags: settingsStore.featureFlags,
            provider: provider
        )

        // Step 3: Create services via factory
        let playbackService = coreFactory.makePlaybackService()
        let tagReaderService = coreFactory.makeTagReaderService()
        let fileDropService = FileDropService()
        let lyricsService = coreFactory.makeLyricsService()
        let lyricsPreferenceStore = lyricsPreferenceStore
            ?? DefaultLyricsPreferenceStore(userDefaults: userDefaults)

        // Step 4: Create EQ coordinator. The injected variant is used by
        // tests that need a pre-seeded coordinator; the default builds
        // from the same provider's EQService and an EQPersistenceStore
        // backed by the same UserDefaults instance.
        self.eqCoordinator = eqCoordinator
            ?? EQCoordinator(
                service: coreFactory.makeEQService(),
                store: EQPersistenceStore(defaults: userDefaults)
            )

        // Step 5: Construct the lyrics store, which takes ownership of the
        // lyrics service and preference store created in Step 3.
        self.lyricsStore = LyricsStore(
            lyricsService: lyricsService,
            lyricsPreferenceStore: lyricsPreferenceStore
        )

        // Step 6: Construct the playlist collection from the playlist
        // services, the undo manager, the durable playlist store, and the
        // stores it reports to. It restores the persisted playlists. The
        // undo manager and the store default to nil and are constructed
        // here, because a @MainActor initializer cannot be called from the
        // nonisolated default-argument context (Swift 6).
        let playlistCollection = PlaylistCollection(
            tagReaderService: tagReaderService,
            fileDropService: fileDropService,
            playlistStore: playlistStore ?? FilePlaylistStore(),
            undoManager: undoManager ?? UndoManager(),
            alertCenter: self.alertCenter,
            settingsStore: self.settingsStore,
            userDefaults: userDefaults
        )
        self.playlistCollection = playlistCollection

        // Step 7: Construct the playback controller from the playback
        // service, the stores it reports to, and the playlist collection as
        // its playlist context. It restores its own persistence keys.
        let playbackController = PlaybackController(
            playbackService: playbackService,
            alertCenter: self.alertCenter,
            settingsStore: self.settingsStore,
            playlistContext: playlistCollection,
            userDefaults: userDefaults
        )
        self.playbackController = playbackController

        // Step 8: Construct the NowPlayingCoordinator from the controller's
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

        // Step 9: Wire the stores' notifications. Every closure captures the
        // store it targets, never `self`.
        //
        // - Playlist mutations reach the playback controller: added tracks
        //   join the shuffle queue, removing or clearing the playing track
        //   stops or advances playback, deleting the playing playlist stops
        //   it, and a track queued next moves up in the shuffle queue.
        // - A ReplayGain mode change re-applies the effective volume during
        //   active playback, so the change is audible without restarting the
        //   track.
        // - A current-track change refreshes the lyrics store's resolution.
        // - A completed seek re-anchors the system Now Playing scrubber.
        // - Dismissing an error alert returns playback from .error to .stopped.
        // - A paywall request is presented through the alert store.
        playlistCollection.onTracksAppended = { ids in
            playbackController.handleTracksAppended(ids)
        }
        playlistCollection.onTrackRemoved = { id in
            playbackController.handleTrackRemoved(id)
        }
        playlistCollection.onTracksRemoved = { ids in
            playbackController.handleTracksRemoved(ids)
        }
        playlistCollection.onPlaylistCleared = {
            playbackController.handlePlaylistCleared()
        }
        playlistCollection.onPlaylistDeleted = { id in
            playbackController.handlePlaylistDeleted(id)
        }
        playlistCollection.onTrackQueuedNext = { id in
            playbackController.handleTrackQueuedNext(id)
        }
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

    /// Terminate-time save-all: writes the volume through
    /// `playbackController.saveVolume()`, then the playlists and the active
    /// playlist index through `playlistCollection.saveState()`. Settings
    /// keys, repeat mode, and shuffle mode are persisted by their stores at
    /// change time.
    ///
    /// Called by the app entry point when `NSApplication.willTerminateNotification` fires.
    func saveState() {
        playbackController.saveVolume()
        playlistCollection.saveState()
    }

    // MARK: - Mini Player

    /// Switches the active playlist from the Mini Player and starts playing
    /// from the first track.
    ///
    /// Called by MiniPlayerView when the user selects a playlist. Stops
    /// current playback, switches the active playlist, clears the undo stack,
    /// then plays the first track of the chosen playlist. No-op if `index` is
    /// out of range.
    ///
    /// - Parameter index: Index of the playlist to switch to.
    func switchMiniPlayerPlaylist(to index: Int) async {
        guard playlistCollection.playlists.indices.contains(index) else { return }
        await playbackController.stop()
        playlistCollection.activePlaylistIndex = index
        // Clear undo stack: switched playlist context.
        playlistCollection.undoManager.removeAllActions()
        if let first = playlistCollection.playlists[index].tracks.first {
            await playbackController.play(trackID: first.id)
        }
    }
}
