//
//  AppStateShuffleTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStateShuffleTests: XCTestCase {

    // MARK: - Helpers

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    private func makeSUT() -> (AppState, FakePlaybackService) {
        let fake = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fake)
        let sut = AppState(iapManager: MockIAPManager(), provider: provider)
        return (sut, fake)
    }

    private func loadTracks(_ sut: AppState, count: Int) async {
        let urls = (1...count).map { makeURL("track\($0)") }
        await sut.load(urls: urls)
    }

    // MARK: - isShuffled default

    func testIsShuffled_DefaultIsFalse() {
        let (sut, _) = makeSUT()
        XCTAssertEqual(sut.isShuffled, ShuffleMode.off)
    }

    // MARK: - toggleShuffle

    func testToggleShuffle_OffToOn() {
        let (sut, _) = makeSUT()
        sut.toggleShuffle()
        XCTAssertEqual(sut.isShuffled, ShuffleMode.on)
    }

    func testToggleShuffle_OnToOff() {
        let (sut, _) = makeSUT()
        sut.toggleShuffle()
        sut.toggleShuffle()
        XCTAssertEqual(sut.isShuffled, ShuffleMode.off)
    }

    // MARK: - playNextTrack with shuffle

    func testPlayNext_Shuffled_DoesNotRepeatCurrentTrack() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 2)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        sut.toggleShuffle()
        await sut.playNextTrack()
        XCTAssertEqual(sut.currentTrack?.url, makeURL("track2"))
    }

    func testPlayNext_Shuffled_PlaysRandomTrack() async {
        let (sut, _) = makeSUT()
        await loadTracks(sut, count: 5)
        await sut.play(trackID: sut.playlist.tracks[0].id)
        sut.toggleShuffle()

        var playedIDs = Set<Track.ID>()
        for _ in 0..<10 {
            await sut.playNextTrack()
            if let id = sut.currentTrack?.id { playedIDs.insert(id) }
        }
        XCTAssertGreaterThan(playedIDs.count, 1)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
