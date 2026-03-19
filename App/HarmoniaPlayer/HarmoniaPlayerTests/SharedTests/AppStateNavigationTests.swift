//
//  AppStateNavigationTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStateNavigationTests: XCTestCase {

    // MARK: - Helpers

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    private func makeSUT(isProUser: Bool = false) -> (AppState, FakePlaybackService) {
        let fake = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fake)
        let sut = AppState(iapManager: MockIAPManager(isProUnlocked: isProUser), provider: provider)
        return (sut, fake)
    }

    private func loadTracks(_ sut: AppState, count: Int) async {
        let urls = (1...count).map { makeURL("track\($0)") }
        await sut.load(urls: urls)
    }

    // MARK: - playNextTrack: empty playlist

    func testPlayNext_EmptyPlaylist_IsNoOp() async {
        let (sut, fake) = makeSUT()
        await sut.playNextTrack()
        XCTAssertEqual(fake.loadCallCount, 0)
    }

    // MARK: - playNextTrack: no currentTrack

    func testPlayNext_NoCurrentTrack_PlaysFirst() async {
        let (sut, fake) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
        XCTAssertEqual(fake.loadCallCount, 1)
    }

    // MARK: - playNextTrack: has next

    func testPlayNext_HasNextTrack_PlaysNext() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track2"))
    }

    // MARK: - playNextTrack: last track, repeatMode == .off

    /// Design decision: manual Next button always wraps to first track at end of playlist.
    /// Only natural completion (trackDidFinishPlaying) stops when repeatMode == .off.
    func testPlayNext_LastTrack_RepeatOff_WrapsToFirst() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[1].id)
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
    }

    // MARK: - playNextTrack: last track, repeatMode == .all

    func testPlayNext_LastTrack_RepeatAll_PlaysFirst() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[1].id)
        sut.cycleRepeatMode() // .off → .all
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
    }

    // MARK: - playNextTrack: repeatMode == .one

    /// Design decision: repeatMode == .one does NOT intercept manual Next button.
    /// Next always advances the playlist regardless of repeat mode.
    /// Only natural track completion (trackDidFinishPlaying) respects .one.
    func testPlayNext_RepeatOne_AdvancesToNextTrack() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        sut.cycleRepeatMode() // .off → .all
        sut.cycleRepeatMode() // .all → .one
        await sut.playNextTrack()
        // Should advance to track2, not replay track1
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track2"))
    }

    // MARK: - playNextTrack: single track

    /// Single track: Next wraps to first (same track) and replays it.
    func testPlayNext_SingleTrack_RepeatOff_ReplaysTrack() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 1)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
    }

    func testPlayNext_SingleTrack_RepeatAll_ReplaysTrack() async {
        let (sut, fake) = makeSUT()
        await loadTracks(sut, count: 1)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        sut.cycleRepeatMode() // .off → .all
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
        XCTAssertEqual(fake.loadCallCount, 2)
    }

    // MARK: - playPreviousTrack: empty playlist

    func testPlayPrevious_EmptyPlaylist_IsNoOp() async {
        let (sut, fake) = makeSUT()
        await sut.playPreviousTrack()
        XCTAssertEqual(fake.loadCallCount, 0)
    }

    // MARK: - playPreviousTrack: no currentTrack

    func testPlayPrevious_NoCurrentTrack_PlaysFirst() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.playPreviousTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
    }

    // MARK: - playPreviousTrack: has previous

    func testPlayPrevious_HasPreviousTrack_PlaysPrevious() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[1].id)
        await sut.playPreviousTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
    }

    // MARK: - playPreviousTrack: at first track

    func testPlayPrevious_FirstTrack_SeeksToZero() async {
        let (sut, fake) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        await sut.playPreviousTrack()
        XCTAssertEqual(fake.seekCallCount, 1)
        XCTAssertEqual(fake.seekedToSeconds, [0])
    }

    func testPlayPrevious_FirstTrack_RestartsPlayback() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        await sut.playPreviousTrack()
        XCTAssertEqual(sut.playbackState, .playing)
    }

    // MARK: - trackDidFinishPlaying: no currentTrack

    func testTrackDidFinish_NoCurrentTrack_IsNoOp() async {
        let (sut, fake) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.trackDidFinishPlaying()
        XCTAssertEqual(fake.loadCallCount, 0)
    }

    // MARK: - trackDidFinishPlaying: repeatMode == .off

    func testTrackDidFinish_RepeatOff_HasNext_PlaysNext() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        await sut.trackDidFinishPlaying()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track2"))
    }

    func testTrackDidFinish_RepeatOff_LastTrack_Stops() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[1].id)
        await sut.trackDidFinishPlaying()
        XCTAssertEqual(sut.playbackState, .stopped)
    }

    // MARK: - trackDidFinishPlaying: repeatMode == .all

    func testTrackDidFinish_RepeatAll_LastTrack_PlaysFirst() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[1].id)
        sut.cycleRepeatMode() // .off → .all
        await sut.trackDidFinishPlaying()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
    }

    // MARK: - trackDidFinishPlaying: repeatMode == .one

    func testTrackDidFinish_RepeatOne_ReplaysCurrentTrack() async {
        let (sut, fake) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        sut.cycleRepeatMode() // .off → .all
        sut.cycleRepeatMode() // .all → .one
        await sut.trackDidFinishPlaying()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track1"))
        XCTAssertEqual(fake.loadCallCount, 2)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
