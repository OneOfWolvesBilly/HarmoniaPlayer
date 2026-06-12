//
//  AppStatePlaylistTests.swift
//  HarmoniaPlayerTests
//
//  Playlist Operations in AppState
//

import XCTest
@testable import Harmonia_Player

// MARK: - Helpers

private func makeURLs(_ names: [String]) -> [URL] {
    names.map { URL(fileURLWithPath: "/tmp/\($0).mp3") }
}

// MARK: - Test Suite

/// Tests for Playlist Operations
///
/// @MainActor required because AppState is @MainActor isolated.
/// XCTest executes @MainActor test classes on the main actor automatically.
///
/// **Slice 3-B update:**
/// All calls to `load(urls:)` are now `async` — test methods that invoke
/// `sut.load(urls:)` are marked `async` accordingly.
@MainActor
final class AppStatePlaylistTests: XCTestCase {

    // MARK: - SUT

    private var sut: AppState!
    private var testDefaults: UserDefaults!
    private var testPlaylistStore: FakePlaylistStore!
    private var suiteName: String!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        testPlaylistStore = FakePlaylistStore()
        sut = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: testDefaults,
            playlistStore: testPlaylistStore
        )
    }

    override func tearDown() async throws {
        sut = nil
        testPlaylistStore = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitial_PlaylistIsEmpty() {
        XCTAssertTrue(sut.playlist.isEmpty)
    }

    func testInitial_CurrentTrackIsNil() {
        XCTAssertNil(sut.currentTrack)
    }

    // MARK: - load(urls:)

    func testLoad_EmptyPlaylist_AddsTrack() async {
        await sut.load(urls: makeURLs(["song"]))

        XCTAssertEqual(sut.playlist.count, 1)
    }

    func testLoad_ExistingPlaylist_AppendsTrack() async {
        await sut.load(urls: makeURLs(["a"]))
        await sut.load(urls: makeURLs(["b"]))

        XCTAssertEqual(sut.playlist.count, 2)
    }

    func testLoad_MultipleURLs_AddsAll() async {
        await sut.load(urls: makeURLs(["a", "b"]))

        XCTAssertEqual(sut.playlist.count, 2)
    }

    func testLoad_DerivesTitleFromFilename() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/my-song.mp3")])

        XCTAssertEqual(sut.playlist.tracks.first?.title, "my-song")
    }

    // MARK: - clearPlaylist()

    func testClearPlaylist_WithTracks_EmptiesPlaylist() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))

        sut.clearPlaylist()

        XCTAssertTrue(sut.playlist.isEmpty)
    }

    func testClearPlaylist_NilsCurrentTrack() async {
        await sut.load(urls: makeURLs(["a"]))
        await sut.play(trackID: sut.playlist.tracks[0].id)
        XCTAssertNotNil(sut.currentTrack)           // pre-condition

        sut.clearPlaylist()

        XCTAssertNil(sut.currentTrack)
    }

    // MARK: - removeTrack(_:)

    func testRemoveTrack_ExistingID_RemovesTrack() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let targetID = sut.playlist.tracks[1].id

        sut.removeTrack(targetID)

        XCTAssertEqual(sut.playlist.count, 2)
        XCTAssertFalse(sut.playlist.tracks.contains { $0.id == targetID })
    }

    func testRemoveTrack_InvalidID_NoChange() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))

        sut.removeTrack(UUID())

        XCTAssertEqual(sut.playlist.count, 3)
    }

    /// Design: removing the only playing track stops playback.
    /// currentTrack is cleared asynchronously via Task inside removeTrack.
    func testRemoveTrack_CurrentTrack_StopsPlayback() async {
        await sut.load(urls: makeURLs(["a"]))
        let id = sut.playlist.tracks[0].id
        await sut.play(trackID: id)
        XCTAssertNotNil(sut.currentTrack)           // pre-condition

        sut.removeTrack(id)

        // Allow async Task inside removeTrack to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(sut.playlist.tracks.isEmpty)
        XCTAssertEqual(sut.playbackState, .stopped)
    }

    func testRemoveTrack_OtherTrack_KeepsCurrentTrack() async {
        await sut.load(urls: makeURLs(["a", "b"]))
        let trackA = sut.playlist.tracks[0]
        let trackBID = sut.playlist.tracks[1].id
        await sut.play(trackID: trackA.id)

        sut.removeTrack(trackBID)

        XCTAssertEqual(sut.currentTrack, trackA)
    }

    // MARK: - removeTracks(_:)

    func testRemoveTracks_AllSelected_EmptiesPlaylist() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let allIDs = Set(sut.playlist.tracks.map(\.id))

        sut.removeTracks(allIDs)

        XCTAssertTrue(sut.playlist.isEmpty)
    }

    func testRemoveTracks_Subset_RemovesOnlySelectedKeepsOrder() async {
        await sut.load(urls: makeURLs(["a", "b", "c", "d"]))
        let ids = sut.playlist.tracks.map(\.id)   // [a, b, c, d]

        sut.removeTracks([ids[1], ids[3]])         // remove b and d

        XCTAssertEqual(sut.playlist.tracks.map(\.id), [ids[0], ids[2]])  // [a, c]
    }

    /// Design (9-X D1): removing a batch that includes the playing track
    /// stops playback. currentTrack is cleared asynchronously via Task.
    func testRemoveTracks_IncludingCurrentTrack_StopsPlayback() async {
        await sut.load(urls: makeURLs(["a", "b"]))
        let ids = sut.playlist.tracks.map(\.id)
        await sut.play(trackID: ids[0])
        XCTAssertNotNil(sut.currentTrack)           // pre-condition

        sut.removeTracks([ids[0], ids[1]])

        // Allow async stop Task inside removeTracks to complete.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(sut.playlist.tracks.isEmpty)
        XCTAssertNil(sut.currentTrack)
        XCTAssertEqual(sut.playbackState, .stopped)
    }

    func testRemoveTracks_ExcludingCurrentTrack_KeepsCurrentTrack() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let tracks = sut.playlist.tracks
        await sut.play(trackID: tracks[0].id)

        sut.removeTracks([tracks[1].id, tracks[2].id])

        // The two non-playing tracks are gone...
        XCTAssertEqual(sut.playlist.tracks.map(\.id), [tracks[0].id])
        // ...and the playing track is kept.
        XCTAssertEqual(sut.currentTrack, tracks[0])
    }

    // MARK: - moveTrack(fromOffsets:toOffset:)

    func testMoveTrack_ValidIndices_Reorders() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let originalFirstID = sut.playlist.tracks[0].id

        // [A, B, C] → [B, C, A]
        sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(sut.playlist.tracks.last?.id, originalFirstID)
    }
}

