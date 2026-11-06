//
//  PlaybackControllerReplayGainTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for `PlaybackController` ReplayGain application: the effective
/// output volume for each mode, the tag fallbacks, and clamping.
@MainActor
final class PlaybackControllerReplayGainTests: XCTestCase {

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
        let settingsStore: SettingsStore
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let fake = FakePlaybackService()
        let context = FakePlaylistContext()
        let settingsStore = SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults)
        let sut = PlaybackController(
            playbackService: fake,
            alertCenter: AlertCenter(),
            settingsStore: settingsStore,
            userDefaults: defaults
        )
        sut.playlistContext = context
        return Fixture(sut: sut, fake: fake, context: context, settingsStore: settingsStore)
    }

    /// Seeds a track carrying the given ReplayGain tags and returns it.
    private func seedTrack(
        _ f: Fixture,
        replayGainTrack: Double? = nil,
        replayGainAlbum: Double? = nil
    ) -> Track {
        let track = Track(
            url: URL(fileURLWithPath: "/tmp/rg-test-\(UUID().uuidString).mp3"),
            title: "RG Test",
            replayGainTrack: replayGainTrack,
            replayGainAlbum: replayGainAlbum
        )
        f.context.playlists[0].tracks.append(track)
        return track
    }

    /// Returns the expected effective volume after applying gainDB on top of baseVolume, clamped to [0, 1].
    private func expectedVolume(base: Float = 1.0, gainDB: Double) -> Float {
        Float(min(1.0, Double(base) * pow(10.0, gainDB / 20.0)))
    }

    // MARK: - mode = off

    func testReplayGain_Off_DoesNotAdjustVolume() async throws {
        let f = makeSUT()
        let track = seedTrack(f, replayGainTrack: -6.0, replayGainAlbum: -4.0)
        f.settingsStore.replayGainMode = .off
        await f.sut.setVolume(0.8)

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, 0.8, accuracy: 0.001)
    }

    // MARK: - mode = track

    func testReplayGain_TrackMode_UsesTrackGain() async throws {
        let f = makeSUT()
        let gainDB = -6.0
        let track = seedTrack(f, replayGainTrack: gainDB, replayGainAlbum: -3.0)
        f.settingsStore.replayGainMode = .track
        await f.sut.setVolume(1.0)

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: gainDB), accuracy: 0.001)
    }

    func testReplayGain_TrackMode_FallbackToAlbum_WhenTrackGainNil() async throws {
        let f = makeSUT()
        let albumDB = -4.0
        let track = seedTrack(f, replayGainTrack: nil, replayGainAlbum: albumDB)
        f.settingsStore.replayGainMode = .track

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: albumDB), accuracy: 0.001)
    }

    // MARK: - mode = album

    func testReplayGain_AlbumMode_UsesAlbumGain() async throws {
        let f = makeSUT()
        let gainDB = -3.0
        let track = seedTrack(f, replayGainTrack: -6.0, replayGainAlbum: gainDB)
        f.settingsStore.replayGainMode = .album

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: gainDB), accuracy: 0.001)
    }

    func testReplayGain_AlbumMode_FallbackToTrack_WhenAlbumGainNil() async throws {
        let f = makeSUT()
        let trackDB = -5.0
        let track = seedTrack(f, replayGainTrack: trackDB, replayGainAlbum: nil)
        f.settingsStore.replayGainMode = .album

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: trackDB), accuracy: 0.001)
    }

    // MARK: - Both tags nil

    func testReplayGain_BothTagsNil_UsesPlainVolume() async throws {
        let f = makeSUT()
        let track = seedTrack(f, replayGainTrack: nil, replayGainAlbum: nil)
        f.settingsStore.replayGainMode = .track
        await f.sut.setVolume(0.7)

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, 0.7, accuracy: 0.001)
    }

    // MARK: - Clamping

    func testReplayGain_LargePositiveGain_ClampsTo1() async throws {
        let f = makeSUT()
        // +30 dB → linear ~31.6 → must be clamped to 1.0
        let track = seedTrack(f, replayGainTrack: 30.0)
        f.settingsStore.replayGainMode = .track
        await f.sut.setVolume(1.0)

        await f.sut.play(trackID: track.id)

        let vol = try XCTUnwrap(f.fake.lastSetVolume)
        XCTAssertEqual(vol, 1.0, accuracy: 0.001)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
