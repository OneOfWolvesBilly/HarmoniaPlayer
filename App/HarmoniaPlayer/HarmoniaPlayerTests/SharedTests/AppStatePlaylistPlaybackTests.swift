//
//  AppStatePlaylistPlaybackTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// End-to-end guards of the root wiring between the playlist collection and
/// the playback controller: a playlist mutation made through
/// `appState.playlistCollection` reaches the playback state through the
/// closures the composition root installs.
@MainActor
final class AppStatePlaylistPlaybackTests: XCTestCase {

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

    private func makeSUT() -> AppState {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: defaults,
            playlistStore: FakePlaylistStore()
        )
    }

    private func makeURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0).mp3") }
    }

    /// Loads the named tracks through the collection and returns them.
    private func loadTracks(_ names: [String], into sut: AppState) async -> [Track] {
        await sut.playlistCollection.load(urls: makeURLs(names))
        return sut.playlistCollection.playlist.tracks
    }

    /// Allows the asynchronous stop / play task started by a reaction to finish.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - clearPlaylist

    func testClearPlaylist_NilsCurrentTrack() async throws {
        let sut = makeSUT()
        let tracks = await loadTracks(["a"], into: sut)
        let a = try XCTUnwrap(tracks.first)
        await sut.playbackController.play(trackID: a.id)
        XCTAssertNotNil(sut.playbackController.currentTrack)           // pre-condition

        sut.playlistCollection.clearPlaylist()

        XCTAssertNil(sut.playbackController.currentTrack)
    }

    // MARK: - removeTrack

    /// Removing the only playing track stops playback.
    func testRemoveTrack_CurrentTrack_StopsPlayback() async throws {
        let sut = makeSUT()
        let tracks = await loadTracks(["a"], into: sut)
        let a = try XCTUnwrap(tracks.first)
        await sut.playbackController.play(trackID: a.id)
        XCTAssertNotNil(sut.playbackController.currentTrack)           // pre-condition

        sut.playlistCollection.removeTrack(a.id)
        try await settle()

        XCTAssertTrue(sut.playlistCollection.playlist.tracks.isEmpty)
        XCTAssertEqual(sut.playbackController.playbackState, .stopped)
    }

    func testRemoveTrack_OtherTrack_KeepsCurrentTrack() async throws {
        let sut = makeSUT()
        let tracks = await loadTracks(["a", "b"], into: sut)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1])
        await sut.playbackController.play(trackID: a.id)

        sut.playlistCollection.removeTrack(b.id)
        try await settle()

        XCTAssertEqual(sut.playbackController.currentTrack, a)
    }

    // MARK: - removeTracks

    /// Removing a batch that includes the playing track stops playback.
    func testRemoveTracks_IncludingCurrentTrack_StopsPlayback() async throws {
        let sut = makeSUT()
        let tracks = await loadTracks(["a", "b"], into: sut)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1])
        await sut.playbackController.play(trackID: a.id)
        XCTAssertNotNil(sut.playbackController.currentTrack)           // pre-condition

        sut.playlistCollection.removeTracks([a.id, b.id])
        try await settle()

        XCTAssertTrue(sut.playlistCollection.playlist.tracks.isEmpty)
        XCTAssertNil(sut.playbackController.currentTrack)
        XCTAssertEqual(sut.playbackController.playbackState, .stopped)
    }

    func testRemoveTracks_ExcludingCurrentTrack_KeepsCurrentTrack() async throws {
        let sut = makeSUT()
        let tracks = await loadTracks(["a", "b", "c"], into: sut)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1]), c = try XCTUnwrap(tracks[safe: 2])
        await sut.playbackController.play(trackID: a.id)

        sut.playlistCollection.removeTracks([b.id, c.id])
        try await settle()

        XCTAssertEqual(sut.playlistCollection.playlist.tracks.map(\.id), [a.id])
        XCTAssertEqual(sut.playbackController.currentTrack, a)
    }

    // MARK: - Playback continuity on switch

    func testSwitchPlaylist_DoesNotStopPlayback() async {
        let sut = makeSUT()
        await sut.playlistCollection.load(urls: makeURLs(["test"]))
        await sut.playbackController.play()
        sut.playlistCollection.newPlaylist(name: "Rock")

        sut.playlistCollection.activePlaylistIndex = 1

        XCTAssertEqual(sut.playbackController.playbackState, .playing)
    }
}
