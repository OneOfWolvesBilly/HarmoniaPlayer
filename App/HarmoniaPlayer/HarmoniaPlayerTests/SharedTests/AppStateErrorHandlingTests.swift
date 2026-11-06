//
//  AppStateErrorHandlingTests.swift
//  HarmoniaPlayerTests
//
//  Slice 3-C: Graceful degradation — metadata error → URL-derived Track + lastError
//

import XCTest
@testable import Harmonia_Player

// MARK: - Helpers

private func makeURL(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name).mp3")
}

// MARK: - Test Suite

/// Tests that `AppState.load(urls:)` handles `TagReaderService` errors gracefully:
/// falling back to a URL-derived `Track` and recording the failure in `lastError`.
///
/// `@MainActor` is required because `AppState` is `@MainActor` isolated.
@MainActor
final class AppStateErrorHandlingTests: XCTestCase {

    // MARK: - Fixtures

    private var fakeTagReader: FakeTagReaderService!
    private var fakePlaybackService: FakePlaybackService!
    private var sut: AppState!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        fakeTagReader = FakeTagReaderService()
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(
            playbackService: fakePlaybackService,
            tagReader: fakeTagReader
        )
        sut = AppState(iapManager: MockIAPManager(), provider: provider, userDefaults: testDefaults, playlistStore: FakePlaylistStore())
    }

    override func tearDown() async throws {
        sut = nil
        fakeTagReader = nil
        fakePlaybackService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Slice 3-C: `testLoad_MetadataError_FallsBackToURLDerivedTrack`
    ///
    /// Given a URL with a stubbed error,
    /// when `load(urls:)` is called,
    /// then the playlist contains a track whose title equals the filename (URL-derived fallback).
    func testLoad_MetadataError_FallsBackToURLDerivedTrack() async {
        // Given
        let url = makeURL("song")
        fakeTagReader.stubbedErrors[url] = PlaybackError.failedToOpenFile

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertEqual(
            sut.playlist.tracks.first?.title, "song",
            "On metadata error, track title must be derived from the URL filename"
        )
    }

    /// Slice 3-C: `testLoad_MetadataError_SetsLastError`
    ///
    /// Given a URL with a stubbed error,
    /// when `load(urls:)` is called,
    /// then `lastError` is set to `.failedToOpenFile`.
    func testLoad_MetadataError_SetsLastError() async {
        // Given
        let url = makeURL("song")
        fakeTagReader.stubbedErrors[url] = PlaybackError.failedToOpenFile

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertEqual(
            sut.lastError, .failedToOpenFile,
            "On metadata error, lastError must be set to .failedToOpenFile"
        )
    }

    /// Slice 3-C: `testLoad_PartialError_SuccessfulURLsStillEnriched`
    ///
    /// Given 2 URLs — one with stubbed metadata and one with a stubbed error —
    /// when `load(urls:)` is called,
    /// then the successful URL is enriched and the failing URL falls back to URL-derived.
    func testLoad_PartialError_SuccessfulURLsStillEnriched() async {
        // Given
        let goodURL = makeURL("good")
        let badURL = makeURL("bad")
        fakeTagReader.stubbedMetadata[goodURL] = Track(
            url: goodURL,
            title: "Good Track",
            artist: "Artist",
            album: "Album"
        )
        fakeTagReader.stubbedErrors[badURL] = PlaybackError.failedToOpenFile

        // When
        await sut.load(urls: [goodURL, badURL])

        // Then
        XCTAssertEqual(sut.playlist.count, 2)
        XCTAssertEqual(
            sut.playlist.tracks[0].title, "Good Track",
            "Successful URL must still be enriched with metadata"
        )
        XCTAssertEqual(
            sut.playlist.tracks[1].title, "bad",
            "Erroring URL must fall back to URL-derived title"
        )
    }

    /// Slice 3-C: `testLoad_NoError_LastErrorRemainsNil`
    ///
    /// Given all URLs have valid stubbed metadata (no errors),
    /// when `load(urls:)` is called,
    /// then `lastError` remains `nil`.
    func testLoad_NoError_LastErrorRemainsNil() async {
        // Given
        let url = makeURL("clean")
        fakeTagReader.stubbedMetadata[url] = Track(
            url: url,
            title: "Clean Track",
            artist: "",
            album: ""
        )

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertNil(
            sut.lastError,
            "lastError must remain nil when all metadata reads succeed"
        )
    }

    /// Slice 3-C: `testLoad_MultipleErrors_LastErrorIsSet`
    ///
    /// Given 2 URLs both with stubbed errors,
    /// when `load(urls:)` is called,
    /// then `lastError` is not nil.
    func testLoad_MultipleErrors_LastErrorIsSet() async {
        // Given
        let urlA = makeURL("a")
        let urlB = makeURL("b")
        fakeTagReader.stubbedErrors[urlA] = PlaybackError.failedToOpenFile
        fakeTagReader.stubbedErrors[urlB] = PlaybackError.failedToOpenFile

        // When
        await sut.load(urls: [urlA, urlB])

        // Then
        XCTAssertNotNil(
            sut.lastError,
            "lastError must be set when at least one metadata read fails"
        )
    }

    // MARK: - Error dismissal wiring

    /// Given the playback controller is in `.error(…)` and the alert store's
    /// error surface is populated,
    /// when `alertCenter.clearLastError()` is called (the error alert's
    /// dismiss action),
    /// then the controller's `playbackState` becomes `.stopped` through the
    /// root-wired `onErrorCleared` closure and the store's surface is cleared.
    func testClearLastError_ErrorState_BecomesStopped() {
        // Given
        sut.playbackController.playbackState = .error(.failedToDecode)
        sut.alertCenter.lastError = .failedToDecode
        sut.alertCenter.lastErrorDetail = "failedToDecode: /tmp/broken.mp3"
        sut.alertCenter.failedTrackName = "Broken Track"
        sut.alertCenter.showFileNotFoundAlert = true
        sut.alertCenter.skippedInaccessibleNames = ["Broken Track"]

        // When
        sut.alertCenter.clearLastError()

        // Then
        XCTAssertEqual(sut.playbackController.playbackState, .stopped,
                       "dismissing the error alert must transition the controller from .error to .stopped")
        XCTAssertNil(sut.alertCenter.lastError,
                     "clearLastError() must clear the store's lastError")
        XCTAssertNil(sut.alertCenter.lastErrorDetail,
                     "clearLastError() must clear the store's lastErrorDetail")
        XCTAssertNil(sut.alertCenter.failedTrackName,
                     "clearLastError() must clear the store's failedTrackName")
        XCTAssertFalse(sut.alertCenter.showFileNotFoundAlert,
                       "clearLastError() must lower the store's showFileNotFoundAlert")
        XCTAssertTrue(sut.alertCenter.skippedInaccessibleNames.isEmpty,
                      "clearLastError() must clear the store's skippedInaccessibleNames")
    }
}
