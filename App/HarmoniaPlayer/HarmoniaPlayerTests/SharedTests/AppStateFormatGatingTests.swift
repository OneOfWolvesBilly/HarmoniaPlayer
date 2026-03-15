//
//  AppStateFormatGatingTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Created on 2026-03-12.
//
//  PURPOSE
//  -------
//  Tests for AppState.play(trackID:) format gating.
//
//  COVERAGE
//  --------
//  9 test cases covering:
//  - Free tier: FLAC / DSF / DFF → gate fires (lastError, playbackState, loadCallCount, currentTrack)
//  - Pro tier:  FLAC → gate bypassed (loadCallCount == 1)
//  - Free tier: MP3 / M4A → gate bypassed (loadCallCount == 1)
//
//  All tests use FakePlaybackService — no real audio I/O occurs in this file.
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - @MainActor: Required because AppState is a @MainActor-isolated class.
//    XCTest runs @MainActor test classes on the main actor automatically,
//    so individual test methods do NOT need `await MainActor.run {}` wrappers.
//  - nonisolated deinit {}: Workaround for Xcode 26 beta TaskLocal deallocation
//    crash. Required on every @MainActor XCTestCase subclass in this project.
//  - tearDown order: sut = nil before fakePlaybackService = nil to reduce
//    Xcode 26 beta LLDB RPC instability during test teardown.
//

import XCTest
@testable import HarmoniaPlayer

/// Verifies that `AppState.play(trackID:)` correctly gates Pro-only audio formats
/// on the Free tier and allows all formats on the Pro tier and Free-tier formats.
@MainActor
final class AppStateFormatGatingTests: XCTestCase {

    // MARK: - Test Fixtures

    /// System under test. Created fresh for each test via `makeSUT(isProUnlocked:)`.
    private var sut: AppState!

    /// Fake playback service used to inspect call counts without real audio I/O.
    private var fakePlaybackService: FakePlaybackService!

    // Workaround: Xcode 26 beta TaskLocal deallocation crash on @MainActor deinit.
    nonisolated deinit {}

    // MARK: - Setup / Teardown

    override func tearDown() {
        // Nil the SUT before its dependencies to reduce LLDB RPC instability
        // observed under Xcode 26 beta when @MainActor objects are torn down.
        sut = nil
        fakePlaybackService = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates and assigns a fresh SUT wired to a `FakePlaybackService`.
    ///
    /// - Parameter isProUnlocked: Determines whether `CoreFeatureFlags.supportsFLAC`
    ///   is `true` (Pro) or `false` (Free).
    private func makeSUT(isProUnlocked: Bool) {
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        let iap = MockIAPManager(isProUnlocked: isProUnlocked)
        sut = AppState(iapManager: iap, provider: provider)
    }

    /// Adds one track with the given file extension to the SUT playlist via `load(urls:)`.
    ///
    /// Uses a `/tmp/test-track.<ext>` URL. `FakeTagReaderService` (inside `FakeCoreProvider`)
    /// returns the URL-derived `Track` without any real file access.
    ///
    /// - Parameter ext: File extension without the leading dot (e.g. "flac", "mp3").
    /// - Returns: The `Track` that was appended to `sut.playlist`.
    private func addTrack(extension ext: String) async -> Track {
        let url = URL(fileURLWithPath: "/tmp/test-track.\(ext)")
        await sut.load(urls: [url])
        return sut.playlist.tracks[0]
    }

    // MARK: - FLAC / Free Tier (4 cases)

    /// Verifies that `lastError` is set to `.unsupportedFormat` when a Free-tier
    /// user attempts to play a `.flac` file.
    func testFormatGating_FLAC_FreeTier_SetsUnsupportedFormat() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")

        await sut.play(trackID: track.id)

        // Format gate must set lastError before returning.
        XCTAssertEqual(sut.lastError, .unsupportedFormat)
    }

    /// Verifies that `playbackState` is set to `.error(.unsupportedFormat)` when a
    /// Free-tier user attempts to play a `.flac` file.
    func testFormatGating_FLAC_FreeTier_SetsErrorState() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")

        await sut.play(trackID: track.id)

        // Format gate must set playbackState to .error(.unsupportedFormat).
        XCTAssertEqual(sut.playbackState, .error(.unsupportedFormat))
    }

    /// Verifies that `playbackService.load(url:)` is never called when the format
    /// gate fires on the Free tier for a `.flac` file.
    ///
    /// This is the key behavioural contract: the gate fires BEFORE any service call.
    func testFormatGating_FLAC_FreeTier_NoServiceCalls() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")

        await sut.play(trackID: track.id)

        // The gate fires before playbackService.load, so loadCallCount must remain 0.
        XCTAssertEqual(fakePlaybackService.loadCallCount, 0)
    }

    /// Verifies that `currentTrack` is set to the matching track even when the format
    /// gate fires — the gate is applied AFTER `currentTrack` is assigned.
    func testFormatGating_FLAC_FreeTier_SetsCurrentTrack() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")

        await sut.play(trackID: track.id)

        // currentTrack is set before the gate check, so it must reflect the track.
        XCTAssertEqual(sut.currentTrack, track)
    }

    // MARK: - DSF / Free Tier (1 case)

    /// Verifies that `.dsf` (DSD Stream File) is gated on the Free tier.
    func testFormatGating_DSF_FreeTier_SetsUnsupportedFormat() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "dsf")

        await sut.play(trackID: track.id)

        XCTAssertEqual(sut.lastError, .unsupportedFormat)
    }

    // MARK: - DFF / Free Tier (1 case)

    /// Verifies that `.dff` (DSDIFF) is gated on the Free tier.
    func testFormatGating_DFF_FreeTier_SetsUnsupportedFormat() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "dff")

        await sut.play(trackID: track.id)

        XCTAssertEqual(sut.lastError, .unsupportedFormat)
    }

    // MARK: - FLAC / Pro Tier (1 case)

    /// Verifies that the format gate is NOT triggered for a `.flac` file on the Pro tier.
    ///
    /// `featureFlags.supportsFLAC` is `true` for Pro users, so execution must
    /// proceed to `playbackService.load(url:)` (loadCallCount == 1).
    func testFormatGating_FLAC_ProTier_Proceeds() async {
        makeSUT(isProUnlocked: true)
        let track = await addTrack(extension: "flac")

        await sut.play(trackID: track.id)

        // Gate must NOT fire for Pro users — load must be called exactly once.
        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }

    // MARK: - Free-Tier Allowed Formats (2 cases)

    /// Verifies that `.mp3` bypasses the format gate on the Free tier.
    ///
    /// MP3 is a Free-tier supported format; `playbackService.load` must be called.
    func testFormatGating_MP3_FreeTier_Proceeds() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "mp3")

        await sut.play(trackID: track.id)

        // MP3 is allowed on Free tier; load must be called exactly once.
        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }

    /// Verifies that `.m4a` (AAC/ALAC) bypasses the format gate on the Free tier.
    ///
    /// M4A is a Free-tier supported format; `playbackService.load` must be called.
    func testFormatGating_M4A_FreeTier_Proceeds() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "m4a")

        await sut.play(trackID: track.id)

        // M4A is allowed on Free tier; load must be called exactly once.
        XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    }
}
