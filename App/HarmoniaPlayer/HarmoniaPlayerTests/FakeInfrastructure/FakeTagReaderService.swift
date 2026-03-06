//
//  FakeTagReaderService.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-25.
//  Moved from SharedTests/ to FakeInfrastructure/ in Slice 3-A.
//

import Foundation
@testable import HarmoniaPlayer

/// Fake TagReaderService for deterministic test setups.
///
/// Supports per-URL metadata stubs and error stubs, enabling
/// Slice 3-B and 3-C tests to control exactly what metadata is returned
/// or what error is thrown for each URL.
///
/// **Default behaviour (no stub configured):**
/// Returns `Track(url:)` — a URL-derived placeholder, same as Slice 1 baseline.
///
/// **Stub priority:**
/// `stubbedErrors` takes precedence over `stubbedMetadata`. If both are set
/// for the same URL, the error is thrown and the metadata stub is ignored.
///
/// **Usage — happy path:**
/// ```swift
/// let fake = FakeTagReaderService()
/// let url = URL(fileURLWithPath: "/tmp/song.mp3")
/// fake.stubbedMetadata[url] = Track(url: url, title: "Real Title", artist: "Artist X")
///
/// let track = try await fake.readMetadata(for: url)
/// // track.title == "Real Title"
/// ```
///
/// **Usage — error simulation:**
/// ```swift
/// fake.stubbedErrors[url] = PlaybackError.failedToOpenFile
/// // readMetadata(for: url) will throw PlaybackError.failedToOpenFile
/// ```
final class FakeTagReaderService: TagReaderService {

    // MARK: - Call Recording

    /// Total number of times `readMetadata(for:)` has been called.
    private(set) var readMetadataCallCount = 0

    /// Ordered list of URLs passed to `readMetadata(for:)`.
    ///
    /// Use this to verify both the number of calls and the order in which
    /// URLs were requested.
    private(set) var requestedURLs: [URL] = []

    // MARK: - Stub Configuration

    /// Per-URL metadata stubs.
    ///
    /// When a URL is present in this dictionary, `readMetadata(for:)` returns
    /// the associated `Track` instead of a URL-derived placeholder.
    ///
    /// Ignored if `stubbedErrors[url]` is also set (errors take precedence).
    var stubbedMetadata: [URL: Track] = [:]

    /// Per-URL error stubs.
    ///
    /// When a URL is present in this dictionary, `readMetadata(for:)` throws
    /// the associated error. Takes precedence over `stubbedMetadata`.
    var stubbedErrors: [URL: Error] = [:]

    // MARK: - TagReaderService

    func readMetadata(for url: URL) async throws -> Track {
        readMetadataCallCount += 1
        requestedURLs.append(url)

        if let error = stubbedErrors[url] { throw error }
        return stubbedMetadata[url] ?? Track(url: url)
    }
}