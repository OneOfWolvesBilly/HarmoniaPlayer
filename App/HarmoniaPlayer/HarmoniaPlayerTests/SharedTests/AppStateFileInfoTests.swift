//
//  AppStateFileInfoTests.swift
//  HarmoniaPlayerTests
//
//  Slice 9-D: Regression contract tests for AppState.showFileInfo(trackID:).
//
//  These tests lock the behaviour of `fileInfoTrack` and `showFileInfo(trackID:)`
//  as `FileInfoView` moves from a `.sheet` presentation to an independent
//  `WindowGroup`. The runtime behaviour of `showFileInfo` does not change in
//  Slice 9-D; these tests exist to protect the AppState API contract that
//  ContentView's `.onChange(of: appState.fileInfoTrack)` now relies on.
//

import XCTest
@testable import HarmoniaPlayer

// MARK: - Helpers

private func makeURL(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name).mp3")
}

// MARK: - Test Suite

/// Tests that `AppState.showFileInfo(trackID:)` populates `fileInfoTrack`
/// when the given track ID exists in the active playlist, and leaves it
/// `nil` when the ID does not match any track.
///
/// `@MainActor` is required because `AppState` is `@MainActor` isolated.
@MainActor
final class AppStateFileInfoTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: AppState!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        let provider = FakeCoreProvider()
        sut = AppState(iapManager: MockIAPManager(), provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        sut = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Slice 9-D: `testShowFileInfo_SetsTrack`
    ///
    /// Given a track present in the active playlist,
    /// when `showFileInfo(trackID:)` is called with that track's ID,
    /// then `fileInfoTrack` is populated with the matching track.
    func testShowFileInfo_SetsTrack() async {
        // Given: a track loaded into the playlist
        let url = makeURL("a")
        await sut.load(urls: [url])
        guard let loadedID = sut.playlist.tracks.first?.id else {
            XCTFail("Precondition failed: track was not loaded into playlist")
            return
        }

        // When
        sut.showFileInfo(trackID: loadedID)

        // Then
        XCTAssertEqual(
            sut.fileInfoTrack?.id, loadedID,
            "showFileInfo(trackID:) must set fileInfoTrack to the matching track"
        )
    }

    /// Slice 9-D: `testShowFileInfo_InvalidID_NoOp`
    ///
    /// Given no matching track in the active playlist,
    /// when `showFileInfo(trackID:)` is called with an unknown ID,
    /// then `fileInfoTrack` remains `nil`.
    func testShowFileInfo_InvalidID_NoOp() {
        // Given: empty playlist and a random ID that cannot match
        let randomID = UUID()
        XCTAssertTrue(
            sut.playlist.tracks.isEmpty,
            "Precondition: playlist must be empty"
        )

        // When
        sut.showFileInfo(trackID: randomID)

        // Then
        XCTAssertNil(
            sut.fileInfoTrack,
            "showFileInfo(trackID:) with a non-matching ID must leave fileInfoTrack nil"
        )
    }
}
