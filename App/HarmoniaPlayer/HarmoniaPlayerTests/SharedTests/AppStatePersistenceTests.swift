//
//  AppStatePersistenceTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-03-25.
//

import XCTest
@testable import Harmonia_Player

/// Verifies that AppState correctly persists and restores state via UserDefaults.
///
/// Two persistence strategies are tested:
/// - Immediate save: playlist mutations call saveState() automatically.
/// - willTerminate save: settings (volume, allowDuplicates, repeatMode, isShuffled)
///   are saved explicitly via saveState().
@MainActor
final class AppStatePersistenceTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var fakeTagReader: FakeTagReaderService!
    private var testDefaults: UserDefaults!
    private var testPlaylistStore: FakePlaylistStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-persistence-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!

        fakePlaybackService = FakePlaybackService()
        fakeTagReader = FakeTagReaderService()
        let provider = FakeCoreProvider(
            playbackService: fakePlaybackService,
            tagReader: fakeTagReader
        )
        let iap = MockIAPManager(isProUnlocked: false)
        testPlaylistStore = FakePlaylistStore()
        sut = AppState(iapManager: iap, provider: provider,
                       userDefaults: testDefaults, playlistStore: testPlaylistStore)
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        fakeTagReader = nil
        testPlaylistStore = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a fresh AppState backed by the same testDefaults, simulating relaunch.
    private func makeRestoredAppState() -> AppState {
        let provider = FakeCoreProvider(
            playbackService: FakePlaybackService(),
            tagReader: FakeTagReaderService()
        )
        let iap = MockIAPManager(isProUnlocked: false)
        return AppState(iapManager: iap, provider: provider,
                        userDefaults: testDefaults, playlistStore: testPlaylistStore)
    }

    // MARK: - Explicit Save / Restore

    func testSaveAndRestore_Playlist_SurvivesRelaunch() async {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.mp3"),
            URL(fileURLWithPath: "/tmp/b.mp3"),
            URL(fileURLWithPath: "/tmp/c.mp3")
        ]
        await sut.load(urls: urls)
        sut.saveState()
        sut.restoreState()

        XCTAssertEqual(sut.playlist.tracks.count, 3)
    }

    func testSaveAndRestore_TrackURL_Preserved() async {
        let expectedURL = URL(fileURLWithPath: "/tmp/known-track.mp3")
        await sut.load(urls: [expectedURL])
        sut.saveState()
        sut.restoreState()

        XCTAssertEqual(sut.playlist.tracks.first?.url, expectedURL)
    }

    func testSaveAndRestore_SortKey_Survives() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        sut.applySort(sut.playlist.tracks, key: .title, ascending: true)
        sut.saveState()
        sut.restoreState()

        XCTAssertEqual(sut.playlist.sortKey, .title)
    }

    func testSaveAndRestore_AllowDuplicates_Survives() {
        sut.allowDuplicateTracks = true
        sut.saveState()
        sut.restoreState()

        XCTAssertTrue(sut.allowDuplicateTracks)
    }

    func testSaveAndRestore_Volume_Survives() async {
        await sut.setVolume(0.7)
        sut.saveState()
        sut.restoreState()

        XCTAssertEqual(sut.volume, 0.7, accuracy: 0.001)
    }

    func testSaveAndRestore_RepeatMode_Survives() {
        sut.cycleRepeatMode() // off → all
        sut.saveState()
        sut.restoreState()

        XCTAssertEqual(sut.repeatMode, .all)
    }

    func testSaveAndRestore_ShuffleMode_Survives() {
        sut.toggleShuffle() // off → on
        sut.saveState()
        sut.restoreState()

        XCTAssertTrue(sut.isShuffled)
    }

    func testRestoreState_WhenNoData_UsesDefaults() {
        sut.restoreState()

        XCTAssertEqual(sut.playlists.count, 1)
        XCTAssertTrue(sut.playlist.isEmpty)
        XCTAssertEqual(sut.volume, 1.0, accuracy: 0.001)
    }

    // MARK: - Immediate Save (playlist mutations)

    func testLoad_ImmediatelySavesPlaylist() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlist.tracks.count, 1)
    }

    func testRemoveTrack_ImmediatelySaves() async {
        await sut.load(urls: [
            URL(fileURLWithPath: "/tmp/a.mp3"),
            URL(fileURLWithPath: "/tmp/b.mp3")
        ])
        let trackID = sut.playlist.tracks[0].id
        sut.removeTrack(trackID)

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlist.tracks.count, 1)
    }

    func testClearPlaylist_ImmediatelySaves() async {
        await sut.load(urls: [
            URL(fileURLWithPath: "/tmp/a.mp3"),
            URL(fileURLWithPath: "/tmp/b.mp3")
        ])
        sut.clearPlaylist()

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlist.tracks.count, 0)
    }

    func testNewPlaylist_ImmediatelySaves() {
        sut.newPlaylist(name: "Rock")

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlists.count, 2)
    }

    func testRenamePlaylist_ImmediatelySaves() {
        sut.renamePlaylist(at: 0, name: "B")

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlists[0].name, "B")
    }

    func testDeletePlaylist_ImmediatelySaves() {
        sut.newPlaylist(name: "Extra")
        sut.deletePlaylist(at: 1)

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlists.count, 1)
    }

    func testMoveTrack_ImmediatelySaves() async {
        let urlA = URL(fileURLWithPath: "/tmp/a.mp3")
        let urlB = URL(fileURLWithPath: "/tmp/b.mp3")
        fakeTagReader.stubbedMetadata[urlA] = Track(url: urlA, title: "A")
        fakeTagReader.stubbedMetadata[urlB] = Track(url: urlB, title: "B")
        await sut.load(urls: [urlA, urlB])

        sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 2) // [A,B] → [B,A]

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlist.tracks[0].url, urlB)
        XCTAssertEqual(restored.playlist.tracks[1].url, urlA)
    }

    func testApplySort_ImmediatelySaves() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        sut.applySort(sut.playlist.tracks, key: .title, ascending: true)

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlist.sortKey, .title)
    }

    func testRestoreInsertionOrder_ImmediatelySaves() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        sut.applySort(sut.playlist.tracks, key: .title, ascending: true)
        sut.restoreInsertionOrder()

        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.playlist.sortKey, .none)
    }

    // MARK: - Combine sink auto-save (no explicit saveState() call)

    /// Changing `replayGainMode` must trigger automatic persistence via its
    /// Combine sink — SettingsView must NOT need to call saveState() directly.
    func testReplayGainMode_AutoSaves_ViaCombineSink() async throws {
        // When: change replayGainMode without calling saveState()
        sut.replayGainMode = .album

        // Allow the Combine sink (.receive(on: RunLoop.main)) to fire
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then: a fresh AppState backed by the same UserDefaults reads back the value
        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.replayGainMode, .album,
                       "replayGainMode must be persisted automatically via Combine sink")
    }

    /// Changing `repeatMode` must trigger automatic persistence via its
    /// Combine sink — toggling repeat must NOT require an explicit saveState() call.
    func testRepeatMode_AutoSaves_ViaCombineSink() async throws {
        // When: change repeatMode without calling saveState()
        sut.repeatMode = .one

        // Allow the Combine sink (.receive(on: RunLoop.main)) to fire
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then: a fresh AppState backed by the same UserDefaults reads back the value
        let restored = makeRestoredAppState()
        XCTAssertEqual(restored.repeatMode, .one,
                       "repeatMode must be persisted automatically via Combine sink")
    }

    /// Changing `isShuffled` must trigger automatic persistence via its
    /// Combine sink — toggling shuffle must NOT require an explicit saveState() call.
    func testShuffleMode_AutoSaves_ViaCombineSink() async throws {
        // When: change isShuffled without calling saveState()
        sut.isShuffled = .on

        // Allow the Combine sink (.receive(on: RunLoop.main)) to fire
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then: a fresh AppState backed by the same UserDefaults reads back the value
        let restored = makeRestoredAppState()
        XCTAssertTrue(restored.isShuffled,
                      "isShuffled must be persisted automatically via Combine sink")
    }

    // MARK: - File-backed playlist store

    func testSaveState_WritesPlaylistsToStore_NotUserDefaults() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertEqual(testPlaylistStore.stored?.first?.tracks.count, 1,
                       "playlists must be written to the PlaylistStore")
        XCTAssertNil(testDefaults.data(forKey: "hp.playlists"),
                     "playlists must no longer be written to UserDefaults")
    }

    func testRestoreState_ReadsPlaylistsFromStore() {
        testPlaylistStore.stored = [
            Playlist(name: "Restored",
                     tracks: [Track(url: URL(fileURLWithPath: "/tmp/x.mp3"), title: "X")])
        ]
        sut.restoreState()
        XCTAssertEqual(sut.playlists.first?.name, "Restored")
        XCTAssertEqual(sut.playlist.tracks.first?.title, "X")
    }

    func testRestoreState_MigratesLegacyUserDefaultsPlaylists() throws {
        let legacy = [
            Playlist(name: "Legacy",
                     tracks: [Track(url: URL(fileURLWithPath: "/tmp/old.mp3"), title: "Old")])
        ]
        let data = try JSONEncoder().encode(legacy)
        testDefaults.set(data, forKey: "hp.playlists")
        testPlaylistStore.stored = nil
        sut.restoreState()
        XCTAssertEqual(sut.playlists.first?.name, "Legacy")
        XCTAssertEqual(testPlaylistStore.stored?.first?.name, "Legacy",
                       "legacy playlists must be migrated into the store")
        XCTAssertNil(testDefaults.data(forKey: "hp.playlists"),
                     "legacy key must be removed after one-shot migration")
    }
}
