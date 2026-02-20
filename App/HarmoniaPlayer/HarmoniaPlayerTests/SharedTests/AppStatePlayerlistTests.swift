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
@MainActor
final class AppStatePlaylistTests: XCTestCase {

    // MARK: - SUT

    private var sut: AppState!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        sut = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider()
        )
    }

    override func tearDown() async throws {
        sut = nil
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

    func testLoad_EmptyPlaylist_AddsTrack() {
        sut.load(urls: makeURLs(["song"]))

        XCTAssertEqual(sut.playlist.count, 1)
    }

    func testLoad_ExistingPlaylist_AppendsTrack() {
        sut.load(urls: makeURLs(["a"]))
        sut.load(urls: makeURLs(["b"]))

        XCTAssertEqual(sut.playlist.count, 2)
    }

    func testLoad_MultipleURLs_AddsAll() {
        sut.load(urls: makeURLs(["a", "b"]))

        XCTAssertEqual(sut.playlist.count, 2)
    }

    func testLoad_DerivesTitleFromFilename() {
        sut.load(urls: [URL(fileURLWithPath: "/tmp/my-song.mp3")])

        XCTAssertEqual(sut.playlist.tracks.first?.title, "my-song")
    }

    // MARK: - clearPlaylist()

    func testClearPlaylist_WithTracks_EmptiesPlaylist() {
        sut.load(urls: makeURLs(["a", "b", "c"]))

        sut.clearPlaylist()

        XCTAssertTrue(sut.playlist.isEmpty)
    }

    func testClearPlaylist_NilsCurrentTrack() {
        sut.load(urls: makeURLs(["a"]))
        sut.play(trackID: sut.playlist.tracks[0].id)
        XCTAssertNotNil(sut.currentTrack)           // pre-condition

        sut.clearPlaylist()

        XCTAssertNil(sut.currentTrack)
    }

    // MARK: - removeTrack(_:)

    func testRemoveTrack_ExistingID_RemovesTrack() {
        sut.load(urls: makeURLs(["a", "b", "c"]))
        let targetID = sut.playlist.tracks[1].id

        sut.removeTrack(targetID)

        XCTAssertEqual(sut.playlist.count, 2)
        XCTAssertFalse(sut.playlist.tracks.contains { $0.id == targetID })
    }

    func testRemoveTrack_InvalidID_NoChange() {
        sut.load(urls: makeURLs(["a", "b", "c"]))

        sut.removeTrack(UUID())

        XCTAssertEqual(sut.playlist.count, 3)
    }

    func testRemoveTrack_CurrentTrack_NilsCurrentTrack() {
        sut.load(urls: makeURLs(["a"]))
        let id = sut.playlist.tracks[0].id
        sut.play(trackID: id)
        XCTAssertNotNil(sut.currentTrack)           // pre-condition

        sut.removeTrack(id)

        XCTAssertNil(sut.currentTrack)
    }

    func testRemoveTrack_OtherTrack_KeepsCurrentTrack() {
        sut.load(urls: makeURLs(["a", "b"]))
        let trackA = sut.playlist.tracks[0]
        let trackBID = sut.playlist.tracks[1].id
        sut.play(trackID: trackA.id)

        sut.removeTrack(trackBID)

        XCTAssertEqual(sut.currentTrack, trackA)
    }

    // MARK: - moveTrack(fromOffsets:toOffset:)

    func testMoveTrack_ValidIndices_Reorders() {
        sut.load(urls: makeURLs(["a", "b", "c"]))
        let originalFirstID = sut.playlist.tracks[0].id

        // [A, B, C] → [B, C, A]
        sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(sut.playlist.tracks.last?.id, originalFirstID)
    }
}
