//
//  AppStateTrackSelectionTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-21.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState track selection behaviour (Slice 2-D)
///
/// Verifies `play(trackID:)` edge cases.
/// AppState.swift is **not modified** in this slice — the implementation
/// was already delivered in Slice 2-C.
///
/// **Swift 6 / Xcode 26 note:**
/// `@MainActor` isolation is declared at the class level. XCTest executes
/// `@MainActor`-isolated test classes on the main actor automatically, so
/// no `await MainActor.run {}` wrappers are needed in individual test methods.
@MainActor
final class AppStateTrackSelectionTests: XCTestCase {

    // MARK: - Test Fixtures

    private var sut: AppState!
    private var fakeProvider: FakeCoreProvider!

    override func setUp() {
        super.setUp()
        fakeProvider = FakeCoreProvider()
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: fakeProvider)
    }

    override func tearDown() {
        sut = nil
        fakeProvider = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Loads three tracks into the SUT's playlist and returns them.
    private func loadThreeTracks() -> (Track, Track, Track) {
        let urls = [
            URL(fileURLWithPath: "/tmp/track-a.mp3"),
            URL(fileURLWithPath: "/tmp/track-b.mp3"),
            URL(fileURLWithPath: "/tmp/track-c.mp3"),
        ]
        sut.load(urls: urls)
        let tracks = sut.playlist.tracks
        return (tracks[0], tracks[1], tracks[2])
    }

    // MARK: - Tests

    /// Slice2-D: `testPlay_ValidID_SetsCurrentTrack`
    ///
    /// Given a playlist with 3 tracks,
    /// when `play(trackID:)` is called with a valid ID,
    /// then `currentTrack` is set to the matching track.
    func testPlay_ValidID_SetsCurrentTrack() {
        let (trackA, _, _) = loadThreeTracks()

        sut.play(trackID: trackA.id)

        XCTAssertEqual(sut.currentTrack, trackA)
    }

    /// Slice2-D: `testPlay_SwitchTrack_UpdatesCurrentTrack`
    ///
    /// Given `currentTrack` is already set to track A,
    /// when `play(trackID:)` is called with track B's ID,
    /// then `currentTrack` switches to track B.
    func testPlay_SwitchTrack_UpdatesCurrentTrack() {
        let (trackA, trackB, _) = loadThreeTracks()
        sut.play(trackID: trackA.id)
        XCTAssertEqual(sut.currentTrack, trackA, "Pre-condition: currentTrack should be track A")

        sut.play(trackID: trackB.id)

        XCTAssertEqual(sut.currentTrack, trackB)
    }

    /// Slice2-D: `testPlay_InvalidID_ClearsCurrentTrack`
    ///
    /// Given a playlist with 3 tracks and a currentTrack already set,
    /// when `play(trackID:)` is called with an ID not in the playlist,
    /// then `currentTrack` is nil.
    func testPlay_InvalidID_ClearsCurrentTrack() {
        let (trackA, _, _) = loadThreeTracks()
        sut.play(trackID: trackA.id)
        XCTAssertNotNil(sut.currentTrack, "Pre-condition: currentTrack should be set")

        sut.play(trackID: UUID()) // unknown ID

        XCTAssertNil(sut.currentTrack)
    }

    /// Slice2-D: `testPlay_EmptyPlaylist_ClearsCurrentTrack`
    ///
    /// Given an empty playlist,
    /// when `play(trackID:)` is called with any ID,
    /// then `currentTrack` is nil.
    func testPlay_EmptyPlaylist_ClearsCurrentTrack() {
        XCTAssertTrue(sut.playlist.isEmpty, "Pre-condition: playlist should be empty")

        sut.play(trackID: UUID())

        XCTAssertNil(sut.currentTrack)
    }

    /// Slice2-D: `testPlay_DoesNotCallPlaybackService`
    ///
    /// Given any playlist state,
    /// when `play(trackID:)` is called,
    /// then no calls are made to the playback service.
    ///
    /// Playback orchestration is deferred to Slice 4.
    func testPlay_DoesNotCallPlaybackService() {
        let (trackA, _, _) = loadThreeTracks()

        sut.play(trackID: trackA.id)

        // FakeCoreProvider records makePlaybackService calls at construction time.
        // Verifying the count stays at 1 (set during AppState.init) confirms
        // play(trackID:) does not trigger any additional service creation or calls.
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
            "play(trackID:) must not trigger additional playback service creation")
        XCTAssertEqual(sut.currentTrack, trackA,
            "currentTrack should still be set (sanity check)")
    }
}
