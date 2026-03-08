//
//  AppStateMetadataTests.swift
//  HarmoniaPlayerTests
//
//  Slice 3-B: TagReaderService integration into AppState.load(urls:)
//

import XCTest
@testable import HarmoniaPlayer

// MARK: - Helpers

private func makeURL(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name).mp3")
}

// MARK: - Test Suite

/// Tests that `AppState.load(urls:)` calls `TagReaderService.readMetadata(for:)`
/// once per URL and stores the enriched `Track` (title, artist, album, duration)
/// in the playlist, rather than a URL-derived placeholder. Also verifies that
/// multiple URLs are each enriched independently and that the call remains additive.
///
/// `@MainActor` is required because `AppState` is `@MainActor` isolated.
@MainActor
final class AppStateMetadataTests: XCTestCase {

    // MARK: - Fixtures

    private var fakeTagReader: FakeTagReaderService!
    private var sut: AppState!

    override func setUp() async throws {
        try await super.setUp()
        fakeTagReader = FakeTagReaderService()
        let provider = FakeCoreProvider(tagReader: fakeTagReader)
        sut = AppState(iapManager: MockIAPManager(), provider: provider)
    }

    override func tearDown() async throws {
        sut = nil
        fakeTagReader = nil
        try await super.tearDown()
    }

    // MARK: - Tests: Call Count Verification

    /// Slice 3-B: `testLoad_CallsTagReaderForEachURL`
    ///
    /// Given 3 URLs,
    /// when `load(urls:)` is called,
    /// then `readMetadata(for:)` is called exactly once per URL (3 times total).
    func testLoad_CallsTagReaderForEachURL() async {
        // Given
        let urls = [makeURL("a"), makeURL("b"), makeURL("c")]

        // When
        await sut.load(urls: urls)

        // Then
        XCTAssertEqual(
            fakeTagReader.readMetadataCallCount, 3,
            "load(urls:) must call readMetadata once per URL"
        )
    }

    // MARK: - Tests: Metadata Field Mapping

    /// Slice 3-B: `testLoad_UsesMetadataTitle`
    ///
    /// Given a URL with a stubbed title "Real Title",
    /// when `load(urls:)` is called,
    /// then the track in the playlist has `title == "Real Title"`.
    func testLoad_UsesMetadataTitle() async {
        // Given
        let url = makeURL("song")
        fakeTagReader.stubbedMetadata[url] = Track(
            url: url,
            title: "Real Title",
            artist: "",
            album: ""
        )

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertEqual(
            sut.playlist.tracks.first?.title, "Real Title",
            "load(urls:) must use the title returned by TagReaderService"
        )
    }

    /// Slice 3-B: `testLoad_UsesMetadataArtist`
    ///
    /// Given a URL with a stubbed artist "Artist X",
    /// when `load(urls:)` is called,
    /// then the track in the playlist has `artist == "Artist X"`.
    func testLoad_UsesMetadataArtist() async {
        // Given
        let url = makeURL("song")
        fakeTagReader.stubbedMetadata[url] = Track(
            url: url,
            title: "Title",
            artist: "Artist X",
            album: ""
        )

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertEqual(
            sut.playlist.tracks.first?.artist, "Artist X",
            "load(urls:) must use the artist returned by TagReaderService"
        )
    }

    /// Slice 3-B: `testLoad_UsesMetadataAlbum`
    ///
    /// Given a URL with a stubbed album "Album Y",
    /// when `load(urls:)` is called,
    /// then the track in the playlist has `album == "Album Y"`.
    func testLoad_UsesMetadataAlbum() async {
        // Given
        let url = makeURL("song")
        fakeTagReader.stubbedMetadata[url] = Track(
            url: url,
            title: "Title",
            artist: "Artist",
            album: "Album Y"
        )

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertEqual(
            sut.playlist.tracks.first?.album, "Album Y",
            "load(urls:) must use the album returned by TagReaderService"
        )
    }

    /// Slice 3-B: `testLoad_UsesMetadataDuration`
    ///
    /// Given a URL with a stubbed duration of 180.0 seconds,
    /// when `load(urls:)` is called,
    /// then the track in the playlist has `duration == 180.0`.
    func testLoad_UsesMetadataDuration() async {
        // Given
        let url = makeURL("song")
        fakeTagReader.stubbedMetadata[url] = Track(
            url: url,
            title: "Title",
            artist: "Artist",
            album: "Album",
            duration: 180.0
        )

        // When
        await sut.load(urls: [url])

        // Then
        XCTAssertEqual(
            sut.playlist.tracks.first?.duration, 180.0,
            "load(urls:) must use the duration returned by TagReaderService"
        )
    }

    // MARK: - Tests: Multiple URLs

    /// Slice 3-B: `testLoad_MultipleURLs_AllEnriched`
    ///
    /// Given 2 URLs, each with distinct stubbed metadata,
    /// when `load(urls:)` is called,
    /// then both tracks in the playlist carry their respective metadata.
    func testLoad_MultipleURLs_AllEnriched() async {
        // Given
        let urlA = makeURL("track-a")
        let urlB = makeURL("track-b")
        fakeTagReader.stubbedMetadata[urlA] = Track(
            url: urlA,
            title: "Title A",
            artist: "Artist A",
            album: "Album A"
        )
        fakeTagReader.stubbedMetadata[urlB] = Track(
            url: urlB,
            title: "Title B",
            artist: "Artist B",
            album: "Album B"
        )

        // When
        await sut.load(urls: [urlA, urlB])

        // Then
        XCTAssertEqual(sut.playlist.count, 2)
        XCTAssertEqual(sut.playlist.tracks[0].title, "Title A",
                       "First track should have metadata from URL A")
        XCTAssertEqual(sut.playlist.tracks[1].title, "Title B",
                       "Second track should have metadata from URL B")
    }

    // MARK: - Tests: Additive Behaviour

    /// Slice 3-B: `testLoad_IsAdditive_WithMetadata`
    ///
    /// Given the playlist already contains 1 track,
    /// when `load(urls:)` is called with 1 more URL,
    /// then the playlist contains 2 tracks total.
    ///
    /// Verifies that the async metadata-enrichment path preserves
    /// additive behaviour (consistent with Slice 2 contract).
    func testLoad_IsAdditive_WithMetadata() async {
        // Given: Pre-load 1 track
        let urlA = makeURL("existing")
        fakeTagReader.stubbedMetadata[urlA] = Track(
            url: urlA,
            title: "Existing Track",
            artist: "",
            album: ""
        )
        await sut.load(urls: [urlA])
        XCTAssertEqual(sut.playlist.count, 1, "Pre-condition: playlist should have 1 track")

        // When: Load 1 more track
        let urlB = makeURL("new")
        fakeTagReader.stubbedMetadata[urlB] = Track(
            url: urlB,
            title: "New Track",
            artist: "",
            album: ""
        )
        await sut.load(urls: [urlB])

        // Then: Playlist has 2 tracks total
        XCTAssertEqual(
            sut.playlist.count, 2,
            "load(urls:) must remain additive when integrating metadata"
        )
        XCTAssertEqual(sut.playlist.tracks[0].title, "Existing Track")
        XCTAssertEqual(sut.playlist.tracks[1].title, "New Track")
    }
}
