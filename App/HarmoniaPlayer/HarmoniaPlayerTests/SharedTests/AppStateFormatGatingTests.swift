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
//  COVERAGE (v0.1 frozen)
//  --------
//  Load behaviour (v0.1):
//  - FLAC/DSF/DFF blocked at load time (treated as unsupported)
//  - Unsupported formats still blocked at load time
//  - Free-tier formats proceed normally
//
//  Play gate (Free tier):
//  - MP3/M4A proceed normally
//
//  v0.2 RESTORE: All commented-out tests below must be restored when
//  Pro format gating (load-then-paywall) is re-enabled.
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
    private var tempDir: URL?

    nonisolated deinit {}

    // MARK: - Teardown

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
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

    // MARK: - v0.1: FLAC/DSF/DFF blocked at load time (treated as unsupported)

    func testLoad_FLAC_FreeTier_BlockedAsUnsupported() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "v0.1: FLAC must be blocked at load time")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1,
                       "FLAC must appear in skippedUnsupportedURLs")
    }

    func testLoad_DSF_FreeTier_BlockedAsUnsupported() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dsf")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "v0.1: DSF must be blocked at load time")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1)
    }

    func testLoad_DFF_FreeTier_BlockedAsUnsupported() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dff")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "v0.1: DFF must be blocked at load time")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1)
    }

    // MARK: - Load behaviour: unsupported format still blocked

    func testLoad_UnsupportedFormat_BlockedWithAlert() async {
        makeSUT(isProUnlocked: false)
        await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.xyz")])
        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "Unsupported format must not be added")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1)
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

    // MARK: - importPlaylist format gate

    /// Creates a temp directory with empty stub files and a .m3u8 referencing them.
    private func makeM3U8(filenames: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        for name in filenames {
            let fileURL = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let m3u8URL = dir.appendingPathComponent("test.m3u8")
        var lines = ["#EXTM3U"]
        for name in filenames {
            let absPath = dir.appendingPathComponent(name).path
            lines.append("#EXTINF:-1,\(name)")
            lines.append(absPath)
        }
        try lines.joined(separator: "\n").write(to: m3u8URL, atomically: true, encoding: .utf8)
        return m3u8URL
    }

    func testImportPlaylist_SkipsUnsupportedFormat() async throws {
        makeSUT(isProUnlocked: false)
        let m3u8 = try makeM3U8(filenames: ["track.xyz"])

        await sut.importPlaylist(from: m3u8)

        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "Unsupported format must not be added via importPlaylist")
        XCTAssertEqual(sut.skippedImportURLs.count, 1,
                       "Unsupported file must appear in skippedImportURLs")
    }

    func testImportPlaylist_SkipsUnsupportedFormat_KeepsSupported() async throws {
        makeSUT(isProUnlocked: false)
        let m3u8 = try makeM3U8(filenames: ["good.mp3", "bad.xyz"])

        await sut.importPlaylist(from: m3u8)

        XCTAssertEqual(sut.playlist.tracks.count, 1,
                       "Only the supported format track must be added")
        XCTAssertEqual(sut.skippedImportURLs.count, 1,
                       "The unsupported file must be reported in skippedImportURLs")
    }

    /// v0.1: FLAC must be blocked in importPlaylist too (treated as unsupported).
    func testImportPlaylist_FLAC_BlockedAsUnsupported() async throws {
        makeSUT(isProUnlocked: false)
        let m3u8 = try makeM3U8(filenames: ["track.flac"])

        await sut.importPlaylist(from: m3u8)

        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "v0.1: FLAC must be blocked in importPlaylist")
        XCTAssertEqual(sut.skippedImportURLs.count, 1)
    }

    // MARK: - v0.2 RESTORE: Pro format load + play gate tests
    //
    // All tests below are commented out for v0.1 freeze.
    // FLAC/DSF/DFF cannot enter the playlist, so play-gate and auto-play
    // skip tests are unreachable. Restore when allowedFormats includes
    // proOnlyFormats for Pro users.

    // /// FLAC must be added to the playlist for Free users.
    // /// Paywall is shown only when the user attempts to play the track.
    // func testLoad_FLAC_FreeTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1,
    //                    "FLAC must be added to playlist for Free user")
    // }
    //
    // func testLoad_FLAC_FreeTier_NoPaywall() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
    //     XCTAssertFalse(sut.showPaywall,
    //                    "Loading FLAC must not trigger Paywall — only playing does")
    // }
    //
    // func testLoad_DSF_FreeTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dsf")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1)
    // }
    //
    // func testLoad_DFF_FreeTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dff")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1)
    // }
    //
    // func testLoad_FLAC_ProTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: true)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1,
    //                    "FLAC must be added for Pro user")
    //     XCTAssertFalse(sut.showPaywall)
    // }
    //
    // func testPlayGate_FLAC_FreeTier_ShowsPaywall() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertTrue(sut.showPaywall,
    //                   "Playing FLAC on Free tier must show Paywall")
    // }
    //
    // func testPlayGate_FLAC_FreeTier_DoesNotPlay() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertEqual(fakePlaybackService.loadCallCount, 0,
    //                    "PlaybackService must not be called for format-gated track")
    // }
    //
    // func testPlayGate_FLAC_ProTier_Proceeds() async {
    //     makeSUT(isProUnlocked: true)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    // }
    //
    // func testPlayGate_FLAC_ProTier_NoPaywall() async {
    //     makeSUT(isProUnlocked: true)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertFalse(sut.showPaywall)
    // }
    //
    // /// Given playlist [MP3, FLAC, MP3] and paywallDismissedThisSession == true,
    // /// when trackDidFinishPlaying() fires after MP3[0],
    // /// FLAC is silently skipped and MP3[2] plays.
    // func testAutoPlay_FLAC_DismissedSession_SilentSkip() async {
    //     makeSUT(isProUnlocked: false)
    //     let mp3a = URL(fileURLWithPath: "/tmp/track1.mp3")
    //     let flac = URL(fileURLWithPath: "/tmp/track2.flac")
    //     let mp3b = URL(fileURLWithPath: "/tmp/track3.mp3")
    //     await sut.load(urls: [mp3a, flac, mp3b])
    //
    //     await sut.play(trackID: sut.playlist.tracks[0].id)
    //     sut.paywallDismissedThisSession = true
    //     fakePlaybackService.resetCounts()
    //
    //     await sut.trackDidFinishPlaying()
    //
    //     XCTAssertEqual(sut.currentTrack?.url, mp3b,
    //                    "FLAC must be silently skipped; MP3[2] should be playing")
    //     XCTAssertFalse(sut.showPaywall,
    //                    "Paywall must not appear when paywallDismissedThisSession is true")
    // }
    //
    // /// Given playlist [MP3, FLAC] and paywallDismissedThisSession == false,
    // /// when trackDidFinishPlaying() fires after MP3[0],
    // /// Paywall is shown for the FLAC track.
    // func testAutoPlay_FLAC_NotDismissed_ShowsPaywall() async {
    //     makeSUT(isProUnlocked: false)
    //     let mp3 = URL(fileURLWithPath: "/tmp/track1.mp3")
    //     let flac = URL(fileURLWithPath: "/tmp/track2.flac")
    //     await sut.load(urls: [mp3, flac])
    //
    //     await sut.play(trackID: sut.playlist.tracks[0].id)
    //     XCTAssertFalse(sut.paywallDismissedThisSession, "Pre-condition")
    //
    //     await sut.trackDidFinishPlaying()
    //
    //     XCTAssertTrue(sut.showPaywall,
    //                   "Paywall must appear when paywallDismissedThisSession is false")
    // }
    //
    // /// Playing a format-gated FLAC must show Paywall but must NOT set lastError.
    // func testPlayGate_FLAC_FreeTier_DoesNotSetLastError() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //
    //     await sut.play(trackID: track.id)
    //
    //     XCTAssertNil(sut.lastError,
    //                  "lastError must not be set when format gate blocks playback — Paywall is sufficient feedback")
    // }
    //
    // /// Playing a format-gated FLAC must post bringMainWindowToFront notification.
    // func testPlayGate_FLAC_FreeTier_PostsBringMainWindowToFrontNotification() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //
    //     var notificationReceived = false
    //     let observer = NotificationCenter.default.addObserver(
    //         forName: .bringMainWindowToFront,
    //         object: nil,
    //         queue: .main
    //     ) { _ in notificationReceived = true }
    //     defer { NotificationCenter.default.removeObserver(observer) }
    //
    //     await sut.play(trackID: track.id)
    //
    //     XCTAssertTrue(notificationReceived,
    //                   "bringMainWindowToFront must be posted when format gate blocks FLAC on Free tier")
    // }
    //
    // /// FLAC is a recognised format (Pro-only) and must be added to the playlist
    // /// via importPlaylist — same as load(urls:) behaviour. Format gate at play time.
    // func testImportPlaylist_FLAC_AddsToPlaylist() async throws {
    //     makeSUT(isProUnlocked: false)
    //     let m3u8 = try makeM3U8(filenames: ["track.flac"])
    //
    //     await sut.importPlaylist(from: m3u8)
    //
    //     XCTAssertEqual(sut.playlist.tracks.count, 1,
    //                    "FLAC must be added to playlist via importPlaylist — gated at play time, not load time")
    // }
}
