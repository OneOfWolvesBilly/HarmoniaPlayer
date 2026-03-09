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
///
/// **Slice 3-B update:**
/// `loadThreeTracks()` helper is now `async` because `AppState.load(urls:)`
/// is now `async`. Test methods that call it are updated to `async` accordingly.
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
    ///
    /// Marked `async` because `AppState.load(urls:)` is now async (Slice 3-B).
    private func loadThreeTracks() async -> (Track, Track, Track) {
        let urls = [
            URL(fileURLWithPath: "/tmp/track-a.mp3"),
            URL(fileURLWithPath: "/tmp/track-b.mp3"),
            URL(fileURLWithPath: "/tmp/track-c.mp3"),
        ]
        await sut.load(urls: urls)
        let tracks = sut.playlist.tracks
        return (tracks[0], tracks[1], tracks[2])
    }

    // MARK: - Tests

    /// Slice2-D: `testPlay_ValidID_SetsCurrentTrack`
    ///
    /// Given a playlist with 3 tracks,
    /// when `play(trackID:)` is called with a valid ID,
    /// then `currentTrack` is set to the matching track.
    func testPlay_ValidID_SetsCurrentTrack() async {
        let (trackA, _, _) = await loadThreeTracks()

        await sut.play(trackID: trackA.id)

        XCTAssertEqual(sut.currentTrack, trackA)
    }

    /// Slice2-D: `testPlay_SwitchTrack_UpdatesCurrentTrack`
    ///
    /// Given `currentTrack` is already set to track A,
    /// when `play(trackID:)` is called with track B's ID,
    /// then `currentTrack` switches to track B.
    func testPlay_SwitchTrack_UpdatesCurrentTrack() async {
        let (trackA, trackB, _) = await loadThreeTracks()
        await sut.play(trackID: trackA.id)
        XCTAssertEqual(sut.currentTrack, trackA, "Pre-condition: currentTrack should be track A")

        await sut.play(trackID: trackB.id)

        XCTAssertEqual(sut.currentTrack, trackB)
    }

    /// Slice2-D: `testPlay_InvalidID_ClearsCurrentTrack`
    ///
    /// Given a playlist with 3 tracks and a currentTrack already set,
    /// when `play(trackID:)` is called with an ID not in the playlist,
    /// then `currentTrack` is nil.
    func testPlay_InvalidID_ClearsCurrentTrack() async {
        let (trackA, _, _) = await loadThreeTracks()
        await sut.play(trackID: trackA.id)
        XCTAssertNotNil(sut.currentTrack, "Pre-condition: currentTrack should be set")

        await sut.play(trackID: UUID()) // unknown ID

        XCTAssertNil(sut.currentTrack)
    }

    /// Slice2-D: `testPlay_EmptyPlaylist_ClearsCurrentTrack`
    ///
    /// Given an empty playlist,
    /// when `play(trackID:)` is called with any ID,
    /// then `currentTrack` is nil.
    func testPlay_EmptyPlaylist_ClearsCurrentTrack() async {
        XCTAssertTrue(sut.playlist.isEmpty, "Pre-condition: playlist should be empty")

        await sut.play(trackID: UUID())

        XCTAssertNil(sut.currentTrack)
    }

}