// MARK: - playNext(trackID:) — "Play Next" context menu action

extension AppStatePlaylistTests {

    func testPlayNext_MovesTrackAfterCurrentTrack() async {
        // Given: playlist [A, B, C], playing A
        let urls = makeURLs(["a", "b", "c"])
        await sut.load(urls: urls)
        let trackA = sut.playlist.tracks[0]
        let trackC = sut.playlist.tracks[2]
        await sut.play(trackID: trackA.id)

        // When: Play Next on C
        sut.playNext(trackC.id)

        // Then: order is [A, C, B]
        XCTAssertEqual(sut.playlist.tracks.map { $0.url.lastPathComponent },
                       ["a.mp3", "c.mp3", "b.mp3"])
    }

    func testPlayNext_UpdatesInsertionOrder() async {
        // Given: playlist [A, B, C], playing A
        let urls = makeURLs(["a", "b", "c"])
        await sut.load(urls: urls)
        let trackA = sut.playlist.tracks[0]
        let trackC = sut.playlist.tracks[2]
        await sut.play(trackID: trackA.id)

        // When: Play Next on C
        sut.playNext(trackC.id)

        // Then: insertionOrder matches tracks
        XCTAssertEqual(sut.playlist.insertionOrder,
                       sut.playlist.tracks.map { $0.id },
                       "insertionOrder must stay in sync with tracks after playNext")
    }

