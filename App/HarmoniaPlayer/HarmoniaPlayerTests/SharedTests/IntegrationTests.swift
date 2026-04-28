//
//  IntegrationTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Created on 2026-03-15.
//
//  PURPOSE
//  -------
//  End-to-end integration tests using real HarmoniaCoreProvider and real
//  audio bundle resources.
//
//  COVERAGE
//  --------
//  8 test cases:
//  - testIntegration_CompletePlaybackFlow   : valid MP3 → .playing
//  - testIntegration_MetadataEnrichment     : tagged MP3 → title enriched
//  - testIntegration_CorruptFile_SetsError  : zero-byte file → lastError != nil
//  - testIntegration_UnsupportedFormat_Free : .flac, Free → added to playlist, showPaywall == false at load
//  - testIntegration_TrackSwitching         : 2 MP3s → currentTrack == track2, .playing
//  - testIntegration_StopResetsState        : playing → stop() → .stopped, currentTime == 0
//  - testIntegration_PauseSetsPausedState   : playing → pause() → .paused
//  - testIntegration_SeekUpdatesCurrentTime : playing → seek(to:) → currentTime updated
//
//  DESIGN NOTES
//  ------------
//  - Uses HarmoniaCoreProvider directly — no FakeCoreProvider or FakePlaybackService.
//  - Uses MockIAPManager for IAP state (external to HarmoniaCore).
//  - Does NOT import HarmoniaCore (module boundary: import only in Integration Layer).
//  - Uses XCTSkip (not XCTFail) when a bundle resource is absent so CI passes
//    on machines that do not yet have the audio files.
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - @MainActor: Required because AppState is a @MainActor-isolated class.
//    XCTest runs @MainActor test classes on the main actor automatically,
//    so individual test methods do NOT need `await MainActor.run {}` wrappers.
//  - nonisolated deinit {}: Workaround for Xcode 26 beta TaskLocal deallocation
//    crash. Required on every @MainActor XCTestCase subclass in this project.
//  - tearDown order: await sut.stop() before sut = nil to release real audio
//    resources (AVAudioEngine) cleanly before deallocation.
//

import XCTest
@testable import HarmoniaPlayer

/// End-to-end integration tests using a real `HarmoniaCoreProvider` and real
/// audio bundle resources.
///
/// Exercises the full stack: `AppState` → `HarmoniaCoreProvider` →
/// `HarmoniaPlaybackServiceAdapter` / `HarmoniaTagReaderAdapter` →
/// HarmoniaCore-Swift adapters (AVFoundation).
///
/// Missing bundle resources cause the individual test to be skipped via
/// `XCTSkip` rather than failing, so the suite remains green before audio
/// files are added to the bundle.
@MainActor
final class IntegrationTests: XCTestCase {

    // MARK: - Test Fixtures

    var sut: AppState!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    // Workaround: Xcode 26 beta TaskLocal deallocation crash on @MainActor deinit.
    nonisolated deinit {}

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        let provider = HarmoniaCoreProvider()
        let iap = MockIAPManager()
        sut = AppState(iapManager: iap, provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        await sut.stop()
        sut = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
    }

    // MARK: - Resource Helper

    /// Returns the URL for a named resource in the test bundle.
    ///
    /// Throws `XCTSkip` when the resource is absent so the calling test is
    /// marked as skipped rather than failed.
    ///
    /// - Parameters:
    ///   - name: Resource file name without extension.
    ///   - ext:  File extension (e.g. `"mp3"`, `"flac"`).
    /// - Returns: URL to the bundle resource.
    /// - Throws: `XCTSkip` when the resource is not found in the test bundle.
    func bundleURL(forResource name: String, withExtension ext: String) throws -> URL {
        guard let url = Bundle(for: type(of: self))
            .url(forResource: name, withExtension: ext) else {
            throw XCTSkip("Bundle resource '\(name).\(ext)' not found")
        }
        return url
    }

