//
//  AppStateDragReorderTests.swift
//  HarmoniaPlayerTests
//
//  Drag-to-Reorder behaviour in AppState (Slice 7-D)
//

import XCTest
@testable import HarmoniaPlayer

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
}
