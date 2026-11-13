//
//  PlaylistCollectionUndoTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//
//  UNIT TEST DESIGN
//  ----------------
//  Each test covers exactly ONE undo-registering operation. Test data setup
//  uses seedTracks() which loads tracks then clears the undo stack, ensuring
//  only the operation under test is in the stack. This avoids NSUndoManager
//  groupsByEvent contamination between setup and the operation being tested.
//

import XCTest
@testable import Harmonia_Player

@MainActor
final class PlaylistCollectionUndoTests: XCTestCase {

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

    private func makeSUT() -> (sut: PlaylistCollection, undoManager: UndoManager) {
        let suiteName = "hp-undo-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let um = UndoManager()
        let sut = PlaylistCollection(
            tagReaderService: FakeTagReaderService(),
            fileDropService: FileDropService(),
            playlistStore: FakePlaylistStore(),
            undoManager: um,
            alertCenter: AlertCenter(),
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        return (sut, um)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    /// Loads tracks into the playlist and clears the undo stack.
    private func seedTracks(_ urls: [URL], into sut: PlaylistCollection) async {
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
    func testUndoRemoveTrack_ReInsertsTrack() async throws {
        let (sut, um) = makeSUT()
        await seedTracks([url("x"), url("y")], into: sut)
        let idToRemove = try XCTUnwrap(sut.playlist.tracks.first).id

        sut.removeTrack(idToRemove)
        XCTAssertEqual(sut.playlist.tracks.count, 1, "Precondition: track should be removed")

        um.undo()

        XCTAssertEqual(sut.playlist.tracks.count, 2)
    }

    // MARK: - removeTracks(_:) — undo

    /// Given: playlist seeded with [A, B, C] (undo stack clear)
    /// When:  removeTracks([A, C]) → undo
    /// Then:  all three tracks restored by a single undo
    func testUndoRemoveTracks_ReInsertsWholeBatch() async throws {
        let (sut, um) = makeSUT()
        await seedTracks([url("A"), url("B"), url("C")], into: sut)
        let toRemove: Set<Track.ID> = [try XCTUnwrap(sut.playlist.tracks[safe: 0]).id,
                                       try XCTUnwrap(sut.playlist.tracks[safe: 2]).id]

        sut.removeTracks(toRemove)
        XCTAssertEqual(sut.playlist.tracks.count, 1, "Precondition: 2 tracks should be removed")

        um.undo()

        XCTAssertEqual(sut.playlist.tracks.count, 3)
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

    // MARK: - moveTrack(id:before:) — undo

    /// Given: playlist seeded with [A, B, C] (undo stack clear)
    /// When:  moveTrack(id: C, before: A) → undo
    /// Then:  order restored to [A, B, C]
    func testUndoMoveTrackIDBefore_RestoresOrder() async throws {
        let (sut, um) = makeSUT()
        await seedTracks([url("A"), url("B"), url("C")], into: sut)
        let originalIDs = sut.playlist.tracks.map(\.id)
        let a = try XCTUnwrap(originalIDs[safe: 0]), c = try XCTUnwrap(originalIDs[safe: 2])

        sut.moveTrack(id: c, before: a)
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

    // MARK: - undo() / redo() entry points

    /// Given: load([track])
    /// When:  undo() then redo() through the store's own entry points
    /// Then:  the playlist is emptied, then refilled
    func testUndoAndRedo_ForwardToUndoManager() async {
        let (sut, _) = makeSUT()
        await sut.load(urls: [url("solo")])
        XCTAssertEqual(sut.playlist.tracks.count, 1, "Precondition")

        sut.undo()
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "undo() must perform the undo manager's undo")

        sut.redo()
        XCTAssertEqual(sut.playlist.tracks.count, 1, "redo() must perform the undo manager's redo")
    }
}
