//
//  PlaylistCollectionPersistenceTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Verifies that `PlaylistCollection` persists and restores the playlists
/// through the `PlaylistStore` and the active index through `UserDefaults`.
///
/// Two persistence strategies are tested:
/// - Immediate save: playlist mutations call `saveState()` automatically.
/// - Explicit save / restore and the restore performed by `init`.
@MainActor
final class PlaylistCollectionPersistenceTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() async throws {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private struct Fixture {
        let sut: PlaylistCollection
        let tagReader: FakeTagReaderService
        let store: FakePlaylistStore
        let defaults: UserDefaults
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "hp-test-persistence-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    /// Builds a collection on `store` and `defaults`; a second call on the
    /// same pair simulates a relaunch.
    private func makeSUT(store: FakePlaylistStore = FakePlaylistStore(),
                         defaults: UserDefaults? = nil) -> Fixture {
        let defaults = defaults ?? makeDefaults()
        let tagReader = FakeTagReaderService()
        let sut = PlaylistCollection(
            tagReaderService: tagReader,
            fileDropService: FileDropService(),
            playlistStore: store,
            undoManager: UndoManager(),
            alertCenter: AlertCenter(),
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        return Fixture(sut: sut, tagReader: tagReader, store: store, defaults: defaults)
    }

    /// Creates a fresh collection backed by the same store and defaults.
    private func makeRestored(_ f: Fixture) -> PlaylistCollection {
        makeSUT(store: f.store, defaults: f.defaults).sut
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    // MARK: - Explicit Save / Restore

    func testSaveAndRestore_Playlist_SurvivesRelaunch() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a"), url("b"), url("c")])
        f.sut.saveState()
        f.sut.restoreState()

        XCTAssertEqual(f.sut.playlist.tracks.count, 3)
    }

    func testSaveAndRestore_TrackURL_Preserved() async {
        let f = makeSUT()
        let expectedURL = url("known-track")
        await f.sut.load(urls: [expectedURL])
        f.sut.saveState()
        f.sut.restoreState()

        XCTAssertEqual(f.sut.playlist.tracks.first?.url, expectedURL)
    }

    func testSaveAndRestore_SortKey_Survives() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a")])
        f.sut.applySort(f.sut.playlist.tracks, key: .title, ascending: true)
        f.sut.saveState()
        f.sut.restoreState()

        XCTAssertEqual(f.sut.playlist.sortKey, .title)
    }

    func testRestoreState_WhenNoData_UsesDefaults() {
        let f = makeSUT()
        f.sut.restoreState()

        XCTAssertEqual(f.sut.playlists.count, 1)
        XCTAssertTrue(f.sut.playlist.isEmpty)
    }

    // MARK: - Immediate Save (playlist mutations)

