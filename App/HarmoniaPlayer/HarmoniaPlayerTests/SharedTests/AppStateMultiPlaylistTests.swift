//
//  AppStateMultiPlaylistTests.swift
//  HarmoniaPlayerTests
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState multiple playlist management.
///
/// Verifies `newPlaylist(name:)`, `renamePlaylist(at:name:)`,
/// `deletePlaylist(at:)`, and playlist switching behaviour.
@MainActor
final class AppStateMultiPlaylistTests: XCTestCase {

    // MARK: - Fixtures

    private var fakeService: FakePlaybackService!
    private var provider: FakeCoreProvider!
    private var sut: AppState!

    override func setUp() async throws {
        try await super.setUp()
        fakeService = FakePlaybackService()
        provider = FakeCoreProvider(playbackService: fakeService)
        sut = AppState(iapManager: MockIAPManager(), provider: provider)
    }

    override func tearDown() async throws {
        sut = nil
        provider = nil
        fakeService = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_HasOnePlaylist() {
        XCTAssertEqual(sut.playlists.count, 1)
    }

    func testInitialState_ActiveIndexIsZero() {
        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    func testPlaylist_ComputedReturnsActive() {
        sut.newPlaylist(name: "Rock")
        sut.activePlaylistIndex = 1
        XCTAssertEqual(sut.playlist, sut.playlists[1])
    }

    // MARK: - newPlaylist

    func testNewPlaylist_IncreasesCount() {
        sut.newPlaylist(name: "Rock")
        XCTAssertEqual(sut.playlists.count, 2)
    }

    func testNewPlaylist_SetsActiveIndex() {
        sut.newPlaylist(name: "Rock")
        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    func testNewPlaylist_EmptyName_UsesDefault() {
        sut.newPlaylist(name: "")
        XCTAssertEqual(sut.playlists[1].name, "Playlist 2")
    }

    // MARK: - renamePlaylist

    func testRenamePlaylist_UpdatesName() {
        sut.renamePlaylist(at: 0, name: "Jazz")
        XCTAssertEqual(sut.playlists[0].name, "Jazz")
    }

    func testRenamePlaylist_OutOfRange_NoOp() {
        let before = sut.playlists.count
        sut.renamePlaylist(at: 99, name: "X")
        XCTAssertEqual(sut.playlists.count, before)
    }

    // MARK: - deletePlaylist

    func testDeletePlaylist_DecreasesCount() {
        sut.newPlaylist(name: "Rock")
        sut.deletePlaylist(at: 1)
        XCTAssertEqual(sut.playlists.count, 1)
    }

    func testDeletePlaylist_LastOne_AutoInsertsSession() {
        sut.deletePlaylist(at: 0)
        XCTAssertEqual(sut.playlists.count, 1)
        XCTAssertEqual(sut.playlists[0].name, "Playlist 1")
    }

    func testDeletePlaylist_LastOne_ActiveIndexStaysZero() {
        sut.deletePlaylist(at: 0)
        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    func testDeletePlaylist_AdjustsActiveIndex_WhenDeletingActive() {
        sut.newPlaylist(name: "Rock")
        sut.activePlaylistIndex = 1
        sut.deletePlaylist(at: 1)
        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    func testDeletePlaylist_DecrementsActiveIndex_WhenDeletingBeforeActive() {
        sut.newPlaylist(name: "Rock")
        sut.newPlaylist(name: "Jazz")
        sut.activePlaylistIndex = 2
        sut.deletePlaylist(at: 0)
        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    func testDeletePlaylist_OutOfRange_NoOp() {
        let before = sut.playlists.count
        sut.deletePlaylist(at: 99)
        XCTAssertEqual(sut.playlists.count, before)
    }

    // MARK: - Playback continuity on switch

    func testSwitchPlaylist_DoesNotStopPlayback() async {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await sut.load(urls: [url])
        await sut.play()
        sut.newPlaylist(name: "Rock")

        sut.activePlaylistIndex = 1

        XCTAssertEqual(sut.playbackState, .playing)
    }
}
