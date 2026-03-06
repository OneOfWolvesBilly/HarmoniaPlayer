//
//  FakeTagReaderService.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-25.
//

import Foundation
@testable import HarmoniaPlayer

/// Fake TagReaderService for Slice 1-F wiring verification.
///
/// Records `readMetadata(for:)` call count so tests can assert
/// that `AppState.init` does not trigger metadata reads.
///
/// Slice 3-A will upgrade this fake with stub support and move it
/// to `HarmoniaPlayerTests/Fakes/`.
final class FakeTagReaderService: TagReaderService {

    // MARK: - Call Recording

    /// Number of times `readMetadata(for:)` was called.
    /// Must remain 0 after `AppState.init` completes.
    private(set) var readMetadataCallCount = 0

    // MARK: - TagReaderService

    func readMetadata(for url: URL) async throws -> Track {
        readMetadataCallCount += 1
        return Track(url: url)
    }
}