    func testLoad_ImmediatelySavesPlaylist() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a")])

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.tracks.count, 1)
    }

    func testRemoveTrack_ImmediatelySaves() async throws {
        let f = makeSUT()
        await f.sut.load(urls: [url("a"), url("b")])
        let trackID = try XCTUnwrap(f.sut.playlist.tracks.first).id
        f.sut.removeTrack(trackID)

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.tracks.count, 1)
    }

    func testClearPlaylist_ImmediatelySaves() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a"), url("b")])
        f.sut.clearPlaylist()

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.tracks.count, 0)
    }

    func testNewPlaylist_ImmediatelySaves() {
        let f = makeSUT()
        f.sut.newPlaylist(name: "Rock")

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlists.count, 2)
    }

    func testRenamePlaylist_ImmediatelySaves() {
        let f = makeSUT()
        f.sut.renamePlaylist(at: 0, name: "B")

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlists[0].name, "B")
    }

    func testDeletePlaylist_ImmediatelySaves() {
        let f = makeSUT()
        f.sut.newPlaylist(name: "Extra")
        f.sut.deletePlaylist(at: 1)

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlists.count, 1)
    }

    func testMoveTrack_ImmediatelySaves() async {
        let f = makeSUT()
        let urlA = url("a")
        let urlB = url("b")
        f.tagReader.stubbedMetadata[urlA] = Track(url: urlA, title: "A")
        f.tagReader.stubbedMetadata[urlB] = Track(url: urlB, title: "B")
        await f.sut.load(urls: [urlA, urlB])

        f.sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 2) // [A,B] → [B,A]

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.tracks[safe: 0]?.url, urlB)
        XCTAssertEqual(restored.playlist.tracks[safe: 1]?.url, urlA)
    }

    func testApplySort_ImmediatelySaves() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a")])
        f.sut.applySort(f.sut.playlist.tracks, key: .title, ascending: true)

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.sortKey, .title)
    }

    func testRestoreInsertionOrder_ImmediatelySaves() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a")])
        f.sut.applySort(f.sut.playlist.tracks, key: .title, ascending: true)
        f.sut.restoreInsertionOrder()

        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.sortKey, .none)
    }

    func testPlayNext_PersistsOrderAfterSaveAndRestore() async throws {
        // Given: playlist [A, B, C], A is the current track
        let f = makeSUT()
        await f.sut.load(urls: [url("a"), url("b"), url("c")])
        let trackA = try XCTUnwrap(f.sut.playlist.tracks[safe: 0]).id
        let trackC = try XCTUnwrap(f.sut.playlist.tracks[safe: 2]).id

        // When: Play Next on C
        f.sut.playNext(trackC, afterCurrent: trackA)

        // Then: a fresh collection restoring from the same store sees the same order
        let restored = makeRestored(f)
        XCTAssertEqual(restored.playlist.tracks.map { $0.url.lastPathComponent },
                       ["a.mp3", "c.mp3", "b.mp3"],
                       "playNext order must survive a relaunch via saveState()")
    }

    // MARK: - File-backed playlist store

    func testSaveState_WritesPlaylistsToStore_NotUserDefaults() async {
        let f = makeSUT()
        await f.sut.load(urls: [url("a")])
        XCTAssertEqual(f.store.stored?.first?.tracks.count, 1,
                       "playlists must be written to the PlaylistStore")
        XCTAssertNil(f.defaults.data(forKey: "hp.playlists"),
                     "playlists must no longer be written to UserDefaults")
    }

    func testRestoreState_ReadsPlaylistsFromStore() {
        let f = makeSUT()
        f.store.stored = [
            Playlist(name: "Restored",
                     tracks: [Track(url: url("x"), title: "X")])
        ]
        f.sut.restoreState()
        XCTAssertEqual(f.sut.playlists.first?.name, "Restored")
        XCTAssertEqual(f.sut.playlist.tracks.first?.title, "X")
    }

    func testRestoreState_MigratesLegacyUserDefaultsPlaylists() throws {
        let f = makeSUT()
        let legacy = [
            Playlist(name: "Legacy",
                     tracks: [Track(url: url("old"), title: "Old")])
        ]
        let data = try JSONEncoder().encode(legacy)
        f.defaults.set(data, forKey: "hp.playlists")
        f.store.stored = nil
        f.sut.restoreState()
        XCTAssertEqual(f.sut.playlists.first?.name, "Legacy")
        XCTAssertEqual(f.store.stored?.first?.name, "Legacy",
                       "legacy playlists must be migrated into the store")
        XCTAssertNil(f.defaults.data(forKey: "hp.playlists"),
                     "legacy key must be removed after one-shot migration")
    }

    // MARK: - Restore at init

    func testInit_RestoresPlaylistsFromStore() {
        let store = FakePlaylistStore(stored: [Playlist(name: "Seeded")])

        let f = makeSUT(store: store)

        XCTAssertEqual(f.sut.playlists.first?.name, "Seeded",
                       "init must restore the playlists from the store")
    }

    func testInit_ClampsActivePlaylistIndexToRange() {
        let store = FakePlaylistStore(stored: [Playlist(name: "One"), Playlist(name: "Two")])
        let defaults = makeDefaults()
        defaults.set(5, forKey: "hp.activePlaylistIndex")

        let f = makeSUT(store: store, defaults: defaults)

        XCTAssertEqual(f.sut.activePlaylistIndex, 1,
                       "a persisted index past the end must clamp to the last playlist")
    }

    func testInit_MarksMissingFilesInaccessible() {
        var missing = Track(url: url("gone"), title: "Gone")
        missing.originalPath = "/nonexistent/\(UUID().uuidString)/gone.mp3"
        let store = FakePlaylistStore(stored: [Playlist(name: "One", tracks: [missing])])

        let f = makeSUT(store: store)

        XCTAssertEqual(f.sut.playlist.tracks.first?.isAccessible, false,
                       "a restored track whose file is missing must be marked inaccessible")
    }

    func testSaveState_WritesActivePlaylistIndex() {
        let f = makeSUT()
        f.sut.newPlaylist(name: "Rock")

        f.sut.saveState()

        XCTAssertEqual(f.defaults.integer(forKey: "hp.activePlaylistIndex"), 1)
    }
}
