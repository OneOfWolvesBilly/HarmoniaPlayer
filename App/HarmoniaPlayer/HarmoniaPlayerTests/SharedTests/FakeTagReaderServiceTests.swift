//
//  FakeTagReaderServiceTests.swift
//  HarmoniaPlayerTests
//
//  Slice 3-A: Verify FakeTagReaderService stub behaviour and call recording.
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for the upgraded FakeTagReaderService (Slice 3-A).
///
/// Verifies stub behaviour, error simulation, and call recording
/// so that Slice 3-B and 3-C tests can rely on this fake with confidence.
///
/// **Swift 6 / Xcode 26 note:**
/// `@MainActor` is required because test methods access `Track` properties
/// inside `XCTAssertEqual` autoclosures. Xcode 26 beta infers `@MainActor`
/// on `Track` properties due to their use in `AppState`, causing warnings
/// when accessed from a nonisolated context.
@MainActor
final class FakeTagReaderServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeURL(_ filename: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(filename).mp3")
    }

    // MARK: - Slice 3-A: Default Behaviour

    /// testFake_DefaultBehaviour
    ///
    /// Given: No stub configured for the URL
    /// When:  `readMetadata(for:)` is called
    /// Then:  Returns `Track(url:)` — a URL-derived placeholder
    func testFake_DefaultBehaviour() async throws {
        // Given
        let fake = FakeTagReaderService()
        let url = makeURL("unknown-song")

        // When
        let track = try await fake.readMetadata(for: url)

        // Then: title derived from filename, no metadata enrichment
        XCTAssertEqual(track.url, url)
        XCTAssertEqual(track.title, "unknown-song",
                       "Default behaviour should derive title from filename")
        XCTAssertEqual(track.artist, "",
                       "Default behaviour should leave artist empty")
        XCTAssertEqual(track.album, "",
                       "Default behaviour should leave album empty")
        XCTAssertEqual(track.duration, 0,
                     "Default behaviour should default duration to 0")
    }

    // MARK: - Slice 3-A: Stubbed Metadata

    /// testFake_StubbedMetadata
    ///
    /// Given: `stubbedMetadata[url]` is configured with a specific Track
    /// When:  `readMetadata(for:)` is called with that URL
    /// Then:  Returns the stubbed Track, not a URL-derived placeholder
    func testFake_StubbedMetadata() async throws {
        // Given
        let fake = FakeTagReaderService()
        let url = makeURL("stubbed-song")
        let expectedTrack = Track(
            url: url,
            title: "Real Title",
            artist: "Artist X",
            album: "Album Y",
            duration: 180.0
        )
        fake.stubbedMetadata[url] = expectedTrack

        // When
        let track = try await fake.readMetadata(for: url)

        // Then
        XCTAssertEqual(track, expectedTrack,
                       "Should return the stubbed Track instance")
        XCTAssertEqual(track.title, "Real Title")
        XCTAssertEqual(track.artist, "Artist X")
        XCTAssertEqual(track.album, "Album Y")
        XCTAssertEqual(track.duration, 180.0)
    }

    // MARK: - Slice 3-A: Stubbed Error

    /// testFake_StubbedError
    ///
    /// Given: `stubbedErrors[url]` is configured with an error
    /// When:  `readMetadata(for:)` is called with that URL
    /// Then:  Throws the stubbed error (not returning a Track)
    func testFake_StubbedError() async {
        // Given
        let fake = FakeTagReaderService()
        let url = makeURL("broken-file")
        let expectedError = PlaybackError.failedToOpenFile
        fake.stubbedErrors[url] = expectedError

        // When / Then
        do {
            _ = try await fake.readMetadata(for: url)
            XCTFail("Expected error to be thrown, but readMetadata succeeded")
        } catch let error as PlaybackError {
            XCTAssertEqual(error, expectedError,
                           "Should throw the exact stubbed error")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// testFake_StubbedError_TakesPrecedenceOverMetadata
    ///
    /// Given: Both `stubbedErrors[url]` and `stubbedMetadata[url]` are set
    /// When:  `readMetadata(for:)` is called
    /// Then:  Error is thrown — errors take precedence over metadata stubs
    func testFake_StubbedError_TakesPrecedenceOverMetadata() async {
        // Given
        let fake = FakeTagReaderService()
        let url = makeURL("conflict-file")
        fake.stubbedMetadata[url] = Track(url: url, title: "Should Not Return")
        fake.stubbedErrors[url] = PlaybackError.failedToDecode

        // When / Then
        do {
            _ = try await fake.readMetadata(for: url)
            XCTFail("Expected error to be thrown")
        } catch let error as PlaybackError {
            XCTAssertEqual(error, .failedToDecode,
                           "Error stub should take precedence over metadata stub")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Slice 3-A: Call Recording — Count

    /// testFake_RecordsCallCount
    ///
    /// Given: Any stub configuration (or none)
    /// When:  `readMetadata(for:)` is called 3 times
    /// Then:  `readMetadataCallCount == 3`
    func testFake_RecordsCallCount() async throws {
        // Given
        let fake = FakeTagReaderService()
        let urls = [makeURL("a"), makeURL("b"), makeURL("c")]

        // When
        for url in urls {
            _ = try? await fake.readMetadata(for: url)
        }

        // Then
        XCTAssertEqual(fake.readMetadataCallCount, 3,
                       "Call count should match the number of readMetadata calls")
    }

    /// testFake_RecordsCallCount_ZeroOnInit
    ///
    /// Given: Freshly created FakeTagReaderService
    /// When:  No calls made
    /// Then:  `readMetadataCallCount == 0`
    func testFake_RecordsCallCount_ZeroOnInit() {
        let fake = FakeTagReaderService()
        XCTAssertEqual(fake.readMetadataCallCount, 0,
                       "callCount should be 0 before any calls")
    }

    // MARK: - Slice 3-A: Call Recording — URLs

    /// testFake_RecordsURLs
    ///
    /// Given: Any stub configuration (or none)
    /// When:  `readMetadata(for: url1)`, then `readMetadata(for: url2)`
    /// Then:  `requestedURLs == [url1, url2]` (order preserved)
    func testFake_RecordsURLs() async throws {
        // Given
        let fake = FakeTagReaderService()
        let url1 = makeURL("first")
        let url2 = makeURL("second")

        // When
        _ = try? await fake.readMetadata(for: url1)
        _ = try? await fake.readMetadata(for: url2)

        // Then
        XCTAssertEqual(fake.requestedURLs, [url1, url2],
                       "requestedURLs should record calls in order")
    }

    /// testFake_RecordsURLs_EmptyOnInit
    ///
    /// Given: Freshly created FakeTagReaderService
    /// When:  No calls made
    /// Then:  `requestedURLs` is empty
    func testFake_RecordsURLs_EmptyOnInit() {
        let fake = FakeTagReaderService()
        XCTAssertTrue(fake.requestedURLs.isEmpty,
                      "requestedURLs should be empty before any calls")
    }

    /// testFake_RecordsURLs_IncludingOnError
    ///
    /// Given: `stubbedErrors[url]` set so readMetadata throws
    /// When:  `readMetadata(for: url)` is called (and throws)
    /// Then:  URL is still recorded in `requestedURLs`
    func testFake_RecordsURLs_IncludingOnError() async {
        // Given
        let fake = FakeTagReaderService()
        let url = makeURL("error-file")
        fake.stubbedErrors[url] = PlaybackError.failedToOpenFile

        // When
        _ = try? await fake.readMetadata(for: url)

        // Then: URL is recorded even on error
        XCTAssertEqual(fake.requestedURLs, [url],
                       "requestedURLs should record the URL even when an error is thrown")
        XCTAssertEqual(fake.readMetadataCallCount, 1,
                       "callCount should be 1 even when an error is thrown")
    }

    // MARK: - Slice 3-A: Isolation Between URLs

    /// testFake_StubIsolation_DifferentURLs
    ///
    /// Given: Two URLs with different stubs (one metadata, one error)
    /// When:  Both are called
    /// Then:  Each URL receives its own stub behaviour
    func testFake_StubIsolation_DifferentURLs() async {
        // Given
        let fake = FakeTagReaderService()
        let goodURL = makeURL("good-song")
        let badURL = makeURL("bad-song")

        let expectedTrack = Track(url: goodURL, title: "Good Song")
        fake.stubbedMetadata[goodURL] = expectedTrack
        fake.stubbedErrors[badURL] = PlaybackError.failedToDecode

        // When / Then — good URL returns track
        do {
            let track = try await fake.readMetadata(for: goodURL)
            XCTAssertEqual(track, expectedTrack)
        } catch {
            XCTFail("goodURL should not throw: \(error)")
        }

        // When / Then — bad URL throws error
        do {
            _ = try await fake.readMetadata(for: badURL)
            XCTFail("badURL should have thrown")
        } catch let error as PlaybackError {
            XCTAssertEqual(error, .failedToDecode)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
