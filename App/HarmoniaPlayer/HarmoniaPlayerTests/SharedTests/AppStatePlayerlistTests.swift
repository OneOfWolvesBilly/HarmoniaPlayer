//
//  AppStatePlaylistTests.swift
//  HarmoniaPlayerTests
//
//  Playlist Operations in AppState
//

import XCTest
@testable import HarmoniaPlayer

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
    private var suiteName: String!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        sut = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: testDefaults
        )
    }

    override func tearDown() async throws {
        sut = nil
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

    // MARK: - moveTrack(fromOffsets:toOffset:)

    func testMoveTrack_ValidIndices_Reorders() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let originalFirstID = sut.playlist.tracks[0].id

        // [A, B, C] → [B, C, A]
        sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(sut.playlist.tracks.last?.id, originalFirstID)
    }
}
