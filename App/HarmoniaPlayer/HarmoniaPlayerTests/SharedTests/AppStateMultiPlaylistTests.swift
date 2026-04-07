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
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        fakeService = FakePlaybackService()
        provider = FakeCoreProvider(playbackService: fakeService)
        sut = AppState(iapManager: MockIAPManager(), provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        sut = nil
        provider = nil
        fakeService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
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

    func testDeletePlaylist_LastOne_AutoInsertsPlaylist1() {
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

    // MARK: - switchPlaylist(to:)

    /// Switching to a valid different index updates activePlaylistIndex.
    func testSwitchPlaylist_ValidIndex_ChangesActiveIndex() {
        sut.newPlaylist(name: "Rock")

        sut.switchPlaylist(to: 1)

        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    /// Switching to the current index is a no-op: activePlaylistIndex unchanged.
    func testSwitchPlaylist_SameIndex_IsNoOp() {
        sut.newPlaylist(name: "Rock")
        sut.switchPlaylist(to: 1)
        XCTAssertEqual(sut.activePlaylistIndex, 1, "Pre-condition")

        sut.switchPlaylist(to: 1)

        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    /// Switching to the same index must NOT clear the undo stack.
    func testSwitchPlaylist_SameIndex_PreservesUndoStack() async {
        // Seed a track so load() registers an undo action.
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertTrue(sut.canUndo, "Pre-condition: undo stack should be populated")

        sut.switchPlaylist(to: 0)   // same index

        XCTAssertTrue(sut.canUndo, "Undo stack must survive a same-index switch")
    }

    /// Switching to an out-of-range index is a no-op.
    func testSwitchPlaylist_OutOfRangeIndex_IsNoOp() {
        sut.switchPlaylist(to: 99)

        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    /// Switching to a different index clears the undo stack.
    func testSwitchPlaylist_DifferentIndex_ClearsUndoStack() async {
        // Setup: create a second playlist, then switch back to playlist 0.
        // newPlaylist() itself clears the undo stack and lands on index 1,
        // so all setup must complete BEFORE the operation under test.
        sut.newPlaylist(name: "Rock")       // lands on index 1, clears undo stack
        sut.switchPlaylist(to: 0)           // back to index 0, clears undo stack

        // Seed a track in playlist 0 so load() registers an undo action.
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertTrue(sut.canUndo, "Pre-condition: undo stack should be populated")
        XCTAssertEqual(sut.activePlaylistIndex, 0, "Pre-condition: should be on playlist 0")

        // When: switch to a different playlist
        sut.switchPlaylist(to: 1)

        // Then: undo stack is cleared
        XCTAssertFalse(sut.canUndo,
                       "Undo stack must be cleared after switching to a different playlist")
    }
}
