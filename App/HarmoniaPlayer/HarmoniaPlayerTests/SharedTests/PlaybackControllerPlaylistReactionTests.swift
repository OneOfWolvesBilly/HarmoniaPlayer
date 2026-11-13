//
//  PlaybackControllerPlaylistReactionTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the controller's reactions to playlist mutations
/// (`handleTracksAppended`, `handleTrackRemoved`, `handleTracksRemoved`,
/// `handlePlaylistCleared`, `handlePlaylistDeleted`, `handleTrackQueuedNext`):
/// shuffle-queue upkeep, and stopping or advancing when the playing track or
/// playlist goes away.
@MainActor
final class PlaybackControllerPlaylistReactionTests: XCTestCase {

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
        let sut: PlaybackController
        let fake: FakePlaybackService
        let context: FakePlaylistContext
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let fake = FakePlaybackService()
        let context = FakePlaylistContext()
        let sut = PlaybackController(
            playbackService: fake,
            alertCenter: AlertCenter(),
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            playlistContext: context,
            userDefaults: defaults
        )
        return Fixture(sut: sut, fake: fake, context: context)
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    /// Seeds the named tracks into the context's first playlist.
    @discardableResult
    private func seed(_ names: [String], into f: Fixture) -> [Track] {
        let tracks = names.map { Track(url: makeURL($0)) }
        f.context.playlists[0].tracks = tracks
        return tracks
    }

    /// Allows the asynchronous stop / play task started by a reaction to finish.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - handleTracksAppended

    func testHandleTracksAppended_Shuffled_InsertsAfterCurrentPosition() {
        let f = makeSUT()
        let (a, b, c, d) = (UUID(), UUID(), UUID(), UUID())
        f.sut.isShuffled = .on
        f.sut.shuffleQueue = [a, b, c]
        f.sut.shuffleQueueIndex = 0

        f.sut.handleTracksAppended([d])

        XCTAssertEqual(f.sut.shuffleQueue.count, 4)
        let position = try? XCTUnwrap(f.sut.shuffleQueue.firstIndex(of: d))
        XCTAssertGreaterThanOrEqual(position ?? -1, 1, "an appended track lands after the current position")
    }

    func testHandleTracksAppended_NotShuffled_LeavesQueueEmpty() {
        let f = makeSUT()

        f.sut.handleTracksAppended([UUID()])

        XCTAssertTrue(f.sut.shuffleQueue.isEmpty)
    }

    // MARK: - handleTrackRemoved

