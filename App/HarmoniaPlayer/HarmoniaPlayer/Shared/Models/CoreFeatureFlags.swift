//
//  CoreFeatureFlags.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-12.
//

import Foundation

/// Feature flag system for Free vs Pro tier differentiation
///
/// This struct defines which features are available based on product tier.
/// It is derived from `IAPManager.isProUnlocked` and is immutable once created.
///
/// **Free Tier:**
/// - Audio formats: MP3, AAC, ALAC, WAV, AIFF
/// - Basic playback features
///
/// **Pro Tier:**
/// - All Free features
/// - Additional formats: FLAC, DSD
/// - Advanced features: Gapless playback, Metadata editing, Bit-perfect output
///
/// **Usage:**
/// ```swift
/// let flags = CoreFeatureFlags(iapManager: iapManager)
/// if flags.supportsFLAC {
///     // Load FLAC file
/// } else {
///     // Show Pro upgrade prompt
/// }
/// ```
///
/// **Design:**
/// - Immutable struct (all properties are `let`)
/// - No dependencies on HarmoniaCore (app-layer logic)
/// - Single source of truth for feature availability
struct CoreFeatureFlags {
    
    // MARK: - Audio Format Support
    
    /// MP3 format support (Free + Pro)
    let supportsMP3: Bool
    
    /// AAC/M4A format support (Free + Pro)
    let supportsAAC: Bool
    
    /// Apple Lossless (ALAC) format support (Free + Pro)
    let supportsALAC: Bool
    
    /// WAV format support (Free + Pro)
    let supportsWAV: Bool
    
    /// AIFF format support (Free + Pro)
    let supportsAIFF: Bool
    
    /// FLAC format support (Pro only)
    let supportsFLAC: Bool
    
    /// DSD (DSF/DFF) format support (Pro only)
    let supportsDSD: Bool
    
    // MARK: - Advanced Features
    
    /// Gapless playback support (Pro only)
    ///
    /// Enables seamless transitions between tracks without silence.
    /// Planned for v0.4.
    let supportsGaplessPlayback: Bool
    
    /// Metadata editing support (Pro only)
    ///
    /// Allows editing track tags (title, artist, album, etc.).
    /// Planned for v0.2.
    let supportsMetadataEditing: Bool
    
    /// Bit-perfect audio output support (Pro only)
    ///
    /// Bypasses system audio processing for purist playback.
    /// Planned for v0.2.
    let supportsBitPerfectOutput: Bool
    
    // MARK: - Initialization
    
    /// Initialize feature flags based on product tier
    ///
    /// - Parameter isPro: Whether user has Pro tier unlocked
    init(isPro: Bool) {
        // Free formats (always available)
        self.supportsMP3 = true
        self.supportsAAC = true
        self.supportsALAC = true
        self.supportsWAV = true
        self.supportsAIFF = true
        
        // Pro-only formats
        self.supportsFLAC = isPro
        self.supportsDSD = isPro
        
        // Pro-only features
        self.supportsGaplessPlayback = isPro
        self.supportsMetadataEditing = isPro
        self.supportsBitPerfectOutput = isPro
    }
    
    /// Convenience initializer from IAPManager
    ///
    /// - Parameter iapManager: IAP manager to query Pro status
    init(iapManager: IAPManager) {
        self.init(isPro: iapManager.isProUnlocked)
    }
}
