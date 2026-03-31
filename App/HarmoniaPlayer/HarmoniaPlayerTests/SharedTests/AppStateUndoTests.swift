//
//  AppStateUndoTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  SPDX-License-Identifier: MIT
//
//  Slice 8-A — UndoManager support for playlist operations.
//
//  Tests cover:
//    - load(urls:)       undo removes added tracks; redo re-adds them
//    - removeTrack(_:)   undo re-inserts the track at original index
//    - moveTrack(...)    undo restores previous order
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStateUndoTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a testable AppState with an injected UndoManager.
    private func makeSUT(
        undoManager: UndoManager? = nil
    ) -> (sut: AppState, undoManager: UndoManager) {
        let resolvedUndoManager = undoManager ?? UndoManager()
        let provider = FakeCoreProvider()
        let sut = AppState(
            iapManager: MockIAPManager(),
            provider: provider,
            undoManager: resolvedUndoManager
        )
        return (sut, resolvedUndoManager)
    }

    /// Convenience: a file URL under /tmp.
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    // MARK: - load(urls:) — undo / redo

    /// Given: empty playlist
    /// When:  load(urls: [1 track]) then undo
    /// Then:  playlist.tracks is empty again
    func testUndoLoad_RemovesAddedTracks() async {
        let (sut, um) = makeSUT()
        await sut.load(urls: [url("track1")])
        XCTAssertEqual(sut.playlist.tracks.count, 1)

        um.undo()

        XCTAssertTrue(sut.playlist.tracks.isEmpty)
    }

    /// Given: empty playlist
    /// When:  load(urls: [3 tracks]) then undo
    /// Then:  playlist.tracks is empty again
    func testUndoLoad_WithMultipleTracks() async {
        let (sut, um) = makeSUT()
        await sut.load(urls: [url("a"), url("b"), url("c")])
        XCTAssertEqual(sut.playlist.tracks.count, 3)

        um.undo()

        XCTAssertTrue(sut.playlist.tracks.isEmpty)
    }

    // MARK: - removeTrack(_:) — undo

    /// Given: playlist with 2 tracks
    /// When:  removeTrack(first) then undo
    /// Then:  tracks.count == 2 (track re-inserted)
    func testUndoRemoveTrack_ReInsertsTrack() async {
        let (sut, um) = makeSUT()
        await sut.load(urls: [url("x"), url("y")])
        let idToRemove = sut.playlist.tracks[0].id

        sut.removeTrack(idToRemove)
        XCTAssertEqual(sut.playlist.tracks.count, 1)

        um.undo()

        XCTAssertEqual(sut.playlist.tracks.count, 2)
    }

    // MARK: - moveTrack(fromOffsets:toOffset:) — undo

    /// Given: playlist [A, B, C]
    /// When:  move B (index 1) to end (offset 3) then undo
    /// Then:  order restored to [A, B, C]
    func testUndoMoveTrack_RestoresOrder() async {
        let (sut, um) = makeSUT()
        await sut.load(urls: [url("A"), url("B"), url("C")])
        let originalIDs = sut.playlist.tracks.map(\.id)

        // Move B (index 1) to after C (offset 3)
        sut.moveTrack(fromOffsets: IndexSet(integer: 1), toOffset: 3)
        XCTAssertNotEqual(sut.playlist.tracks.map(\.id), originalIDs,
                          "Order should have changed after move")

        um.undo()

        XCTAssertEqual(sut.playlist.tracks.map(\.id), originalIDs)
    }

    // MARK: - redo after undo

    /// Given: undo of load
    /// When:  redo
    /// Then:  tracks.count == 1 (re-added)
    func testRedoLoad_ReAddsTrack() async {
        let (sut, um) = makeSUT()
        await sut.load(urls: [url("solo")])

        um.undo()
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "Precondition: undo should have removed track")

        um.redo()

        XCTAssertEqual(sut.playlist.tracks.count, 1)
    }
}
