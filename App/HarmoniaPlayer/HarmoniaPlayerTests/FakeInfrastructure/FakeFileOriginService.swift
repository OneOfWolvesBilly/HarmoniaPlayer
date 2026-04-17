//
//  FakeFileOriginService.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-04-17 (Slice 9-B).
//

import Foundation
@testable import HarmoniaPlayer

/// Fake FileOriginService for deterministic AppState tests.
///
/// In-memory backing store keyed by URL. Records call counts so tests can
/// verify exactly which method was invoked, and supports error stubs so
/// tests can simulate xattr-write or xattr-clear failures without touching
/// the real filesystem.
///
/// Not used by `FileOriginServiceTests` itself — the adapter's own tests
/// exercise the real `DarwinFileOriginAdapter` against temporary files.
///
/// **Usage — happy path:**
/// ```swift
/// let fake = FakeFileOriginService()
/// try fake.write(["https://example.com"], url: fileURL)
/// let read = fake.read(url: fileURL)
/// // read == ["https://example.com"]
/// ```
///
/// **Usage — error simulation:**
/// ```swift
/// fake.stubbedWriteError = FileOriginError.writeFailed("simulated")
/// // write(_:url:) will throw FileOriginError.writeFailed("simulated")
/// ```
final class FakeFileOriginService: FileOriginService {

    // MARK: - Call Recording

    /// Number of times `read(url:)` was called.
    private(set) var readCallCount = 0

    /// Number of times `write(_:url:)` was called.
    private(set) var writeCallCount = 0

    /// Number of times `clear(url:)` was called.
    private(set) var clearCallCount = 0

    /// Ordered list of URLs passed to `read(url:)`.
    private(set) var readURLs: [URL] = []

    /// Ordered list of `(sources, url)` tuples passed to `write(_:url:)`.
    private(set) var writeCalls: [(sources: [String], url: URL)] = []

    /// Ordered list of URLs passed to `clear(url:)`.
    private(set) var clearURLs: [URL] = []

    // MARK: - Stub Configuration

    /// In-memory backing store. Pre-seed to simulate existing xattrs.
    var storage: [URL: [String]] = [:]

    /// If set, `write(_:url:)` throws this error instead of updating storage.
    var stubbedWriteError: Error? = nil

    /// If set, `clear(url:)` throws this error instead of clearing storage.
    var stubbedClearError: Error? = nil

    // MARK: - FileOriginService

    func read(url: URL) -> [String] {
        readCallCount += 1
        readURLs.append(url)
        return storage[url] ?? []
    }

    func write(_ sources: [String], url: URL) throws {
        writeCallCount += 1
        writeCalls.append((sources: sources, url: url))
        if let error = stubbedWriteError { throw error }
        storage[url] = sources
    }

    func clear(url: URL) throws {
        clearCallCount += 1
        clearURLs.append(url)
        if let error = stubbedClearError { throw error }
        storage.removeValue(forKey: url)
    }
}
