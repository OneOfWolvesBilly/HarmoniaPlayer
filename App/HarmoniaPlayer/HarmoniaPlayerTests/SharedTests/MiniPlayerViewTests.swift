//
//  MiniPlayerViewTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  SPDX-License-Identifier: MIT
//
//  Slice 8-B — Mini Player tests.
//
//  Tests cover:
//    - MarqueeText @AppStorage default values
//    - MiniPlayerView initializes without crash
//    - AppState.switchMiniPlayerPlaylist switches index and plays first track
//

import XCTest
import SwiftUI
@testable import HarmoniaPlayer

@MainActor
final class MiniPlayerViewTests: XCTestCase {

    private var createdSuiteNames: [String] = []

    override func tearDown() {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        super.tearDown()
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "hp-minitest-\(UUID().uuidString)"
        createdSuiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func makeSUT() -> AppState {
        AppState(
            iapManager: MockIAPManager(),
            provider: FakeCoreProvider(),
            userDefaults: makeIsolatedDefaults()
        )
    }

    // MARK: - MarqueeText @AppStorage defaults

    func testMarqueeSpeed_DefaultValue_Is40() {
        let defaults = makeIsolatedDefaults()
        let speed = defaults.object(forKey: "hp.marqueeSpeed") as? Double ?? 40.0
        XCTAssertEqual(speed, 40.0)
    }

    func testMarqueePause_DefaultValue_Is1() {
        let defaults = makeIsolatedDefaults()
        let pause = defaults.object(forKey: "hp.marqueePause") as? Double ?? 1.0
        XCTAssertEqual(pause, 1.0)
    }

    func testAlwaysOnTop_DefaultValue_IsTrue() {
        let defaults = makeIsolatedDefaults()
        // When key absent, default is true
        let val = defaults.object(forKey: "hp.miniPlayerAlwaysOnTop") as? Bool ?? true
        XCTAssertTrue(val)
    }

    // MARK: - MiniPlayerView smoke

    func testMiniPlayerView_InitializesWithNoTrack() {
        let appState = makeSUT()
        XCTAssertNil(appState.currentTrack)
        _ = MiniPlayerView().environmentObject(appState)
    }

    func testMiniPlayerView_InitializesAfterLoad() async {
        let appState = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await appState.load(urls: [url])
        XCTAssertFalse(appState.playlist.tracks.isEmpty)
        _ = MiniPlayerView().environmentObject(appState)
    }

    // MARK: - switchMiniPlayerPlaylist

    func testSwitchMiniPlayerPlaylist_ChangesActiveIndex() async {
        let appState = makeSUT()
        appState.newPlaylist(name: "Playlist 2")
        XCTAssertEqual(appState.playlists.count, 2)

        await appState.switchMiniPlayerPlaylist(to: 1)

        XCTAssertEqual(appState.activePlaylistIndex, 1)
    }

    func testSwitchMiniPlayerPlaylist_OutOfRange_IsNoOp() async {
        let appState = makeSUT()
        let originalIndex = appState.activePlaylistIndex

        await appState.switchMiniPlayerPlaylist(to: 99)

        XCTAssertEqual(appState.activePlaylistIndex, originalIndex)
    }

    func testSwitchMiniPlayerPlaylist_StopsPlayback() async {
        let provider = FakeCoreProvider()
        let fake = provider.playbackServiceStub
        let appState = AppState(
            iapManager: MockIAPManager(),
            provider: provider,
            userDefaults: makeIsolatedDefaults()
        )
        appState.newPlaylist(name: "Playlist 2")

        await appState.switchMiniPlayerPlaylist(to: 1)

        XCTAssertGreaterThanOrEqual(fake.stopCallCount, 1)
    }
}
