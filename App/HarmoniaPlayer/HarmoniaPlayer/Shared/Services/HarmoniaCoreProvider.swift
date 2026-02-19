//
//  HarmoniaCoreProvider.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation
// TODO: import HarmoniaCore when implementing real services

/// Production service provider for HarmoniaCore integration
///
/// **Slice 1 Status:** Placeholder implementation
///
/// This provider will create real HarmoniaCore service instances in later slices.
/// For now, it returns minimal placeholder implementations to validate the architecture.
///
/// **Future Implementation:**
/// - Slice 2: Playlist management services
/// - Slice 3: Metadata extraction services
/// - Slice 4: Full playback orchestration
///
/// **Design:**
/// - Only this class imports HarmoniaCore-Swift
/// - Constructs adapters and services
/// - Configures Free vs Pro decoders
final class HarmoniaCoreProvider: CoreServiceProviding {
    
    // MARK: - CoreServiceProviding
    
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        // TODO (Slice 4): Create real HarmoniaCore playback service
        // For now, return placeholder
        return PlaceholderPlaybackService(isProUser: isProUser)
    }
    
    func makeTagReaderService() -> TagReaderService {
        // TODO (Slice 3): Create real HarmoniaCore tag reader
        // For now, return placeholder
        return PlaceholderTagReaderService()
    }
}

// MARK: - Placeholder Implementations

/// Placeholder playback service for Slice 1
///
/// Returns minimal implementation to validate architecture.
/// Real implementation added in Slice 4.
final class PlaceholderPlaybackService: PlaybackService {
    
    let isProUser: Bool
    var state: PlaybackState = .idle
    
    init(isProUser: Bool) {
        self.isProUser = isProUser
    }
    
    func load(url: URL) async throws {
        // Placeholder: just update state
        state = .loading
    }
    
    func play() async throws {
        // Placeholder: just update state
        state = .playing
    }
    
    func pause() async {
        state = .paused
    }
    
    func stop() async {
        state = .stopped
    }
    
    func seek(to seconds: TimeInterval) async throws {
        // Placeholder: no-op
    }
    
    func currentTime() async -> TimeInterval {
        return 0
    }
    
    func duration() async -> TimeInterval {
        return 0
    }
}

/// Placeholder tag reader service for Slice 1
///
/// Returns minimal Track with filename as title.
/// Real metadata extraction added in Slice 3.
final class PlaceholderTagReaderService: TagReaderService {
    
    func readMetadata(for url: URL) async throws -> Track {
        // Placeholder: return Track with filename as title
        return Track(url: url)
    }
}
