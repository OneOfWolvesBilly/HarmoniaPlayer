//
//  FakeCoreProvider.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-15.
//

import Foundation
@testable import HarmoniaPlayer

/// Fake service provider for testing
///
/// Records method calls for verification in tests.
/// Returns mock service implementations.
///
/// **Usage:**
/// ```swift
/// let fake = FakeCoreProvider()
/// let factory = CoreFactory(featureFlags: flags, provider: fake)
/// _ = factory.makePlaybackService()
///
/// XCTAssertEqual(fake.makePlaybackServiceCallCount, 1)
/// XCTAssertTrue(fake.lastIsProUser!)
/// ```
final class FakeCoreProvider: CoreServiceProviding {
    
    // MARK: - Call Recording
    
    /// Number of times makePlaybackService was called
    private(set) var makePlaybackServiceCallCount = 0
    
    /// Last isProUser parameter passed to makePlaybackService
    private(set) var lastIsProUser: Bool?
    
    /// Number of times makeTagReaderService was called
    private(set) var makeTagReaderServiceCallCount = 0
    
    // MARK: - CoreServiceProviding
    
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        makePlaybackServiceCallCount += 1
        lastIsProUser = isProUser
        return FakePlaybackService()
    }
    
    func makeTagReaderService() -> TagReaderService {
        makeTagReaderServiceCallCount += 1
        return FakeTagReaderService()
    }
}

// MARK: - Mock Services

/// Minimal playback service for testing
private final class FakePlaybackService: PlaybackService {
    var state: PlaybackState = .idle
    
    func load(url: URL) async throws {
        state = .loading
    }
    
    func play() async throws {
        state = .playing
    }
    
    func pause() async {
        state = .paused
    }
    
    func stop() async {
        state = .stopped
    }
    
    func seek(to seconds: TimeInterval) async throws {
        // No-op
    }
    
    func currentTime() async -> TimeInterval {
        return 0
    }
    
    func duration() async -> TimeInterval {
        return 0
    }
}

/// Minimal tag reader for testing
private final class FakeTagReaderService: TagReaderService {
    func readMetadata(for url: URL) async throws -> Track {
        return Track(url: url)
    }
}