    func testPlayNext_PersistsOrderAfterSaveAndRestore() async {
        // Given: playlist [A, B, C], playing A
        let urls = makeURLs(["a", "b", "c"])
        await sut.load(urls: urls)
        let trackA = sut.playlist.tracks[0]
        let trackC = sut.playlist.tracks[2]
        await sut.play(trackID: trackA.id)

        // When: Play Next on C, then save
        sut.playNext(trackC.id)

        // Then: a fresh AppState restoring from same UserDefaults sees same order
        let restored = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: testDefaults,
            playlistStore: testPlaylistStore
        )
        XCTAssertEqual(restored.playlist.tracks.map { $0.url.lastPathComponent },
                       ["a.mp3", "c.mp3", "b.mp3"],
                       "playNext order must survive app relaunch via saveState()")
    }

    func testPlayNext_NoCurrentTrack_InsertsAtFront() async {
        // Given: playlist [A, B, C], nothing playing
        let urls = makeURLs(["a", "b", "c"])
        await sut.load(urls: urls)
        let trackC = sut.playlist.tracks[2]

        // When: Play Next (no current track → currentIndex == -1 → insertIndex == 0)
        sut.playNext(trackC.id)

        // Then: C moves to front
        XCTAssertEqual(sut.playlist.tracks[0].url.lastPathComponent, "c.mp3")
    }

    // MARK: - isPerformingBlockingOperation

    func testIsPerformingBlockingOperation_InitiallyFalse() {
        XCTAssertFalse(sut.isPerformingBlockingOperation)
    }

    func testLoad_ResetsBlockingFlagOnCompletion() async {
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertFalse(sut.isPerformingBlockingOperation,
                       "Flag must be reset after load(urls:) completes")
    }

    func testImportPlaylist_ResetsBlockingFlagOnCompletion() async {
        // importPlaylist with a non-existent file hits the early return guard.
        // defer must still reset the flag.
        await sut.importPlaylist(from: URL(fileURLWithPath: "/tmp/nonexistent.m3u8"))
        XCTAssertFalse(sut.isPerformingBlockingOperation,
                       "Flag must be reset after importPlaylist completes (even on error path)")
    }

    // MARK: - Slice 9-M Layer 2: bookmark capture during load (green-phase)

    /// 9-M green-phase regression test.
    /// Verifies that `AppState.load(urls:)` produces a Track whose URL
    /// roundtrips through encode/decode and remains accessible. Indirectly
    /// confirms that per-iteration `startAccessingSecurityScopedResource`
    /// fires correctly during load — fake-recorder swizzling is not used
    /// because URL is a Swift value type and the start/stop methods are
    /// ObjC instance methods on NSURL whose interception requires
    /// invasive runtime patches not warranted for this slice.
    func testAppStatePlaylistLoad_BookmarkCapturedAfterLoad() async throws {
        // Build a real on-disk file in a temp dir so the bookmark can be
        // generated. FakeTagReaderService default returns Track(url: url),
        // so the Track gets a real-ish url. saveState() inside load(urls:)
        // encodes the playlist, exercising the encode path under [.withSecurityScope].
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateLoadTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realFile = tempDir.appendingPathComponent("track.mp3")
        try Data("audio-bytes".utf8).write(to: realFile)

        await sut.load(urls: [realFile])

        XCTAssertEqual(sut.playlists[0].tracks.count, 1,
            "load(urls:) must add exactly one track for a single valid URL.")
        XCTAssertEqual(sut.playlists[0].tracks[0].url, realFile,
            "Track URL must match the input URL exactly.")
        XCTAssertTrue(sut.playlists[0].tracks[0].isAccessible,
            "Newly loaded track with real on-disk file must be accessible.")

        // Roundtrip encode/decode the track to confirm the security-scoped
        // bookmark was captured during load and survives serialisation.
        let encoded = try JSONEncoder().encode(sut.playlists[0].tracks[0])
        let restored = try JSONDecoder().decode(Track.self, from: encoded)
        XCTAssertEqual(restored.url, realFile,
            "URL must roundtrip through encode/decode under .withSecurityScope.")
        XCTAssertTrue(restored.isAccessible,
            "Restored track must remain accessible (bookmark resolves AND "
            + "startAccessingSecurityScopedResource succeeds).")
    }
}
