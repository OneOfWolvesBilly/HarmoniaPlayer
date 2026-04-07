//
//  AppStateFormatGatingTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Created on 2026-03-12.
//
//  PURPOSE
//  -------
//  Tests for AppState format gating at load time and play time.
//
//  COVERAGE
//  --------
//  10 test cases:
//  - load gate — Free: FLAC/DSF/DFF blocked (not in playlist, Paywall shown)
//  - load gate — Pro:  FLAC allowed (added to playlist, no Paywall)
//  - load gate — Free: unsupported format blocked (skippedUnsupportedURLs set)
//  - play gate — Pro:  FLAC proceeds (loadCallCount == 1, showPaywall == false)
//  - play gate — Free: MP3/M4A proceeds (loadCallCount == 1)
//
//  NOTE: play-gate tests for FLAC/DSF/DFF + Free tier are intentionally absent.
//  Load gate now prevents these formats from entering a Free user's playlist,
//  making the play-gate path unreachable. Load-gate tests provide equivalent coverage.
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - @MainActor: Required because AppState is a @MainActor-isolated class.
//  - nonisolated deinit {}: Workaround for Xcode 26 beta TaskLocal deallocation crash.
//  - tearDown order: sut = nil before fakePlaybackService = nil.
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStateFormatGatingTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    nonisolated deinit {}

    // MARK: - Teardown

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(isProUnlocked: Bool) {
        suiteName = "hp-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        sut = AppState(
            iapManager: MockIAPManager(isProUnlocked: isProUnlocked),
            provider: provider,
            userDefaults: testDefaults
        )
    }

    /// Loads a track with the given extension and returns it.
    /// Only call this for formats that pass the load gate for the current SUT tier.
    private func addTrack(extension ext: String) async -> Track {
        let url = URL(fileURLWithPath: "/tmp/test-track.\(ext)")
        await sut.load(urls: [url])
        return sut.playlist.tracks[0]
    }

    // MARK: - Load gate: Free tier blocks Pro-only formats (3 cases)

    func testLoadGate_FLAC_FreeTier_BlockedAndShowsPaywall() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "FLAC must not be added for Free user")
        XCTAssertTrue(sut.showPaywall, "Paywall must be shown when Free user loads FLAC")
    }

    func testLoadGate_DSF_FreeTier_BlockedAndShowsPaywall() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dsf")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "DSF must not be added for Free user")
        XCTAssertTrue(sut.showPaywall)
    }

    func testLoadGate_DFF_FreeTier_BlockedAndShowsPaywall() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dff")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "DFF must not be added for Free user")
        XCTAssertTrue(sut.showPaywall)
    }

    // MARK: - Load gate: Pro tier allows Pro-only formats (1 case)

    func testLoadGate_FLAC_ProTier_AddedToPlaylist() async {
        makeSUT(isProUnlocked: true)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
        XCTAssertEqual(sut.playlist.tracks.count, 1, "FLAC must be added for Pro user")
        XCTAssertFalse(sut.showPaywall)
    }

    // MARK: - Load gate: unsupported format (1 case)

    func testLoadGate_UnsupportedFormat_BlockedWithAlert() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.xyz")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty, "Unsupported format must not be added")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1)
    }

    // MARK: - Play gate: Pro tier FLAC (2 cases)

    func testPlayGate_FLAC_ProTier_Proceeds() async {
        makeSUT(isProUnlocked: true)
        let track = await addTrack(extension: "flac")
        await sut.play(trackID: track.id)
        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }

    func testPlayGate_FLAC_ProTier_NoPaywall() async {
        makeSUT(isProUnlocked: true)
        let track = await addTrack(extension: "flac")
        await sut.play(trackID: track.id)
        XCTAssertFalse(sut.showPaywall)
    }

    // MARK: - Play gate: Free tier allowed formats (2 cases)

    func testPlayGate_MP3_FreeTier_Proceeds() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "mp3")
        await sut.play(trackID: track.id)
        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }

    func testPlayGate_M4A_FreeTier_Proceeds() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "m4a")
        await sut.play(trackID: track.id)
        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }
}
