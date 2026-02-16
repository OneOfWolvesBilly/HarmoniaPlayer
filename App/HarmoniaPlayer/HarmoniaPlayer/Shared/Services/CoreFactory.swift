//
//  CoreFactory.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Core service factory (composition root)
///
/// **Single integration point** for HarmoniaCore services.
/// This is the ONLY class in HarmoniaPlayer that is allowed to create
/// HarmoniaCore service instances.
///
/// **Design:**
/// - Uses provider pattern for testability
/// - Holds feature flags to configure services
/// - Production uses `HarmoniaCoreProvider`
/// - Tests use `FakeCoreProvider`
///
/// **Usage:**
/// ```swift
/// let flags = CoreFeatureFlags(iapManager: iapManager)
/// let factory = CoreFactory(
///     featureFlags: flags,
///     provider: HarmoniaCoreProvider()
/// )
/// let playback = factory.makePlaybackService()
/// ```
struct CoreFactory {
    
    // MARK: - Properties
    
    /// Feature flags determining available functionality
    let featureFlags: CoreFeatureFlags
    
    /// Service provider (real or fake)
    private let provider: CoreServiceProviding
    
    // MARK: - Initialization
    
    /// Initialize factory with feature flags and provider
    ///
    /// - Parameters:
    ///   - featureFlags: Feature configuration (Free vs Pro)
    ///   - provider: Service provider implementation
    init(featureFlags: CoreFeatureFlags, provider: CoreServiceProviding) {
        self.featureFlags = featureFlags
        self.provider = provider
    }
    
    // MARK: - Service Creation
    
    /// Create playback service
    ///
    /// Service is configured based on feature flags:
    /// - Free: Standard formats only
    /// - Pro: Adds FLAC/DSD support
    ///
    /// - Returns: PlaybackService instance
    func makePlaybackService() -> PlaybackService {
        // Determine Pro status from feature flags
        // (if FLAC is supported, user is Pro)
        let isProUser = featureFlags.supportsFLAC
        
        return provider.makePlaybackService(isProUser: isProUser)
    }
    
    /// Create tag reader service
    ///
    /// Tag reading is available in both Free and Pro tiers.
    ///
    /// - Returns: TagReaderService instance
    func makeTagReaderService() -> TagReaderService {
        return provider.makeTagReaderService()
    }
}
