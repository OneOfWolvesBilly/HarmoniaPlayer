//
//  AppStateErrorHandlingTests.swift
//  HarmoniaPlayerTests
//
//  Slice 3-C: Graceful degradation — metadata error → URL-derived Track + lastError
//

import XCTest
@testable import HarmoniaPlayer

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
        sut = AppState(iapManager: MockIAPManager(), provider: provider, userDefaults: testDefaults)
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

    // MARK: - Slice 9-F: lastErrorDetail

    /// Loads one track into the SUT's playlist and returns it.
    private func loadOneTrack(named name: String = "test-track") async -> Track {
        let url = URL(fileURLWithPath: "/tmp/\(name).mp3")
        await sut.load(urls: [url])
        return sut.playlist.tracks[0]
    }

    /// Slice 9-F: `testLastErrorDetail_PlayTrackDecodeFailure_ContainsCodeAndPath`
    ///
    /// Given `play(trackID:)` throws `.failedToDecode`,
    /// when the error occurs,
    /// then `lastErrorDetail` contains `"failedToDecode"` and `track.url.path`.
    func testLastErrorDetail_PlayTrackDecodeFailure_ContainsCodeAndPath() async throws {
        // Given
        fakePlaybackService.stubbedLoadError = PlaybackError.failedToDecode
        let track = await loadOneTrack(named: "decode-fail")

        // When
        await sut.play(trackID: track.id)

        // Then
        let detail = try XCTUnwrap(sut.lastErrorDetail, "lastErrorDetail must be set on play(trackID:) failure")
        XCTAssertTrue(
            detail.contains("failedToDecode"),
            "lastErrorDetail must contain error code, got: \(detail)"
        )
        XCTAssertTrue(
            detail.contains(track.url.path),
            "lastErrorDetail must contain track.url.path, got: \(detail)"
        )
    }

    /// Slice 9-F: `testLastErrorDetail_InaccessibleTrack_ContainsCodeAndPath`
    ///
    /// Given `play(trackID:)` is called with an inaccessible track,
    /// when the inaccessibility gate trips,
    /// then `lastErrorDetail` contains `"failedToOpenFile"` and `track.url.path`.
    func testLastErrorDetail_InaccessibleTrack_ContainsCodeAndPath() async throws {
        // Given
        let track = await loadOneTrack(named: "inaccessible")
        sut.playlists[0].tracks[0].isAccessible = false

        // When
        await sut.play(trackID: track.id)

        // Then
        let detail = try XCTUnwrap(sut.lastErrorDetail, "lastErrorDetail must be set when inaccessibility gate trips")
        XCTAssertTrue(
            detail.contains("failedToOpenFile"),
            "lastErrorDetail must contain error code, got: \(detail)"
        )
        XCTAssertTrue(
            detail.contains(track.url.path),
            "lastErrorDetail must contain track.url.path, got: \(detail)"
        )
    }

    /// Slice 9-F: `testLastErrorDetail_SeekFailure_ContainsCodeAndNoTrack`
    ///
    /// Given `seek(to:)` throws,
    /// when the error occurs,
    /// then `lastErrorDetail` contains the error code and `"(no active track)"`
    /// because the seek catch path does not know which track it was seeking in.
    func testLastErrorDetail_SeekFailure_ContainsCodeAndNoTrack() async throws {
        // Given
        fakePlaybackService.stubbedSeekError = PlaybackError.invalidState

        // When
        await sut.seek(to: 30)

        // Then
        let detail = try XCTUnwrap(sut.lastErrorDetail, "lastErrorDetail must be set on seek failure")
        XCTAssertTrue(
            detail.contains("invalidState"),
            "lastErrorDetail must contain error code, got: \(detail)"
        )
        XCTAssertTrue(
            detail.contains("(no active track)"),
            "lastErrorDetail must contain '(no active track)' marker on seek catch path, got: \(detail)"
        )
    }

    /// Slice 9-F: `testLastErrorDetail_ClearedOnClearLastError`
    ///
    /// Given `lastErrorDetail` is set,
    /// when `clearLastError()` is called,
    /// then `lastErrorDetail` is `nil`.
    func testLastErrorDetail_ClearedOnClearLastError() {
        // Given
        sut.lastErrorDetail = "failedToDecode: /tmp/some/path.mp3"
        XCTAssertNotNil(sut.lastErrorDetail, "precondition: lastErrorDetail must be set before clearLastError")

        // When
        sut.clearLastError()

        // Then
        XCTAssertNil(
            sut.lastErrorDetail,
            "clearLastError() must set lastErrorDetail to nil"
        )
    }
}
