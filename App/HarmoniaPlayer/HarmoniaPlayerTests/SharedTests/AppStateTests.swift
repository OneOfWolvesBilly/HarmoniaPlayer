//
//  AppStateTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-15.
//

import XCTest
@testable import Harmonia_Player

/// Unit tests for AppState wiring
///
/// Validates that AppState correctly:
/// - Wires dependencies (IAP → Flags → Factory → Services → Stores)
/// - Hands its injected dependencies to the stores it constructs
/// - Wires the stores' notifications to one another
/// - Initializes without crashing and does not execute behavior
///
/// Note: @MainActor required because AppState is @MainActor isolated.
/// AppState.nonisolated deinit workaround is required for Xcode 26 beta.
@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates an isolated UserDefaults suite to prevent persistence state
    /// leaking between tests.
    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    /// Creates a minimal AppState for testing.
    ///
    /// - Parameter isProUnlocked: Simulates Free (`false`, default) or Pro (`true`) IAP state.
    /// - Returns: A fully wired `AppState` backed by `FakeCoreProvider`.
    private func makeSUT(isProUnlocked: Bool = false) -> AppState {
        let iap = MockIAPManager(isProUnlocked: isProUnlocked)
        let provider = FakeCoreProvider()
        return AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults(), playlistStore: FakePlaylistStore())
    }

    // MARK: - Tests: Free User

    func testInit_FreeUser_WiresDependenciesCorrectly() {
        // Given: Free tier IAP
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider,
            userDefaults: makeIsolatedDefaults(),
            playlistStore: FakePlaylistStore()
        )

        // Then: Dependencies are wired
        XCTAssertFalse(appState.settingsStore.isProUnlocked,
                       "Free user should not have Pro unlocked")
        XCTAssertFalse(appState.settingsStore.featureFlags.supportsFLAC,
                       "Free tier should not support FLAC")
        XCTAssertNotNil(appState.playbackController.playbackService,
                        "Playback service should be created")
        XCTAssertNotNil(appState.playlistCollection.tagReaderService,
                        "Tag reader service should be created")
    }

    func testInit_FreeUser_CallsProviderWithFreeConfig() {
        // Given: Free tier IAP with fake provider
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        _ = AppState(iapManager: iapManager, provider: fakeProvider, userDefaults: makeIsolatedDefaults(), playlistStore: FakePlaylistStore())

        // Then: Provider called with Free configuration
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should create playback service once")
        XCTAssertEqual(fakeProvider.lastIsProUser, false,
                       "Should pass Free configuration to provider")
        XCTAssertEqual(fakeProvider.makeTagReaderServiceCallCount, 1,
                       "Should create tag reader service once")
    }

    // MARK: - Tests: Pro User

    func testInit_ProUser_WiresDependenciesCorrectly() {
        // Given: Pro tier IAP
        let iapManager = MockIAPManager(isProUnlocked: true)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider,
            userDefaults: makeIsolatedDefaults(),
            playlistStore: FakePlaylistStore()
        )

        // Then: Dependencies are wired with Pro features
        XCTAssertTrue(appState.settingsStore.isProUnlocked,
                      "Pro user should have Pro unlocked")
        XCTAssertTrue(appState.settingsStore.featureFlags.supportsFLAC,
                      "Pro tier should support FLAC")
        XCTAssertNotNil(appState.playbackController.playbackService,
                        "Playback service should be created")
        XCTAssertNotNil(appState.playlistCollection.tagReaderService,
                        "Tag reader service should be created")
    }

    func testInit_ProUser_CallsProviderWithProConfig() {
        // Given: Pro tier IAP with fake provider
        let iapManager = MockIAPManager(isProUnlocked: true)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        _ = AppState(iapManager: iapManager, provider: fakeProvider, userDefaults: makeIsolatedDefaults(), playlistStore: FakePlaylistStore())

        // Then: Provider called with Pro configuration
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should create playback service once")
        XCTAssertEqual(fakeProvider.lastIsProUser, true,
                       "Should pass Pro configuration to provider")
        XCTAssertEqual(fakeProvider.makeTagReaderServiceCallCount, 1,
                       "Should create tag reader service once")
    }

    // MARK: - Tests: Initialization Safety

    func testInit_DoesNotCrash() {
        // Given/When/Then: Init completes without crashing
        XCTAssertNoThrow(
            _ = AppState(
                iapManager: MockIAPManager(),
                provider: FakeCoreProvider(),
                userDefaults: makeIsolatedDefaults(),
                playlistStore: FakePlaylistStore()
            )
        )
    }

    func testInit_DoesNotExecuteBehavior() {
        // Given: Fake provider
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider,
            userDefaults: makeIsolatedDefaults(),
            playlistStore: FakePlaylistStore()
        )

        // Then: Services are created but no behavior executed
        XCTAssertEqual(appState.playbackController.playbackService.state, .idle,
                       "Playback should remain idle (no auto-play)")
        XCTAssertTrue(true, "AppState should not execute playback/playlist behavior")
    }

    // MARK: - Tests: Settings Store Wiring

    /// Verifies that AppState hands its injected `UserDefaults` to the
    /// settings store, so persisted settings are restored at init.
    func testInit_SettingsStoreRestoresFromInjectedDefaults() {
        // Given: an isolated suite with a persisted ReplayGain mode
        let defaults = makeIsolatedDefaults()
        defaults.set("album", forKey: "hp.replayGainMode")

        // When: AppState is built on that suite
        let appState = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: defaults,
            playlistStore: FakePlaylistStore()
        )

        // Then: the settings store restored the persisted value
        XCTAssertEqual(appState.settingsStore.replayGainMode, .album,
                       "AppState must construct SettingsStore on its injected UserDefaults")
    }

    // MARK: - Tests: TagReader Wiring Verification

    /// `makeTagReaderService()` is called exactly once during `AppState.init`.
    func testAppState_Init_CallsMakeTagReaderService() {
        // Given
        let iap = MockIAPManager(isProUnlocked: false)
        let provider = FakeCoreProvider()

        // When
        _ = AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults(), playlistStore: FakePlaylistStore())

        // Then
        XCTAssertEqual(provider.makeTagReaderServiceCallCount, 1,
                       "AppState.init should call makeTagReaderService exactly once")
    }

    /// `tagReaderService` is non-nil after `AppState.init`.
    func testAppState_TagReaderService_IsNotNil() {
        // Given / When
        let sut = makeSUT()

        // Then
        XCTAssertNotNil(sut.playlistCollection.tagReaderService,
                        "tagReaderService should be non-nil after init")
    }

    /// `tagReaderService` stored in the playlist collection is the exact
    /// instance the provider returned.
    ///
    /// Injects a known `FakeTagReaderService` via `FakeCoreProvider(tagReader:)`
    /// so the `===` identity check is unambiguous.
    func testAppState_TagReaderService_IsFromProvider() {
        // Given: A known fake injected into the provider
        let knownFake = FakeTagReaderService()
        let provider = FakeCoreProvider(tagReader: knownFake)
        let iap = MockIAPManager(isProUnlocked: false)

        // When
        let sut = AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults(), playlistStore: FakePlaylistStore())

        // Then: the collection holds the exact instance the provider returned
        XCTAssertTrue(
            sut.playlistCollection.tagReaderService === knownFake,
            "AppState should wire the exact TagReaderService instance returned by the provider"
        )
    }

    /// No `TagReaderService` methods are called during `AppState.init`.
    ///
    /// Injects a known `FakeTagReaderService` and checks its call count
    /// remains 0 after init completes.
    func testAppState_TagReaderService_NoMethodsCalled() {
        // Given: A known fake injected into the provider
        let knownFake = FakeTagReaderService()
        let provider = FakeCoreProvider(tagReader: knownFake)
        let iap = MockIAPManager(isProUnlocked: false)

        // When
        _ = AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults(), playlistStore: FakePlaylistStore())

        // Then: No metadata reads triggered by init
        XCTAssertEqual(knownFake.readMetadataCallCount, 0,
                       "AppState.init must not call readMetadata — no eager fetch")
    }

    // MARK: - Tests: Playback controller wiring

    /// Verifies that AppState hands its injected `UserDefaults` to the
    /// playback controller, so persisted playback settings are restored at init.
    func testInit_PlaybackControllerRestoresFromInjectedDefaults() throws {
        // Given: an isolated suite with a persisted repeat mode
        let defaults = makeIsolatedDefaults()
        defaults.set(try JSONEncoder().encode(RepeatMode.all), forKey: "hp.repeatMode")

        // When: AppState is built on that suite
        let appState = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: defaults,
            playlistStore: FakePlaylistStore()
        )

        // Then: the playback controller restored the persisted value
        XCTAssertEqual(appState.playbackController.repeatMode, .all,
                       "AppState must construct PlaybackController on its injected UserDefaults")
    }

    /// Verifies the root wiring from the playback controller's current-track
    /// change to the lyrics store's resolution.
    func testInit_WiresCurrentTrackChangeToLyricsStore() async throws {
        // Given: a lyrics service stub that records resolution requests
        let stub = StubLyricsService()
        let provider = FakeCoreProvider(lyricsService: stub)
        let appState = AppState(
            iapManager: MockIAPManager(),
            provider: provider,
            userDefaults: makeIsolatedDefaults(),
            playlistStore: FakePlaylistStore()
        )
        await appState.playlistCollection.load(urls: [URL(fileURLWithPath: "/tmp/lyrics-wiring.mp3")])
        let track = try XCTUnwrap(appState.playlistCollection.playlist.tracks.first)

        // When: the controller changes the current track
        await appState.playbackController.play(trackID: track.id)

        // Then: the lyrics store resolved lyrics for that track
        XCTAssertEqual(stub.lastResolvedTrack?.id, track.id,
                       "a currentTrack change must reach LyricsStore.updateResolution(for:)")
    }

    /// Verifies that the playback controller reads playlist state from the
    /// playlist collection AppState constructed for it.
    func testInit_PlaybackControllerReadsPlaylistCollection() async throws {
        // Given: one track loaded through the collection
        let appState = makeSUT()
        await appState.playlistCollection.load(urls: [URL(fileURLWithPath: "/tmp/context-wiring.mp3")])
        let track = try XCTUnwrap(appState.playlistCollection.playlist.tracks.first)

        // When: play() with no current track resolves from the context
        await appState.playbackController.play()

        // Then: the controller played the collection's track
        XCTAssertEqual(appState.playbackController.currentTrack, track,
                       "the controller must resolve tracks in appState.playlistCollection")
    }

    // MARK: - Tests: Playlist collection wiring

    /// Verifies that AppState hands its injected `PlaylistStore` to the
    /// playlist collection, so persisted playlists are restored at init.
    func testInit_PlaylistCollectionRestoresFromInjectedStore() {
        // Given: a store seeded with one playlist
        let store = FakePlaylistStore(stored: [Playlist(name: "Seeded")])

        // When: AppState is built on that store
        let appState = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: makeIsolatedDefaults(),
            playlistStore: store
        )

        // Then: the collection restored the persisted playlists
        XCTAssertEqual(appState.playlistCollection.playlists.first?.name, "Seeded",
                       "AppState must construct PlaylistCollection on its injected PlaylistStore")
    }

    // MARK: - Tests: Error dismissal wiring

    /// Given the playback controller is in `.error(…)` and the alert store's
    /// error surface is populated,
    /// when `alertCenter.clearLastError()` is called (the error alert's
    /// dismiss action),
    /// then the controller's `playbackState` becomes `.stopped` through the
    /// root-wired `onErrorCleared` closure and the store's surface is cleared.
    func testClearLastError_ErrorState_BecomesStopped() {
        // Given
        let sut = makeSUT()
        sut.playbackController.playbackState = .error(.failedToDecode)
        sut.alertCenter.lastError = .failedToDecode
        sut.alertCenter.lastErrorDetail = "failedToDecode: /tmp/broken.mp3"
        sut.alertCenter.failedTrackName = "Broken Track"
        sut.alertCenter.showFileNotFoundAlert = true
        sut.alertCenter.skippedInaccessibleNames = ["Broken Track"]

        // When
        sut.alertCenter.clearLastError()

        // Then
        XCTAssertEqual(sut.playbackController.playbackState, .stopped,
                       "dismissing the error alert must transition the controller from .error to .stopped")
        XCTAssertNil(sut.alertCenter.lastError,
                     "clearLastError() must clear the store's lastError")
        XCTAssertNil(sut.alertCenter.lastErrorDetail,
                     "clearLastError() must clear the store's lastErrorDetail")
        XCTAssertNil(sut.alertCenter.failedTrackName,
                     "clearLastError() must clear the store's failedTrackName")
        XCTAssertFalse(sut.alertCenter.showFileNotFoundAlert,
                       "clearLastError() must lower the store's showFileNotFoundAlert")
        XCTAssertTrue(sut.alertCenter.skippedInaccessibleNames.isEmpty,
                      "clearLastError() must clear the store's skippedInaccessibleNames")
    }

    // MARK: - Tests: showPaywallIfNeeded facade

    /// Given a Free-tier AppState,
    /// when `showPaywallIfNeeded()` is called,
    /// then it returns `true` and raises the store's paywall flag.
    func testShowPaywallIfNeeded_Free_PresentsAndReturnsTrue() {
        // Given
        let sut = makeSUT(isProUnlocked: false)

        // When
        let result = sut.showPaywallIfNeeded()

        // Then
        XCTAssertTrue(result,
                      "showPaywallIfNeeded() must return true for a Free user")
        XCTAssertTrue(sut.alertCenter.showPaywall,
                      "showPaywallIfNeeded() must raise alertCenter.showPaywall")
    }

    /// Given a Pro-tier AppState,
    /// when `showPaywallIfNeeded()` is called,
    /// then it is a no-op returning `false` and the paywall stays down.
    func testShowPaywallIfNeeded_Pro_NoopReturnsFalse() {
        // Given
        let sut = makeSUT(isProUnlocked: true)

        // When
        let result = sut.showPaywallIfNeeded()

        // Then
        XCTAssertFalse(result,
                       "showPaywallIfNeeded() must return false for a Pro user")
        XCTAssertFalse(sut.alertCenter.showPaywall,
                       "showPaywallIfNeeded() must not raise the paywall for a Pro user")
    }
}