    func testHandleTrackRemoved_PlayingTrack_PlaysFirstTrack() async throws {
        let f = makeSUT()
        let tracks = seed(["a", "b", "c"], into: f)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1])
        await f.sut.play(trackID: a.id)
        f.context.playlists[0].tracks.removeAll { $0.id == a.id }

        f.sut.handleTrackRemoved(a.id)
        try await settle()

        XCTAssertEqual(f.sut.currentTrack, b, "playback continues with the first track of the playlist")
        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    func testHandleTrackRemoved_PlayingLastTrack_Stops() async throws {
        let f = makeSUT()
        let a = try XCTUnwrap(seed(["a"], into: f).first)
        await f.sut.play(trackID: a.id)
        f.context.playlists[0].tracks = []

        f.sut.handleTrackRemoved(a.id)
        try await settle()

        XCTAssertEqual(f.sut.playbackState, .stopped)
        XCTAssertEqual(f.sut.currentTime, 0)
        XCTAssertNil(f.sut.currentTrack)
    }

    func testHandleTrackRemoved_PausedCurrentTrack_ClearsCurrentTrackOnly() async throws {
        let f = makeSUT()
        let a = try XCTUnwrap(seed(["a"], into: f).first)
        await f.sut.play(trackID: a.id)
        await f.sut.pause()
        let stopCountBefore = f.fake.stopCallCount
        f.context.playlists[0].tracks = []

        f.sut.handleTrackRemoved(a.id)
        try await settle()

        XCTAssertNil(f.sut.currentTrack)
        XCTAssertEqual(f.fake.stopCallCount, stopCountBefore, "a paused track is not stopped through the service")
    }

    func testHandleTrackRemoved_OtherTrack_LeavesPlaybackUnchanged() async throws {
        let f = makeSUT()
        let tracks = seed(["a", "b"], into: f)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1])
        await f.sut.play(trackID: a.id)
        f.context.playlists[0].tracks.removeAll { $0.id == b.id }

        f.sut.handleTrackRemoved(b.id)
        try await settle()

        XCTAssertEqual(f.sut.currentTrack, a)
        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    func testHandleTrackRemoved_Shuffled_RemovesFromQueueAndShiftsIndex() {
        let f = makeSUT()
        let (x, y, z) = (UUID(), UUID(), UUID())
        f.sut.isShuffled = .on
        f.sut.shuffleQueue = [x, y, z]
        f.sut.shuffleQueueIndex = 2

        f.sut.handleTrackRemoved(x)

        XCTAssertEqual(f.sut.shuffleQueue, [y, z])
        XCTAssertEqual(f.sut.shuffleQueueIndex, 1)
    }

    // MARK: - handleTracksRemoved

    func testHandleTracksRemoved_IncludingCurrent_StopsAndClears() async throws {
        let f = makeSUT()
        let tracks = seed(["a", "b"], into: f)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1])
        await f.sut.play(trackID: a.id)
        f.context.playlists[0].tracks = []

        f.sut.handleTracksRemoved([a.id, b.id])
        try await settle()

        XCTAssertEqual(f.sut.playbackState, .stopped)
        XCTAssertNil(f.sut.currentTrack)
        XCTAssertEqual(f.sut.currentTime, 0)
    }

    func testHandleTracksRemoved_ExcludingCurrent_LeavesPlaybackUnchanged() async throws {
        let f = makeSUT()
        let tracks = seed(["a", "b"], into: f)
        let a = try XCTUnwrap(tracks[safe: 0]), b = try XCTUnwrap(tracks[safe: 1])
        await f.sut.play(trackID: a.id)
        f.context.playlists[0].tracks.removeAll { $0.id == b.id }

        f.sut.handleTracksRemoved([b.id])
        try await settle()

        XCTAssertEqual(f.sut.currentTrack, a)
        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    func testHandleTracksRemoved_Shuffled_FiltersQueueAndClampsIndex() {
        let f = makeSUT()
        let (x, y, z) = (UUID(), UUID(), UUID())
        f.sut.isShuffled = .on
        f.sut.shuffleQueue = [x, y, z]
        f.sut.shuffleQueueIndex = 2

        f.sut.handleTracksRemoved([y, z])

        XCTAssertEqual(f.sut.shuffleQueue, [x])
        XCTAssertEqual(f.sut.shuffleQueueIndex, 0)
    }

    // MARK: - handlePlaylistCleared

    func testHandlePlaylistCleared_ClearsCurrentTrackOnly() async throws {
        let f = makeSUT()
        let a = try XCTUnwrap(seed(["a"], into: f).first)
        await f.sut.play(trackID: a.id)
        let stopCountBefore = f.fake.stopCallCount

        f.sut.handlePlaylistCleared()

        XCTAssertNil(f.sut.currentTrack)
        XCTAssertEqual(f.sut.playbackState, .playing, "clearing the playlist does not change the playback state")
        XCTAssertEqual(f.fake.stopCallCount, stopCountBefore, "clearing the playlist does not stop the service")
    }

    // MARK: - handlePlaylistDeleted

    func testHandlePlaylistDeleted_PlayingPlaylist_Stops() async throws {
        let f = makeSUT()
        let a = try XCTUnwrap(seed(["a"], into: f).first)
        await f.sut.play(trackID: a.id)
        let playingID = try XCTUnwrap(f.sut.playingPlaylistID)

        f.sut.handlePlaylistDeleted(playingID)
        try await settle()

        XCTAssertEqual(f.sut.playbackState, .stopped)
        XCTAssertNil(f.sut.currentTrack)
    }

    func testHandlePlaylistDeleted_OtherPlaylist_NoOp() async throws {
        let f = makeSUT()
        let a = try XCTUnwrap(seed(["a"], into: f).first)
        await f.sut.play(trackID: a.id)

        f.sut.handlePlaylistDeleted(UUID())
        try await settle()

        XCTAssertEqual(f.sut.playbackState, .playing)
        XCTAssertEqual(f.sut.currentTrack, a)
    }

    // MARK: - handleTrackQueuedNext

    func testHandleTrackQueuedNext_Shuffled_PlacesTrackAtNextQueuePosition() {
        let f = makeSUT()
        let (a, b, c) = (UUID(), UUID(), UUID())
        f.sut.isShuffled = .on
        f.sut.shuffleQueue = [a, b, c]
        f.sut.shuffleQueueIndex = 0

        f.sut.handleTrackQueuedNext(c)

        XCTAssertEqual(f.sut.shuffleQueue, [a, c, b])
    }

    func testHandleTrackQueuedNext_NotShuffled_NoOp() {
        let f = makeSUT()

        f.sut.handleTrackQueuedNext(UUID())

        XCTAssertTrue(f.sut.shuffleQueue.isEmpty)
    }
}
