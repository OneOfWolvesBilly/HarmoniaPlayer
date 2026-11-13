//
//  PlaylistCollectionTabTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the playlist-tab management of `PlaylistCollection`:
/// `newPlaylist(name:)`, `renamePlaylist(at:name:)`, `deletePlaylist(at:)`,
/// `switchPlaylist(to:)`, the initial state, and the delete notification.
@MainActor
final class PlaylistCollectionTabTests: XCTestCase {

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

    private func makeSUT() -> PlaylistCollection {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        return PlaylistCollection(
            tagReaderService: FakeTagReaderService(),
            fileDropService: FileDropService(),
            playlistStore: FakePlaylistStore(),
            undoManager: UndoManager(),
            alertCenter: AlertCenter(),
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
    }

    // MARK: - Initial State

    func testInitial_PlaylistIsEmpty() {
        let sut = makeSUT()
        XCTAssertTrue(sut.playlist.isEmpty)
    }

    func testInitialState_HasOnePlaylist() {
        let sut = makeSUT()
        XCTAssertEqual(sut.playlists.count, 1)
    }

    func testInitialState_ActiveIndexIsZero() {
        let sut = makeSUT()
        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    func testPlaylist_ComputedReturnsActive() throws {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        sut.activePlaylistIndex = 1
        XCTAssertEqual(sut.playlist, try XCTUnwrap(sut.playlists[safe: 1]))
    }

    // MARK: - newPlaylist

    func testNewPlaylist_IncreasesCount() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        XCTAssertEqual(sut.playlists.count, 2)
    }

    func testNewPlaylist_SetsActiveIndex() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    func testNewPlaylist_EmptyName_UsesDefault() {
        let sut = makeSUT()
        sut.newPlaylist(name: "")
        XCTAssertEqual(sut.playlists[safe: 1]?.name, "Playlist 2")
    }

    // MARK: - renamePlaylist

    func testRenamePlaylist_UpdatesName() {
        let sut = makeSUT()
        sut.renamePlaylist(at: 0, name: "Jazz")
        XCTAssertEqual(sut.playlists[0].name, "Jazz")
    }

    func testRenamePlaylist_OutOfRange_NoOp() {
        let sut = makeSUT()
        let before = sut.playlists.count
        sut.renamePlaylist(at: 99, name: "X")
        XCTAssertEqual(sut.playlists.count, before)
    }

    // MARK: - deletePlaylist

    func testDeletePlaylist_DecreasesCount() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        sut.deletePlaylist(at: 1)
        XCTAssertEqual(sut.playlists.count, 1)
    }

    func testDeletePlaylist_LastOne_AutoInsertsPlaylist1() {
        let sut = makeSUT()
        sut.deletePlaylist(at: 0)
        XCTAssertEqual(sut.playlists.count, 1)
        XCTAssertEqual(sut.playlists[0].name, "Playlist 1")
    }

    func testDeletePlaylist_LastOne_ActiveIndexStaysZero() {
        let sut = makeSUT()
        sut.deletePlaylist(at: 0)
        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    func testDeletePlaylist_AdjustsActiveIndex_WhenDeletingActive() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        sut.activePlaylistIndex = 1
        sut.deletePlaylist(at: 1)
        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    func testDeletePlaylist_DecrementsActiveIndex_WhenDeletingBeforeActive() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        sut.newPlaylist(name: "Jazz")
        sut.activePlaylistIndex = 2
        sut.deletePlaylist(at: 0)
        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    func testDeletePlaylist_OutOfRange_NoOp() {
        let sut = makeSUT()
        let before = sut.playlists.count
        sut.deletePlaylist(at: 99)
        XCTAssertEqual(sut.playlists.count, before)
    }

    // MARK: - switchPlaylist(to:)

    /// Switching to a valid different index updates activePlaylistIndex.
    func testSwitchPlaylist_ValidIndex_ChangesActiveIndex() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")

        sut.switchPlaylist(to: 1)

        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    /// Switching to the current index is a no-op: activePlaylistIndex unchanged.
    func testSwitchPlaylist_SameIndex_IsNoOp() {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        sut.switchPlaylist(to: 1)
        XCTAssertEqual(sut.activePlaylistIndex, 1, "Pre-condition")

        sut.switchPlaylist(to: 1)

        XCTAssertEqual(sut.activePlaylistIndex, 1)
    }

    /// Switching to the same index must NOT clear the undo stack.
    func testSwitchPlaylist_SameIndex_PreservesUndoStack() async {
        let sut = makeSUT()
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertTrue(sut.canUndo, "Pre-condition: undo stack should be populated")

        sut.switchPlaylist(to: 0)   // same index

        XCTAssertTrue(sut.canUndo, "Undo stack must survive a same-index switch")
    }

    /// Switching to an out-of-range index is a no-op.
    func testSwitchPlaylist_OutOfRangeIndex_IsNoOp() {
        let sut = makeSUT()

        sut.switchPlaylist(to: 99)

        XCTAssertEqual(sut.activePlaylistIndex, 0)
    }

    /// Switching to a different index clears the undo stack.
    func testSwitchPlaylist_DifferentIndex_ClearsUndoStack() async {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")       // lands on index 1, clears undo stack
        sut.switchPlaylist(to: 0)           // back to index 0, clears undo stack
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertTrue(sut.canUndo, "Pre-condition: undo stack should be populated")
        XCTAssertEqual(sut.activePlaylistIndex, 0, "Pre-condition: should be on playlist 0")

        sut.switchPlaylist(to: 1)

        XCTAssertFalse(sut.canUndo,
                       "Undo stack must be cleared after switching to a different playlist")
    }

    // MARK: - onPlaylistDeleted

    func testDeletePlaylist_CallsOnPlaylistDeletedWithID() throws {
        let sut = makeSUT()
        sut.newPlaylist(name: "Rock")
        let deletedID = try XCTUnwrap(sut.playlists[safe: 1]).id
        var received: [Playlist.ID] = []
        sut.onPlaylistDeleted = { received.append($0) }

        sut.deletePlaylist(at: 1)

        XCTAssertEqual(received, [deletedID])
    }

    func testDeletePlaylist_OutOfRange_DoesNotCallOnPlaylistDeleted() {
        let sut = makeSUT()
        var callCount = 0
        sut.onPlaylistDeleted = { _ in callCount += 1 }

        sut.deletePlaylist(at: 99)

        XCTAssertEqual(callCount, 0)
    }
}