    // MARK: - Tests

    /// Verifies that playing a valid real MP3 via the real HarmoniaCore stack
    /// transitions `playbackState` to `.playing`.
    func testIntegration_CompletePlaybackFlow() async throws {
        let url = try bundleURL(forResource: "test_playback", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]

        await sut.play(trackID: track.id)

        XCTAssertEqual(sut.playbackState, .playing)
    }

    /// Verifies that `load(urls:)` with a tagged MP3 enriches the track's title
    /// field so that it differs from the raw URL filename.
    ///
    /// `test_tagged.mp3` carries the ID3 title "Tagged Track", which is distinct
    /// from `url.lastPathComponent` ("test_tagged.mp3").
    func testIntegration_MetadataEnrichment() async throws {
        let url = try bundleURL(forResource: "test_tagged", withExtension: "mp3")

        await sut.load(urls: [url])

        let track = sut.playlist.tracks[0]
        XCTAssertNotEqual(track.title, url.lastPathComponent)
    }

    /// Verifies that attempting to play a zero-byte corrupt file causes
    /// `lastError` to be set (non-nil).
    ///
    /// The corrupt file cannot be decoded by the real HarmoniaCore stack,
    /// so either tag reading or playback loading raises an error that
    /// `AppState` maps into `lastError`.
    func testIntegration_CorruptFile_SetsError() async throws {
        let url = try bundleURL(forResource: "test_corrupt", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]

        await sut.play(trackID: track.id)

        XCTAssertNotNil(sut.lastError)
    }

    /// v0.1: Loading a `.flac` file on the Free tier is blocked as unsupported.
    /// FLAC must not enter the playlist — same as any unknown format.
    func testIntegration_UnsupportedFormat_Free() async throws {
        let url = try bundleURL(forResource: "test_format", withExtension: "flac")
        await sut.load(urls: [url])

        XCTAssertTrue(sut.playlist.tracks.isEmpty,
                      "v0.1: FLAC must be blocked at load time")
        XCTAssertEqual(sut.skippedUnsupportedURLs.count, 1,
                       "FLAC must appear in skippedUnsupportedURLs")
    }

    // v0.2 RESTORE: original test (FLAC enters playlist, Paywall at play time).
    //
    // /// Verifies that loading a `.flac` file on the Free tier adds it to the
    // /// playlist with no Paywall shown at load time.
    // /// The Paywall is shown only when the user attempts to play the track.
    // func testIntegration_UnsupportedFormat_Free() async throws {
    //     let url = try bundleURL(forResource: "test_format", withExtension: "flac")
    //     await sut.load(urls: [url])
    //
    //     XCTAssertFalse(sut.playlist.tracks.isEmpty,
    //                    "FLAC must be added to playlist for Free user")
    //     XCTAssertFalse(sut.showPaywall,
    //                    "Paywall must not be shown at load time — only when playing")
    // }

    /// Verifies that switching from one track to another sets `currentTrack`
    /// to the new track and `playbackState` to `.playing`.
    func testIntegration_TrackSwitching() async throws {
        let url1 = try bundleURL(forResource: "test_playback", withExtension: "mp3")
        let url2 = try bundleURL(forResource: "test_track2", withExtension: "mp3")
        await sut.load(urls: [url1, url2])
        let track1 = sut.playlist.tracks[0]
        let track2 = sut.playlist.tracks[1]

        await sut.play(trackID: track1.id)
        await sut.play(trackID: track2.id)

        XCTAssertEqual(sut.currentTrack, track2)
        XCTAssertEqual(sut.playbackState, .playing)
    }

    /// Verifies that `stop()` transitions `playbackState` to `.stopped`
    /// and resets `currentTime` to `0`.
    func testIntegration_StopResetsState() async throws {
        let url = try bundleURL(forResource: "test_playback", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]
        await sut.play(trackID: track.id)

        await sut.stop()

        XCTAssertEqual(sut.playbackState, .stopped)
        XCTAssertEqual(sut.currentTime, 0)
    }

