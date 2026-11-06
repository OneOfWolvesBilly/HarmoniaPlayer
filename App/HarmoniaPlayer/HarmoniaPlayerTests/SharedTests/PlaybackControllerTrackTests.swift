//
//  PlaybackControllerTrackTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for `PlaybackController.play(trackID:)`: track resolution across
/// the playlist context, the load-then-play service sequence, duration
/// and state updates, and error propagation.
@MainActor
final class PlaybackControllerTrackTests: XCTestCase {

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
        let alertCenter: AlertCenter
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let fake = FakePlaybackService()
        let context = FakePlaylistContext()
        let alertCenter = AlertCenter()
        let sut = PlaybackController(
            playbackService: fake,
            alertCenter: alertCenter,
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        sut.playlistContext = context
        return Fixture(sut: sut, fake: fake, context: context, alertCenter: alertCenter)
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    /// Seeds one track into the context's first playlist and returns it.
    private func seedOneTrack(_ f: Fixture) -> Track {
        let track = Track(url: makeURL("test-track"))
        f.context.playlists[0].tracks = [track]
        return track
    }

    /// Seeds three tracks and returns them.
    private func seedThreeTracks(_ f: Fixture) -> (Track, Track, Track) {
        let tracks = [Track(url: makeURL("track-a")), Track(url: makeURL("track-b")), Track(url: makeURL("track-c"))]
        f.context.playlists[0].tracks = tracks
        return (tracks[0], tracks[1], tracks[2])
    }

    // MARK: - Tests

    func testPlayTrack_SetsCurrentTrack() async {
        let f = makeSUT()
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.sut.currentTrack, track)
    }

    func testPlayTrack_CallsLoad() async {
        let f = makeSUT()
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.fake.loadCallCount, 1)
    }

    func testPlayTrack_LoadsCorrectURL() async {
        let f = makeSUT()
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.fake.loadedURLs.first, track.url)
    }

    func testPlayTrack_CallsPlay() async {
        let f = makeSUT()
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.fake.playCallCount, 1)
    }

    func testPlayTrack_SetsPlayingState() async {
        let f = makeSUT()
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    func testPlayTrack_UpdatesDuration() async {
        let f = makeSUT()
        f.fake.stubbedDuration = 240.0
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.sut.duration, 240.0)
    }

    func testPlayTrack_LoadError_SetsLastError() async {
        let f = makeSUT()
        f.fake.stubbedLoadError = PlaybackError.failedToOpenFile
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertNotNil(f.alertCenter.lastError)
    }

    func testPlayTrack_LoadError_SetsErrorState() async {
        let f = makeSUT()
        f.fake.stubbedLoadError = PlaybackError.failedToOpenFile
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        if case .error = f.sut.playbackState {
            // expected
        } else {
            XCTFail("Expected playbackState == .error, got \(f.sut.playbackState)")
        }
    }

    func testPlayTrack_LoadError_DoesNotCallPlay() async {
        let f = makeSUT()
        f.fake.stubbedLoadError = PlaybackError.failedToOpenFile
        let track = seedOneTrack(f)

        await f.sut.play(trackID: track.id)

        XCTAssertEqual(f.fake.playCallCount, 0)
    }

    func testPlayTrack_InvalidID_NoServiceCalls() async {
        let f = makeSUT()
        _ = seedOneTrack(f)

        await f.sut.play(trackID: UUID())

        XCTAssertEqual(f.fake.loadCallCount, 0)
    }

    func testPlayTrack_InvalidID_NilsCurrentTrack() async {
        let f = makeSUT()
        let track = seedOneTrack(f)
        await f.sut.play(trackID: track.id)
        XCTAssertNotNil(f.sut.currentTrack, "Pre-condition: currentTrack should be set")

        await f.sut.play(trackID: UUID())

        XCTAssertNil(f.sut.currentTrack)
    }

    func testPlay_SwitchTrack_UpdatesCurrentTrack() async {
        let f = makeSUT()
        let (trackA, trackB, _) = seedThreeTracks(f)
        await f.sut.play(trackID: trackA.id)
        XCTAssertEqual(f.sut.currentTrack, trackA, "Pre-condition: currentTrack should be track A")

        await f.sut.play(trackID: trackB.id)

        XCTAssertEqual(f.sut.currentTrack, trackB)
    }

    func testPlay_EmptyPlaylist_ClearsCurrentTrack() async {
        let f = makeSUT()
        let (trackA, _, _) = seedThreeTracks(f)
        await f.sut.play(trackID: trackA.id)
        XCTAssertNotNil(f.sut.currentTrack, "Pre-condition: currentTrack should be set")
        f.context.playlists[0].tracks = []

        await f.sut.play(trackID: trackA.id)

        XCTAssertNil(f.sut.currentTrack)
    }

    func testPlayTrack_InOtherPlaylist_SwitchesActivePlaylistIndex() async {
        let f = makeSUT()
        let other = Track(url: makeURL("other"))
        let second = Playlist(name: "PL2", tracks: [other])
        f.context.playlists = [Playlist(name: "PL1", tracks: [Track(url: makeURL("first"))]), second]
        f.context.activePlaylistIndex = 0

        await f.sut.play(trackID: other.id)

        XCTAssertEqual(f.context.activePlaylistIndex, 1)
        XCTAssertEqual(f.sut.playingPlaylistID, second.id)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
