//
//  PlaybackControllerNavigationTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for `PlaybackController` navigation: `playNextTrack()`,
/// `playPreviousTrack()`, `trackDidFinishPlaying()`, and the repeat and
/// shuffle modes that steer them.
@MainActor
final class PlaybackControllerNavigationTests: XCTestCase {

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
            userDefaults: defaults
        )
        sut.playlistContext = context
        return Fixture(sut: sut, fake: fake, context: context)
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    /// Seeds `count` tracks named track1…trackN into the active playlist.
    private func seedTracks(_ f: Fixture, count: Int) {
        f.context.playlists[0].tracks = (1...count).map { Track(url: makeURL("track\($0)")) }
    }

    private func tracks(_ f: Fixture) -> [Track] {
        f.context.playlists[f.context.activePlaylistIndex].tracks
    }

    // MARK: - playNextTrack

    func testPlayNext_EmptyPlaylist_IsNoOp() async {
        let f = makeSUT()
        await f.sut.playNextTrack()
        XCTAssertEqual(f.fake.loadCallCount, 0)
    }

    func testPlayNext_NoCurrentTrack_PlaysFirst() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
        XCTAssertEqual(f.fake.loadCallCount, 1)
    }

    func testPlayNext_HasNextTrack_PlaysNext() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track2"))
    }

    /// Design decision: manual Next button always wraps to first track at end of playlist.
    /// Only natural completion (trackDidFinishPlaying) stops when repeatMode == .off.
    func testPlayNext_LastTrack_RepeatOff_WrapsToFirst() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[1].id)
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
    }

    func testPlayNext_LastTrack_RepeatAll_PlaysFirst() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[1].id)
        f.sut.cycleRepeatMode() // .off → .all
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
    }

    /// Design decision: repeatMode == .one does NOT intercept manual Next button.
    /// Next always advances the playlist regardless of repeat mode.
    /// Only natural track completion (trackDidFinishPlaying) respects .one.
    func testPlayNext_RepeatOne_AdvancesToNextTrack() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        f.sut.cycleRepeatMode() // .off → .all
        f.sut.cycleRepeatMode() // .all → .one
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track2"))
    }

    /// Single track: Next wraps to first (same track) and replays it.
    func testPlayNext_SingleTrack_RepeatOff_ReplaysTrack() async {
        let f = makeSUT()
        seedTracks(f, count: 1)
        await f.sut.play(trackID: tracks(f)[0].id)
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
    }

    func testPlayNext_SingleTrack_RepeatAll_ReplaysTrack() async {
        let f = makeSUT()
        seedTracks(f, count: 1)
        await f.sut.play(trackID: tracks(f)[0].id)
        f.sut.cycleRepeatMode() // .off → .all
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
        XCTAssertEqual(f.fake.loadCallCount, 2)
    }

    // MARK: - playPreviousTrack

    func testPlayPrevious_EmptyPlaylist_IsNoOp() async {
        let f = makeSUT()
        await f.sut.playPreviousTrack()
        XCTAssertEqual(f.fake.loadCallCount, 0)
    }

    func testPlayPrevious_NoCurrentTrack_PlaysFirst() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.playPreviousTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
    }

    func testPlayPrevious_HasPreviousTrack_PlaysPrevious() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[1].id)
        await f.sut.playPreviousTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
    }

    func testPlayPrevious_FirstTrack_SeeksToZero() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        await f.sut.playPreviousTrack()
        XCTAssertEqual(f.fake.seekCallCount, 1)
        XCTAssertEqual(f.fake.seekedToSeconds, [0])
    }

    func testPlayPrevious_FirstTrack_RestartsPlayback() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        await f.sut.playPreviousTrack()
        XCTAssertEqual(f.sut.playbackState, .playing)
    }

    // MARK: - trackDidFinishPlaying

    func testTrackDidFinish_NoCurrentTrack_IsNoOp() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.trackDidFinishPlaying()
        XCTAssertEqual(f.fake.loadCallCount, 0)
    }

    func testTrackDidFinish_RepeatOff_HasNext_PlaysNext() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        await f.sut.trackDidFinishPlaying()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track2"))
    }

    func testTrackDidFinish_RepeatOff_LastTrack_Stops() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[1].id)
        await f.sut.trackDidFinishPlaying()
        XCTAssertEqual(f.sut.playbackState, .stopped)
    }

    func testTrackDidFinish_RepeatAll_LastTrack_PlaysFirst() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[1].id)
        f.sut.cycleRepeatMode() // .off → .all
        await f.sut.trackDidFinishPlaying()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
    }

    func testTrackDidFinish_RepeatOne_ReplaysCurrentTrack() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        f.sut.cycleRepeatMode() // .off → .all
        f.sut.cycleRepeatMode() // .all → .one
        await f.sut.trackDidFinishPlaying()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track1"))
        XCTAssertEqual(f.fake.loadCallCount, 2)
    }

    /// Finishing the last track of the *playing* playlist while a *different*
    /// playlist is selected must still stop and clear now-playing state.
    func testTrackDidFinish_PlayingDiffersFromActive_RepeatOff_StopsAndClears() async {
        let f = makeSUT()
        f.context.playlists = [
            Playlist(name: "PL1", tracks: [Track(url: makeURL("a1")), Track(url: makeURL("a2"))]),
            Playlist(name: "PL2", tracks: [Track(url: makeURL("b1")), Track(url: makeURL("b2"))]),
        ]
        f.context.activePlaylistIndex = 1
        await f.sut.play(trackID: tracks(f)[1].id)      // play last track of PL2

        f.context.activePlaylistIndex = 0                 // browse PL1; PL2 still playing
        await f.sut.trackDidFinishPlaying()

        XCTAssertEqual(f.sut.playbackState, .stopped)
        XCTAssertNil(f.sut.currentTrack)
    }

    /// Repeat-one must replay the *playing* track even when a different
    /// playlist is selected.
    func testTrackDidFinish_PlayingDiffersFromActive_RepeatOne_Replays() async {
        let f = makeSUT()
        f.context.playlists = [
            Playlist(name: "PL1", tracks: [Track(url: makeURL("a1")), Track(url: makeURL("a2"))]),
            Playlist(name: "PL2", tracks: [Track(url: makeURL("b1")), Track(url: makeURL("b2"))]),
        ]
        f.context.activePlaylistIndex = 1
        await f.sut.play(trackID: tracks(f)[0].id)      // play first track of PL2
        f.sut.cycleRepeatMode() // .off → .all
        f.sut.cycleRepeatMode() // .all → .one
        let playingURL = f.sut.currentTrack?.url
        let loadsBefore = f.fake.loadCallCount

        f.context.activePlaylistIndex = 0                 // browse PL1; PL2 still playing
        await f.sut.trackDidFinishPlaying()

        XCTAssertEqual(f.sut.currentTrack?.url, playingURL)
        XCTAssertEqual(f.sut.playbackState, .playing)
        XCTAssertEqual(f.fake.loadCallCount, loadsBefore + 1,
                       "repeat-one must reload and replay the playing track")
    }

    // MARK: - Shuffle

    func testIsShuffled_DefaultIsFalse() {
        let f = makeSUT()
        XCTAssertEqual(f.sut.isShuffled, ShuffleMode.off)
    }

    func testToggleShuffle_OffToOn() {
        let f = makeSUT()
        f.sut.toggleShuffle()
        XCTAssertEqual(f.sut.isShuffled, ShuffleMode.on)
    }

    func testToggleShuffle_OnToOff() {
        let f = makeSUT()
        f.sut.toggleShuffle()
        f.sut.toggleShuffle()
        XCTAssertEqual(f.sut.isShuffled, ShuffleMode.off)
    }

    func testPlayNext_Shuffled_DoesNotRepeatCurrentTrack() async {
        let f = makeSUT()
        seedTracks(f, count: 2)
        await f.sut.play(trackID: tracks(f)[0].id)
        f.sut.toggleShuffle()
        await f.sut.playNextTrack()
        XCTAssertEqual(f.sut.currentTrack?.url, makeURL("track2"))
    }

    func testPlayNext_Shuffled_PlaysRandomTrack() async {
        let f = makeSUT()
        seedTracks(f, count: 5)
        await f.sut.play(trackID: tracks(f)[0].id)
        f.sut.toggleShuffle()

        var playedIDs = Set<Track.ID>()
        for _ in 0..<10 {
            await f.sut.playNextTrack()
            if let id = f.sut.currentTrack?.id { playedIDs.insert(id) }
        }
        XCTAssertGreaterThan(playedIDs.count, 1)
    }

    // MARK: - Repeat mode

    func testRepeatMode_DefaultIsOff() {
        let f = makeSUT()
        XCTAssertEqual(f.sut.repeatMode, .off)
    }

    func testCycleRepeatMode_OffToAll() {
        let f = makeSUT()
        f.sut.cycleRepeatMode()
        XCTAssertEqual(f.sut.repeatMode, .all)
    }

    func testCycleRepeatMode_AllToOne() {
        let f = makeSUT()
        f.sut.cycleRepeatMode()
        f.sut.cycleRepeatMode()
        XCTAssertEqual(f.sut.repeatMode, .one)
    }

    func testCycleRepeatMode_OneToOff() {
        let f = makeSUT()
        f.sut.cycleRepeatMode()
        f.sut.cycleRepeatMode()
        f.sut.cycleRepeatMode()
        XCTAssertEqual(f.sut.repeatMode, .off)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
