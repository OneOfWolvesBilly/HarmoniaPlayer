//
//  AppStateUndoTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  SPDX-License-Identifier: MIT
//
//  Slice 8-A — UndoManager support for playlist operations.
//
//  UNIT TEST DESIGN
//  ----------------
//  Each test covers exactly ONE undo-registering operation:
//    - testUndoLoad:        load(urls:)
//    - testUndoRemoveTrack: removeTrack(_:)
//    - testUndoMoveTrack:   moveTrack(fromOffsets:toOffset:)
//    - testRedoLoad:        redo after undo of load
//
//  Test data setup uses seedTracks() which loads tracks then clears the
//  undo stack, ensuring only the operation under test is in the stack.
//  This avoids NSUndoManager groupsByEvent contamination between setup
//  and the operation being tested.
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStateUndoTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "hp-undo-test-\(UUID().uuidString)"
        createdSuiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func makeSUT() -> (sut: AppState, undoManager: UndoManager) {
        let um = UndoManager()
        let sut = AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: makeIsolatedDefaults(),
            undoManager: um
        )
        return (sut, um)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    /// Loads tracks into the playlist and clears the undo stack.
    ///
    /// Use this for test data setup so only the operation under test
    /// is registered in the undo stack. This prevents NSUndoManager
    /// groupsByEvent from grouping setup and the tested operation together.
    private func seedTracks(_ urls: [URL], into sut: AppState) async {
        await sut.load(urls: urls)
        sut.undoManager.removeAllActions()
    }

    // MARK: - load(urls:) — undo

    /// Given: empty playlist
    /// When:  load([track]) → undo
    /// Then:  playlist is empty
    func testUndoLoad_RemovesAddedTracks() async {
        let (sut, um) = makeSUT()

        await sut.load(urls: [url("track1")])
        XCTAssertEqual(sut.playlist.tracks.count, 1)

        um.undo()

        XCTAssertTrue(sut.playlist.tracks.isEmpty)
    }

    /// Given: empty playlist
    /// When:  load([3 tracks]) → undo
    /// Then:  playlist is empty
    func testUndoLoad_WithMultipleTracks() async {
        let (sut, um) = makeSUT()

        await sut.load(urls: [url("a"), url("b"), url("c")])
        XCTAssertEqual(sut.playlist.tracks.count, 3)

        um.undo()

        XCTAssertTrue(sut.playlist.tracks.isEmpty)
    }

    // MARK: - removeTrack(_:) — undo

    /// Given: playlist seeded with 2 tracks (undo stack clear)
    /// When:  removeTrack(first) → undo
    /// Then:  tracks.count == 2
    func testUndoRemoveTrack_ReInsertsTrack() async {
        let (sut, um) = makeSUT()
        await seedTracks([url("x"), url("y")], into: sut)
        let idToRemove = sut.playlist.tracks[0].id

        sut.removeTrack(idToRemove)
        XCTAssertEqual(sut.playlist.tracks.count, 1, "Precondition: track should be removed")

        um.undo()

        XCTAssertEqual(sut.playlist.tracks.count, 2)
    }

    // MARK: - moveTrack(fromOffsets:toOffset:) — undo

    /// Given: playlist seeded with [A, B, C] (undo stack clear)
    /// When:  move B to end → undo
    /// Then:  order restored to [A, B, C]
    func testUndoMoveTrack_RestoresOrder() async {
        let (sut, um) = makeSUT()
        await seedTracks([url("A"), url("B"), url("C")], into: sut)
        let originalIDs = sut.playlist.tracks.map(\.id)

        sut.moveTrack(fromOffsets: IndexSet(integer: 1), toOffset: 3)
        XCTAssertNotEqual(sut.playlist.tracks.map(\.id), originalIDs,
                          "Precondition: order should have changed")

        um.undo()

        XCTAssertEqual(sut.playlist.tracks.map(\.id), originalIDs)
    }

    // MARK: - redo after undo

    /// Given: load([track]) → undo
    /// When:  redo
    /// Then:  tracks.count == 1
    func testRedoLoad_ReAddsTrack() async {
        let (sut, um) = makeSUT()

        await sut.load(urls: [url("solo")])
        XCTAssertEqual(sut.playlist.tracks.count, 1)

        um.undo()
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "Precondition: undo should remove track")

        um.redo()

        XCTAssertEqual(sut.playlist.tracks.count, 1)
    }
}
