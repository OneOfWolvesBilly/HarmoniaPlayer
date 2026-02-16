//
//  CoreServiceProviding.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Provider abstraction for HarmoniaCore services
///
/// This protocol enables dependency injection and testability by abstracting
/// HarmoniaCore service creation. Production code uses `HarmoniaCoreProvider`
/// while tests use `FakeCoreProvider`.
///
/// **Design:**
/// - Factory methods return protocol types (not concrete classes)
/// - Takes configuration (Free/Pro) as parameters
/// - No direct HarmoniaCore imports (only in concrete provider)
///
/// **Usage:**
/// ```swift
/// let factory = CoreFactory(provider: HarmoniaCoreProvider())
/// let playback = factory.makePlaybackService(isProUser: true)
/// ```
protocol CoreServiceProviding {
    
    /// Create a playback service configured for Free or Pro tier
    ///
    /// - Parameter isProUser: Whether Pro features are unlocked
    /// - Returns: PlaybackService instance with appropriate decoder configuration
    ///
    /// **Configuration:**
    /// - Free: Standard formats only (MP3, AAC, ALAC, WAV, AIFF)
    /// - Pro: Adds FLAC, DSD support
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    
    /// Create a tag reader service for metadata extraction
    ///
    /// - Returns: TagReaderService instance
    ///
    /// **Note:** Tag reading is available in both Free and Pro tiers
    func makeTagReaderService() -> TagReaderService
}
