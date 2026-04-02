//
//  AppStateReplayGainTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-04-02.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for Slice 8-C: ReplayGain mode selection and volume gain application.
@MainActor
final class AppStateReplayGainTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var fakeTagReader: FakeTagReaderService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        fakePlaybackService = FakePlaybackService()
        fakeTagReader = FakeTagReaderService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService,
                                        tagReader: fakeTagReader)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        fakeTagReader = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Loads a track with the given ReplayGain tags into the playlist via FakeTagReaderService stub.
    private func loadTrack(
        replayGainTrack: Double? = nil,
        replayGainAlbum: Double? = nil
    ) async -> Track {
        let url = URL(fileURLWithPath: "/tmp/rg-test-\(UUID().uuidString).mp3")
        let track = Track(
            url: url,
            title: "RG Test",
            replayGainTrack: replayGainTrack,
            replayGainAlbum: replayGainAlbum
        )
        fakeTagReader.stubbedMetadata[url] = track
        await sut.load(urls: [url])
        return sut.playlist.tracks.last!
    }

    /// Returns the expected effective volume after applying gainDB on top of baseVolume, clamped to [0, 1].
    private func expectedVolume(base: Float = 1.0, gainDB: Double) -> Float {
        Float(min(1.0, Double(base) * pow(10.0, gainDB / 20.0)))
    }

    // MARK: - Default

    func testReplayGainMode_DefaultIsOff() {
        XCTAssertEqual(sut.replayGainMode, .off)
    }

    // MARK: - mode = off

    func testReplayGain_Off_DoesNotAdjustVolume() async throws {
        let track = await loadTrack(replayGainTrack: -6.0, replayGainAlbum: -4.0)
        sut.replayGainMode = .off
        await sut.setVolume(0.8)

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, 0.8, accuracy: 0.001)
    }

    // MARK: - mode = track

    func testReplayGain_TrackMode_UsesTrackGain() async throws {
        let gainDB = -6.0
        let track = await loadTrack(replayGainTrack: gainDB, replayGainAlbum: -3.0)
        sut.replayGainMode = .track
        await sut.setVolume(1.0)

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: gainDB), accuracy: 0.001)
    }

    func testReplayGain_TrackMode_FallbackToAlbum_WhenTrackGainNil() async throws {
        let albumDB = -4.0
        let track = await loadTrack(replayGainTrack: nil, replayGainAlbum: albumDB)
        sut.replayGainMode = .track

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: albumDB), accuracy: 0.001)
    }

    // MARK: - mode = album

    func testReplayGain_AlbumMode_UsesAlbumGain() async throws {
        let gainDB = -3.0
        let track = await loadTrack(replayGainTrack: -6.0, replayGainAlbum: gainDB)
        sut.replayGainMode = .album

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: gainDB), accuracy: 0.001)
    }

    func testReplayGain_AlbumMode_FallbackToTrack_WhenAlbumGainNil() async throws {
        let trackDB = -5.0
        let track = await loadTrack(replayGainTrack: trackDB, replayGainAlbum: nil)
        sut.replayGainMode = .album

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: trackDB), accuracy: 0.001)
    }

    // MARK: - Both tags nil

    func testReplayGain_BothTagsNil_UsesPlainVolume() async throws {
        let track = await loadTrack(replayGainTrack: nil, replayGainAlbum: nil)
        sut.replayGainMode = .track
        await sut.setVolume(0.7)

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, 0.7, accuracy: 0.001)
    }

    // MARK: - Clamping

    func testReplayGain_LargePositiveGain_ClampsTo1() async throws {
        // +30 dB → linear ~31.6 → must be clamped to 1.0
        let track = await loadTrack(replayGainTrack: 30.0)
        sut.replayGainMode = .track
        await sut.setVolume(1.0)

        await sut.play(trackID: track.id)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, 1.0, accuracy: 0.001)
    }

    // MARK: - Persistence

    func testReplayGainMode_Persisted() {
        sut.replayGainMode = .album
        sut.saveState()

        let provider2 = FakeCoreProvider()
        let iap2 = MockIAPManager(isProUnlocked: false)
        let sut2 = AppState(iapManager: iap2, provider: provider2, userDefaults: testDefaults)

        XCTAssertEqual(sut2.replayGainMode, .album)
    }

    // MARK: - Real-time mode switching

    func testReplayGain_ModeSwitch_DuringPlayback_AppliesImmediately() async throws {
        let gainDB = -6.0
        let track = await loadTrack(replayGainTrack: gainDB, replayGainAlbum: -3.0)
        sut.replayGainMode = .off
        await sut.play(trackID: track.id)

        // Switch to track mode while playing — should apply immediately
        sut.replayGainMode = .track

        // Allow Combine sink + Task to execute
        try await Task.sleep(nanoseconds: 50_000_000)

        let vol = try XCTUnwrap(fakePlaybackService.lastSetVolume)
        XCTAssertEqual(vol, expectedVolume(gainDB: gainDB), accuracy: 0.001)
    }

    func testReplayGain_ModeSwitch_WhenStopped_DoesNotCallSetVolume() async throws {
        let track = await loadTrack(replayGainTrack: -6.0)
        _ = track  // loaded but not played
        let callCountBefore = fakePlaybackService.setVolumeCallCount

        sut.replayGainMode = .track
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fakePlaybackService.setVolumeCallCount, callCountBefore)
    }
}
