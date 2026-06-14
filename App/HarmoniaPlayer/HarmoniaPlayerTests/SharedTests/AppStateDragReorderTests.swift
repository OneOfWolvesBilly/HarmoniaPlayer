//
//  AppStateDragReorderTests.swift
//  HarmoniaPlayerTests
//
//  Drag-to-Reorder behaviour in AppState (Slice 7-D)
//

import XCTest
@testable import Harmonia_Player

// MARK: - Helpers

private func makeURLs(_ names: [String]) -> [URL] {
    names.map { URL(fileURLWithPath: "/tmp/\($0).mp3") }
}

// MARK: - Test Suite

/// Tests that moveTrack() keeps insertionOrder in sync with tracks.
///
/// @MainActor required because AppState is @MainActor isolated.
@MainActor
final class AppStateDragReorderTests: XCTestCase {

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
            userDefaults: testDefaults,
            playlistStore: FakePlaylistStore()
        )
    }

    override func tearDown() async throws {
        sut = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - moveTrack insertionOrder sync

    /// Moving C from last → first must update insertionOrder to [C, A, B].
    func testMoveTrack_UpdatesInsertionOrder() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let ids = sut.playlist.tracks.map { $0.id }   // [A, B, C]

        // Move index 2 (C) → before index 0
        sut.moveTrack(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let expected = [ids[2], ids[0], ids[1]]        // [C, A, B]
        XCTAssertEqual(sut.playlist.insertionOrder, expected)
    }

    /// After any move, insertionOrder must equal tracks.map(\.id).
    func testMoveTrack_InsertionOrder_MatchesTracks() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))

        // Move index 0 (A) → after last item
        sut.moveTrack(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let trackIDs = sut.playlist.tracks.map { $0.id }
        XCTAssertEqual(sut.playlist.insertionOrder, trackIDs)
    }

    // MARK: - moveTrack(id:before:) — drag reorder entry point

    /// Move C before A: [A, B, C] → [C, A, B].
    func testMoveTrackIDBefore_MovesDraggedBeforeTarget() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let ids = sut.playlist.tracks.map(\.id)        // [A, B, C]

        sut.moveTrack(id: ids[2], before: ids[0])      // C before A

        XCTAssertEqual(sut.playlist.tracks.map(\.id), [ids[2], ids[0], ids[1]])  // [C, A, B]
    }

    /// A nil target appends the dragged track to the end: [A, B, C] → [B, C, A].
    func testMoveTrackIDBefore_NilTarget_AppendsToEnd() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let ids = sut.playlist.tracks.map(\.id)        // [A, B, C]

        sut.moveTrack(id: ids[0], before: nil)         // A to the end

        XCTAssertEqual(sut.playlist.tracks.map(\.id), [ids[1], ids[2], ids[0]])  // [B, C, A]
    }

    /// insertionOrder follows the new visible order after a drag reorder.
    func testMoveTrackIDBefore_KeepsInsertionOrderInSync() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let ids = sut.playlist.tracks.map(\.id)        // [A, B, C]

        sut.moveTrack(id: ids[2], before: ids[0])      // C before A

        XCTAssertEqual(sut.playlist.insertionOrder, [ids[2], ids[0], ids[1]])    // [C, A, B]
        XCTAssertEqual(sut.playlist.insertionOrder, sut.playlist.tracks.map(\.id))
    }

    /// Disabled while a column sort is active (sortKey != .none): order unchanged.
    func testMoveTrackIDBefore_NoOpWhenColumnSortActive() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let ids = sut.playlist.tracks.map(\.id)        // [A, B, C]
        sut.playlists[sut.activePlaylistIndex].sortKey = .title   // a column sort is active

        sut.moveTrack(id: ids[2], before: ids[0])      // attempt C before A

        XCTAssertEqual(sut.playlist.tracks.map(\.id), ids)        // unchanged
    }

    /// Dropping a row onto itself is a no-op.
    func testMoveTrackIDBefore_DropOntoSelf_NoOp() async {
        await sut.load(urls: makeURLs(["a", "b", "c"]))
        let ids = sut.playlist.tracks.map(\.id)

        sut.moveTrack(id: ids[1], before: ids[1])      // drop B onto itself

        XCTAssertEqual(sut.playlist.tracks.map(\.id), ids)        // unchanged
    }
}