    /// Verifies that `pause()` transitions `playbackState` to `.paused`
    /// through the real HarmoniaPlaybackServiceAdapter → HarmoniaCore stack.
    ///
    /// This test confirms that our adapter wiring for `pause()` is correct —
    /// not just that `AppState` calls the method, but that the real
    /// HarmoniaCore service receives and handles it.
    func testIntegration_PauseSetsPausedState() async throws {
        let url = try bundleURL(forResource: "test_playback", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]
        await sut.play(trackID: track.id)

        await sut.pause()

        XCTAssertEqual(sut.playbackState, .paused)
    }

    /// Verifies that `seek(to:)` updates `currentTime` through the real
    /// HarmoniaPlaybackServiceAdapter → HarmoniaCore stack.
    ///
    /// This test confirms that our adapter wiring for `seek(to:)` is correct —
    /// not just that `AppState` calls the method, but that `currentTime`
    /// reflects the seek position after a real HarmoniaCore seek call.
    func testIntegration_SeekUpdatesCurrentTime() async throws {
        let url = try bundleURL(forResource: "test_playback", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]
        await sut.play(trackID: track.id)

        await sut.seek(to: 1.0)

        XCTAssertEqual(sut.currentTime, 1.0, accuracy: 0.5)
    }
    // MARK: - USLT Lyrics integration tests (Slice 9-J)
    //
    // Fixtures required (prepare with Python mutagen before commit 4):
    //   test_uslt_single.mp3    — 1 USLT frame: lang="eng", text="Verse one"
    //   test_uslt_multilang.mp3 — 2 USLT frames: eng "Verse one" + chi "第一段"
    //   test_uslt_no_lang.mp3   — 1 USLT frame: no language tag
    //
    // bundleURL(forResource:withExtension:) throws XCTSkip when fixture absent,
    // so these tests skip (yellow) until fixtures are added to the test bundle.

    /// One USLT frame with language "eng" → Track.lyrics has one variant,
    /// languageCode == "eng", text non-empty.
    func testIntegration_USLT_SingleVariant_MapsToTrackLyrics() async throws {
        let url = try bundleURL(forResource: "test_uslt_single", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]

        let lyrics = try XCTUnwrap(track.lyrics,
            "Track.lyrics should be non-nil for a file with embedded USLT")
        XCTAssertEqual(lyrics.count, 1)
        XCTAssertEqual(lyrics.first?.languageCode, "eng")
        XCTAssertFalse(lyrics.first?.text.isEmpty ?? true)
    }

    /// Two USLT frames (eng + chi) → Track.lyrics has two variants with correct codes.
    func testIntegration_USLT_MultipleVariants_ProducesCorrectLanguageCodes() async throws {
        let url = try bundleURL(forResource: "test_uslt_multilang", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]

        let lyrics = try XCTUnwrap(track.lyrics,
            "Track.lyrics should be non-nil for a file with 2 USLT frames")
        XCTAssertEqual(lyrics.count, 2)
        let codes = Set(lyrics.compactMap { $0.languageCode })
        XCTAssertTrue(codes.contains("eng"))
        XCTAssertTrue(codes.contains("chi"))
    }

    /// USLT frame with no declared language → Track.lyrics has one variant,
    /// languageCode == nil.
    func testIntegration_USLT_NilLanguageCode_ProducesVariantWithNilCode() async throws {
        let url = try bundleURL(forResource: "test_uslt_no_lang", withExtension: "mp3")
        await sut.load(urls: [url])
        let track = sut.playlist.tracks[0]

        let lyrics = try XCTUnwrap(track.lyrics,
            "Track.lyrics should be non-nil for a file with USLT (even without language code)")
        XCTAssertEqual(lyrics.count, 1)
        XCTAssertNil(lyrics.first?.languageCode)
    }
}
