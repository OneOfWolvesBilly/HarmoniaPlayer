//
//  PlaylistCollectionTrackTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the per-track operations of `PlaylistCollection`: clear,
/// remove, batch remove, reorder, play-next ordering, the File Info
/// request, and the notifications each mutation emits.
@MainActor
final class PlaylistCollectionTrackTests: XCTestCase {

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
        let alertCenter: AlertCenter
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let alertCenter = AlertCenter()
        let sut = PlaylistCollection(
            tagReaderService: FakeTagReaderService(),
            fileDropService: FileDropService(),
            playlistStore: FakePlaylistStore(),
            undoManager: UndoManager(),
            alertCenter: alertCenter,
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        return Fixture(sut: sut, alertCenter: alertCenter)
    }

    private func makeURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0).mp3") }
    }

    /// Loads the named tracks and returns their ids in playlist order.
    private func loadTracks(_ names: [String], into f: Fixture) async -> [Track.ID] {
        await f.sut.load(urls: makeURLs(names))
        return f.sut.playlist.tracks.map(\.id)
    }

    private func id(_ index: Int, in f: Fixture) throws -> Track.ID {
        try XCTUnwrap(f.sut.playlist.tracks[safe: index]).id
    }

    // MARK: - clearPlaylist()

    func testClearPlaylist_WithTracks_EmptiesPlaylist() async {
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)

        f.sut.clearPlaylist()

        XCTAssertTrue(f.sut.playlist.isEmpty)
    }

    // MARK: - removeTrack(_:)

    func testRemoveTrack_ExistingID_RemovesTrack() async throws {
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)
        let targetID = try id(1, in: f)

        f.sut.removeTrack(targetID)

        XCTAssertEqual(f.sut.playlist.count, 2)
        XCTAssertFalse(f.sut.playlist.tracks.contains { $0.id == targetID })
    }

    func testRemoveTrack_InvalidID_NoChange() async {
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)

        f.sut.removeTrack(UUID())

        XCTAssertEqual(f.sut.playlist.count, 3)
    }

    // MARK: - removeTracks(_:)

    func testRemoveTracks_AllSelected_EmptiesPlaylist() async {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)

        f.sut.removeTracks(Set(ids))

        XCTAssertTrue(f.sut.playlist.isEmpty)
    }

    func testRemoveTracks_Subset_RemovesOnlySelectedKeepsOrder() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c", "d"], into: f)   // [a, b, c, d]
        let b = try XCTUnwrap(ids[safe: 1])
        let d = try XCTUnwrap(ids[safe: 3])

        f.sut.removeTracks([b, d])                                    // remove b and d

        XCTAssertEqual(f.sut.playlist.tracks.map(\.id), [ids[0], ids[2]])  // [a, c]
    }

    // MARK: - moveTrack(fromOffsets:toOffset:)

    func testMoveTrack_ValidIndices_Reorders() async throws {
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)
        let originalFirstID = try id(0, in: f)

        // [A, B, C] → [B, C, A]
        f.sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(f.sut.playlist.tracks.last?.id, originalFirstID)
    }

    // MARK: - playNext(_:afterCurrent:)

    func testPlayNext_MovesTrackAfterCurrentTrack() async throws {
        // Given: playlist [A, B, C], A is the current track
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)
        let trackA = try id(0, in: f)
        let trackC = try id(2, in: f)

        // When: Play Next on C
        f.sut.playNext(trackC, afterCurrent: trackA)

        // Then: order is [A, C, B]
        XCTAssertEqual(f.sut.playlist.tracks.map { $0.url.lastPathComponent },
                       ["a.mp3", "c.mp3", "b.mp3"])
    }

    func testPlayNext_UpdatesInsertionOrder() async throws {
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)
        let trackA = try id(0, in: f)
        let trackC = try id(2, in: f)

        f.sut.playNext(trackC, afterCurrent: trackA)

        XCTAssertEqual(f.sut.playlist.insertionOrder,
                       f.sut.playlist.tracks.map { $0.id },
                       "insertionOrder must stay in sync with tracks after playNext")
    }

    func testPlayNext_NoCurrentTrack_InsertsAtFront() async throws {
        // Given: playlist [A, B, C], nothing playing
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)
        let trackC = try id(2, in: f)

        // When: Play Next (no current track → insert at index 0)
        f.sut.playNext(trackC, afterCurrent: nil)

        // Then: C moves to front
        XCTAssertEqual(f.sut.playlist.tracks.first?.url.lastPathComponent, "c.mp3")
    }

    // MARK: - moveTrack insertionOrder sync

    /// Moving C from last → first must update insertionOrder to [C, A, B].
    func testMoveTrack_UpdatesInsertionOrder() async {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)   // [A, B, C]

        f.sut.moveTrack(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(f.sut.playlist.insertionOrder, [ids[safe: 2], ids[safe: 0], ids[safe: 1]].compactMap { $0 })
    }

    /// After any move, insertionOrder must equal tracks.map(\.id).
    func testMoveTrack_InsertionOrder_MatchesTracks() async {
        let f = makeSUT()
        _ = await loadTracks(["a", "b", "c"], into: f)

        f.sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(f.sut.playlist.insertionOrder, f.sut.playlist.tracks.map { $0.id })
    }

    // MARK: - moveTrack(id:before:) — drag reorder entry point

    /// Move C before A: [A, B, C] → [C, A, B].
    func testMoveTrackIDBefore_MovesDraggedBeforeTarget() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(ids[safe: 0]), c = try XCTUnwrap(ids[safe: 2])

        f.sut.moveTrack(id: c, before: a)

        XCTAssertEqual(f.sut.playlist.tracks.map(\.id), [ids[2], ids[0], ids[1]])
    }

    /// A nil target appends the dragged track to the end: [A, B, C] → [B, C, A].
    func testMoveTrackIDBefore_NilTarget_AppendsToEnd() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(ids[safe: 0])

        f.sut.moveTrack(id: a, before: nil)

        XCTAssertEqual(f.sut.playlist.tracks.map(\.id), [ids[1], ids[2], ids[0]])
    }

    /// insertionOrder follows the new visible order after a drag reorder.
    func testMoveTrackIDBefore_KeepsInsertionOrderInSync() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(ids[safe: 0]), c = try XCTUnwrap(ids[safe: 2])

        f.sut.moveTrack(id: c, before: a)

        XCTAssertEqual(f.sut.playlist.insertionOrder, [ids[2], ids[0], ids[1]])
        XCTAssertEqual(f.sut.playlist.insertionOrder, f.sut.playlist.tracks.map(\.id))
    }

    /// Disabled while a column sort is active (sortKey != .none): order unchanged.
    func testMoveTrackIDBefore_NoOpWhenColumnSortActive() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(ids[safe: 0]), c = try XCTUnwrap(ids[safe: 2])
        f.sut.playlists[f.sut.activePlaylistIndex].sortKey = .title

        f.sut.moveTrack(id: c, before: a)

        XCTAssertEqual(f.sut.playlist.tracks.map(\.id), ids)
    }

    /// Dropping a row onto itself is a no-op.
    func testMoveTrackIDBefore_DropOntoSelf_NoOp() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let b = try XCTUnwrap(ids[safe: 1])

        f.sut.moveTrack(id: b, before: b)

        XCTAssertEqual(f.sut.playlist.tracks.map(\.id), ids)
    }

    // MARK: - showFileInfo(trackID:)

    func testShowFileInfo_SetsAlertCenterTrack() async throws {
        let f = makeSUT()
        _ = await loadTracks(["a"], into: f)
        let loadedID = try id(0, in: f)

        f.sut.showFileInfo(trackID: loadedID)

        XCTAssertEqual(f.alertCenter.fileInfoTrack?.id, loadedID,
                       "showFileInfo(trackID:) must set alertCenter.fileInfoTrack to the matching track")
    }

    func testShowFileInfo_UnknownID_NoOp() {
        let f = makeSUT()
        XCTAssertTrue(f.sut.playlist.tracks.isEmpty, "Precondition: playlist must be empty")

        f.sut.showFileInfo(trackID: UUID())

        XCTAssertNil(f.alertCenter.fileInfoTrack,
                     "showFileInfo(trackID:) with a non-matching ID must leave alertCenter.fileInfoTrack nil")
    }

    // MARK: - Notifications

    func testRemoveTrack_CallsOnTrackRemoved() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b"], into: f)
        let a = try XCTUnwrap(ids[safe: 0])
        var received: [Track.ID] = []
        f.sut.onTrackRemoved = { received.append($0) }

        f.sut.removeTrack(a)

        XCTAssertEqual(received, [a])
    }

    func testRemoveTrack_UnknownID_DoesNotCallOnTrackRemoved() async {
        let f = makeSUT()
        _ = await loadTracks(["a"], into: f)
        var callCount = 0
        f.sut.onTrackRemoved = { _ in callCount += 1 }

        f.sut.removeTrack(UUID())

        XCTAssertEqual(callCount, 0)
    }

    func testRemoveTracks_CallsOnTracksRemovedWithMatchingIDs() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(ids[safe: 0]), c = try XCTUnwrap(ids[safe: 2])
        var received: [Set<Track.ID>] = []
        f.sut.onTracksRemoved = { received.append($0) }

        f.sut.removeTracks([a, c, UUID()])

        XCTAssertEqual(received, [[a, c]])
    }

    func testRemoveTracks_NoMatch_DoesNotCallOnTracksRemoved() async {
        let f = makeSUT()
        _ = await loadTracks(["a"], into: f)
        var callCount = 0
        f.sut.onTracksRemoved = { _ in callCount += 1 }

        f.sut.removeTracks([UUID()])

        XCTAssertEqual(callCount, 0)
    }

    func testClearPlaylist_CallsOnPlaylistCleared() async {
        let f = makeSUT()
        _ = await loadTracks(["a"], into: f)
        var callCount = 0
        f.sut.onPlaylistCleared = { callCount += 1 }

        f.sut.clearPlaylist()

        XCTAssertEqual(callCount, 1)
    }

    func testPlayNext_CallsOnTrackQueuedNext() async throws {
        let f = makeSUT()
        let ids = await loadTracks(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(ids[safe: 0]), c = try XCTUnwrap(ids[safe: 2])
        var received: [Track.ID] = []
        f.sut.onTrackQueuedNext = { received.append($0) }

        f.sut.playNext(c, afterCurrent: a)

        XCTAssertEqual(received, [c])
    }
}
