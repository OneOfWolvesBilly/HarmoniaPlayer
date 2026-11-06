//
//  PlaybackControllerPersistenceTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the `PlaybackController` persistence keys: `hp.volume`
/// (written by `saveVolume()`), `hp.repeatMode` and `hp.isShuffled`
/// (written on change), and their restore at init.
@MainActor
final class PlaybackControllerPersistenceTests: XCTestCase {

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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    /// Builds a controller on `defaults`; a second call on the same suite
    /// simulates a relaunch.
    private func makeSUT(defaults: UserDefaults) -> PlaybackController {
        let sut = PlaybackController(
            playbackService: FakePlaybackService(),
            alertCenter: AlertCenter(),
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        sut.playlistContext = nil
        return sut
    }

    // MARK: - Defaults

    func testInit_NoVolumeKey_VolumeIsOne() {
        let sut = makeSUT(defaults: makeDefaults())
        XCTAssertEqual(sut.volume, 1.0, accuracy: 0.001)
    }

    // MARK: - Restore

    func testInit_RestoresPersistedPlaybackSettings() throws {
        let defaults = makeDefaults()
        defaults.set(Float(0.25), forKey: "hp.volume")
        defaults.set(try JSONEncoder().encode(RepeatMode.one), forKey: "hp.repeatMode")
        defaults.set(true, forKey: "hp.isShuffled")

        let sut = makeSUT(defaults: defaults)

        XCTAssertEqual(sut.volume, 0.25, accuracy: 0.001)
        XCTAssertEqual(sut.repeatMode, .one)
        XCTAssertTrue(sut.isShuffled)
    }

    // MARK: - Volume (written by saveVolume)

    func testVolume_NotPersistedBeforeSaveVolume() async {
        let defaults = makeDefaults()
        let sut = makeSUT(defaults: defaults)

        await sut.setVolume(0.3)
        XCTAssertNil(defaults.object(forKey: "hp.volume"),
                     "volume must not be written to UserDefaults on change")

        sut.saveVolume()
        XCTAssertEqual(defaults.float(forKey: "hp.volume"), 0.3, accuracy: 0.001,
                       "saveVolume() must write hp.volume")
    }

    func testVolume_SurvivesRelaunch_AfterSaveVolume() async {
        let defaults = makeDefaults()
        let sut = makeSUT(defaults: defaults)
        await sut.setVolume(0.7)
        sut.saveVolume()

        let restored = makeSUT(defaults: defaults)

        XCTAssertEqual(restored.volume, 0.7, accuracy: 0.001)
    }

    // MARK: - Repeat mode (written on change)

    func testRepeatMode_PersistsOnChange() throws {
        let defaults = makeDefaults()
        let sut = makeSUT(defaults: defaults)

        sut.repeatMode = .one

        let data = try XCTUnwrap(defaults.data(forKey: "hp.repeatMode"),
                                 "repeatMode must be written to UserDefaults on change")
        XCTAssertEqual(try JSONDecoder().decode(RepeatMode.self, from: data), .one)
    }

    func testRepeatMode_SurvivesRelaunch() {
        let defaults = makeDefaults()
        let sut = makeSUT(defaults: defaults)
        sut.cycleRepeatMode() // off → all

        let restored = makeSUT(defaults: defaults)

        XCTAssertEqual(restored.repeatMode, .all)
    }

    // MARK: - Shuffle mode (written on change)

    func testShuffleMode_PersistsOnChange() {
        let defaults = makeDefaults()
        let sut = makeSUT(defaults: defaults)

        sut.isShuffled = .on

        XCTAssertNotNil(defaults.object(forKey: "hp.isShuffled"),
                        "isShuffled must be written to UserDefaults on change")
        XCTAssertTrue(defaults.bool(forKey: "hp.isShuffled"))
    }

    func testShuffleMode_SurvivesRelaunch() {
        let defaults = makeDefaults()
        let sut = makeSUT(defaults: defaults)
        sut.toggleShuffle() // off → on

        let restored = makeSUT(defaults: defaults)

        XCTAssertTrue(restored.isShuffled)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
