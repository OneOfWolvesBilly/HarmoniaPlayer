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
//  Load behaviour (all tiers):
//  - FLAC/DSF/DFF always added to playlist (no load-time block)
//  - Unsupported formats still blocked at load time
//
//  Play gate (Free tier):
//  - FLAC/DSF/DFF → showPaywall, not played
//
//  Play gate (Pro tier):
//  - FLAC/DSF/DFF → played normally
//
//  Auto-play skip (Free tier):
//  - paywallDismissedThisSession == true  → FLAC silently skipped
//  - paywallDismissedThisSession == false → Paywall shown
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

    private func addTrack(extension ext: String) async -> Track {
        let url = URL(fileURLWithPath: "/tmp/test-track.\(ext)")
        await sut.load(urls: [url])
        return sut.playlist.tracks.last!
    }

    // MARK: - Load behaviour: Pro-format tracks always added to playlist

    /// FLAC must be added to the playlist for Free users.
    /// Paywall is shown only when the user attempts to play the track.
    func testLoad_FLAC_FreeTier_AddsToPlaylist() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
        XCTAssertEqual(sut.playlist.tracks.count, 1,
                       "FLAC must be added to playlist for Free user")
    }

    func testLoad_FLAC_FreeTier_NoPaywall() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
        XCTAssertFalse(sut.showPaywall,
                       "Loading FLAC must not trigger Paywall — only playing does")
    }

    func testLoad_DSF_FreeTier_AddsToPlaylist() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dsf")])
        XCTAssertEqual(sut.playlist.tracks.count, 1)
    }

    func testLoad_DFF_FreeTier_AddsToPlaylist() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dff")])
        XCTAssertEqual(sut.playlist.tracks.count, 1)
    }

    func testLoad_FLAC_ProTier_AddsToPlaylist() async {
        makeSUT(isProUnlocked: true)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
        XCTAssertEqual(sut.playlist.tracks.count, 1,
                       "FLAC must be added for Pro user")
        XCTAssertFalse(sut.showPaywall)
    }

    // MARK: - Load behaviour: unsupported format still blocked

    func testLoad_UnsupportedFormat_BlockedWithAlert() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.xyz")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "Unsupported format must not be added")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1)
    }

    // MARK: - Play gate: Free tier blocks Pro-format playback

    func testPlayGate_FLAC_FreeTier_ShowsPaywall() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")
        await sut.play(trackID: track.id)
        XCTAssertTrue(sut.showPaywall,
                      "Playing FLAC on Free tier must show Paywall")
    }

    func testPlayGate_FLAC_FreeTier_DoesNotPlay() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")
        await sut.play(trackID: track.id)
        XCTAssertEqual(fakePlaybackService.loadCallCount, 0,
                       "PlaybackService must not be called for format-gated track")
    }

    // MARK: - Play gate: Pro tier plays Pro-format normally

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

    // MARK: - Play gate: Free tier allowed formats proceed normally

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

    // MARK: - paywallDismissedThisSession default

    func testPaywallDismissedThisSession_DefaultIsFalse() {
        makeSUT(isProUnlocked: false)
        XCTAssertFalse(sut.paywallDismissedThisSession)
    }

    // MARK: - Auto-play silent skip when paywallDismissedThisSession == true

    /// Given playlist [MP3, FLAC, MP3] and paywallDismissedThisSession == true,
    /// when trackDidFinishPlaying() fires after MP3[0],
    /// FLAC is silently skipped and MP3[2] plays.
    func testAutoPlay_FLAC_DismissedSession_SilentSkip() async {
        makeSUT(isProUnlocked: false)
        let mp3a = URL(fileURLWithPath: "/tmp/track1.mp3")
        let flac = URL(fileURLWithPath: "/tmp/track2.flac")
        let mp3b = URL(fileURLWithPath: "/tmp/track3.mp3")
        await sut.load(urls: [mp3a, flac, mp3b])

        await sut.play(trackID: sut.playlist.tracks[0].id)
        sut.paywallDismissedThisSession = true
        fakePlaybackService.resetCounts()

        await sut.trackDidFinishPlaying()

        XCTAssertEqual(sut.currentTrack?.url, mp3b,
                       "FLAC must be silently skipped; MP3[2] should be playing")
        XCTAssertFalse(sut.showPaywall,
                       "Paywall must not appear when paywallDismissedThisSession is true")
    }

    /// Given playlist [MP3, FLAC] and paywallDismissedThisSession == false,
    /// when trackDidFinishPlaying() fires after MP3[0],
    /// Paywall is shown for the FLAC track.
    func testAutoPlay_FLAC_NotDismissed_ShowsPaywall() async {
        makeSUT(isProUnlocked: false)
        let mp3 = URL(fileURLWithPath: "/tmp/track1.mp3")
        let flac = URL(fileURLWithPath: "/tmp/track2.flac")
        await sut.load(urls: [mp3, flac])

        await sut.play(trackID: sut.playlist.tracks[0].id)
        XCTAssertFalse(sut.paywallDismissedThisSession, "Pre-condition")

        await sut.trackDidFinishPlaying()

        XCTAssertTrue(sut.showPaywall,
                      "Paywall must appear when paywallDismissedThisSession is false")
    }

    // MARK: - Format gate does not set lastError

    /// Playing a format-gated FLAC must show Paywall but must NOT set lastError.
    /// Setting lastError would trigger the Playback Error alert simultaneously
    /// with the Paywall — two modals at once.
    func testPlayGate_FLAC_FreeTier_DoesNotSetLastError() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")

        await sut.play(trackID: track.id)

        XCTAssertNil(sut.lastError,
                     "lastError must not be set when format gate blocks playback — Paywall is sufficient feedback")
    }

    // MARK: - bringMainWindowToFront notification

    /// Playing a format-gated FLAC must post bringMainWindowToFront notification
    /// so MiniPlayerView can close itself before the Paywall appears on the main window.
    func testPlayGate_FLAC_FreeTier_PostsBringMainWindowToFrontNotification() async {
        makeSUT(isProUnlocked: false)
        let track = await addTrack(extension: "flac")

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .bringMainWindowToFront,
            object: nil,
            queue: .main
        ) { _ in notificationReceived = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        await sut.play(trackID: track.id)

        XCTAssertTrue(notificationReceived,
                      "bringMainWindowToFront must be posted when format gate blocks FLAC on Free tier")
    }
}
