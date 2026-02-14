//
//  CoreFeatureFlagsTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-12.
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for CoreFeatureFlags
///
/// Tests the feature flag system that determines which features are available
/// based on Free vs Pro tier.
///
/// Test Coverage:
/// - Free tier configuration
/// - Pro tier configuration
/// - Initialization from IAPManager
/// - Feature flag correctness
final class CoreFeatureFlagsTests: XCTestCase {
    
    // MARK: - Free Tier Tests
    
    func testFreeConfiguration_HasBasicFormats() {
        // Given: Free tier
        let flags = CoreFeatureFlags(isPro: false)
        
        // Then: Basic formats should be available
        XCTAssertTrue(flags.supportsMP3, "MP3 should be available in Free")
        XCTAssertTrue(flags.supportsAAC, "AAC should be available in Free")
        XCTAssertTrue(flags.supportsALAC, "ALAC should be available in Free")
        XCTAssertTrue(flags.supportsWAV, "WAV should be available in Free")
        XCTAssertTrue(flags.supportsAIFF, "AIFF should be available in Free")
    }
    
    func testFreeConfiguration_DoesNotHaveProFormats() {
        // Given: Free tier
        let flags = CoreFeatureFlags(isPro: false)
        
        // Then: Pro formats should NOT be available
        XCTAssertFalse(flags.supportsFLAC, "FLAC should NOT be available in Free")
        XCTAssertFalse(flags.supportsDSD, "DSD should NOT be available in Free")
    }
    
    func testFreeConfiguration_DoesNotHaveProFeatures() {
        // Given: Free tier
        let flags = CoreFeatureFlags(isPro: false)
        
        // Then: Pro features should NOT be available
        XCTAssertFalse(flags.supportsGaplessPlayback, "Gapless playback should NOT be available in Free")
        XCTAssertFalse(flags.supportsMetadataEditing, "Metadata editing should NOT be available in Free")
        XCTAssertFalse(flags.supportsBitPerfectOutput, "Bit-perfect output should NOT be available in Free")
    }
    
    // MARK: - Pro Tier Tests
    
    func testProConfiguration_HasAllFormats() {
        // Given: Pro tier
        let flags = CoreFeatureFlags(isPro: true)
        
        // Then: All formats should be available
        XCTAssertTrue(flags.supportsMP3, "MP3 should be available in Pro")
        XCTAssertTrue(flags.supportsAAC, "AAC should be available in Pro")
        XCTAssertTrue(flags.supportsALAC, "ALAC should be available in Pro")
        XCTAssertTrue(flags.supportsWAV, "WAV should be available in Pro")
        XCTAssertTrue(flags.supportsAIFF, "AIFF should be available in Pro")
        XCTAssertTrue(flags.supportsFLAC, "FLAC should be available in Pro")
        XCTAssertTrue(flags.supportsDSD, "DSD should be available in Pro")
    }
    
    func testProConfiguration_HasProFeatures() {
        // Given: Pro tier
        let flags = CoreFeatureFlags(isPro: true)
        
        // Then: Pro features should be available
        XCTAssertTrue(flags.supportsGaplessPlayback, "Gapless playback should be available in Pro")
        XCTAssertTrue(flags.supportsMetadataEditing, "Metadata editing should be available in Pro")
        XCTAssertTrue(flags.supportsBitPerfectOutput, "Bit-perfect output should be available in Pro")
    }
    
    // MARK: - IAPManager Integration Tests
    
    func testInitializationFromFreeIAPManager() {
        // Given: Free IAPManager
        let freeManager = MockIAPManager(isProUnlocked: false)
        
        // When: Creating flags from IAPManager
        let flags = CoreFeatureFlags(iapManager: freeManager)
        
        // Then: Should match Free configuration
        XCTAssertTrue(flags.supportsMP3, "Should have basic format")
        XCTAssertFalse(flags.supportsFLAC, "Should NOT have Pro format")
        XCTAssertFalse(flags.supportsGaplessPlayback, "Should NOT have Pro feature")
    }
    
    func testInitializationFromProIAPManager() {
        // Given: Pro IAPManager
        let proManager = MockIAPManager(isProUnlocked: true)
        
        // When: Creating flags from IAPManager
        let flags = CoreFeatureFlags(iapManager: proManager)
        
        // Then: Should match Pro configuration
        XCTAssertTrue(flags.supportsMP3, "Should have basic format")
        XCTAssertTrue(flags.supportsFLAC, "Should have Pro format")
        XCTAssertTrue(flags.supportsGaplessPlayback, "Should have Pro feature")
    }
    
    // MARK: - Consistency Tests
    
    func testFreeAndProConsistency() {
        // Given: Both Free and Pro configurations
        let freeFlags = CoreFeatureFlags(isPro: false)
        let proFlags = CoreFeatureFlags(isPro: true)
        
        // Then: Pro should be a superset of Free
        // (All Free features should also be in Pro)
        XCTAssertTrue(proFlags.supportsMP3, "Pro should support all Free formats")
        XCTAssertTrue(proFlags.supportsAAC, "Pro should support all Free formats")
        XCTAssertTrue(proFlags.supportsALAC, "Pro should support all Free formats")
        XCTAssertTrue(proFlags.supportsWAV, "Pro should support all Free formats")
        XCTAssertTrue(proFlags.supportsAIFF, "Pro should support all Free formats")
        
        // Pro should have additional features
        XCTAssertNotEqual(freeFlags.supportsFLAC, proFlags.supportsFLAC, "FLAC availability should differ")
        XCTAssertNotEqual(freeFlags.supportsDSD, proFlags.supportsDSD, "DSD availability should differ")
    }
}
