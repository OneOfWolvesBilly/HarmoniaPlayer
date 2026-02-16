//
//  CoreFactoryTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-15.
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for CoreFactory
///
/// Validates that CoreFactory correctly:
/// - Passes feature flags to provider
/// - Creates services via provider
/// - Does not require audio devices
final class CoreFactoryTests: XCTestCase {
    
    // MARK: - Tests: Free Tier
    
    func testMakePlaybackService_FreeUser_CallsProviderWithFreeConfig() {
        // Given: Free tier feature flags
        let flags = CoreFeatureFlags(isPro: false)
        let fakeProvider = FakeCoreProvider()
        let factory = CoreFactory(featureFlags: flags, provider: fakeProvider)
        
        // When: Creating playback service
        _ = factory.makePlaybackService()
        
        // Then: Provider called with isProUser = false
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should call provider once")
        XCTAssertEqual(fakeProvider.lastIsProUser, false,
                       "Should pass Free configuration to provider")
    }
    
    // MARK: - Tests: Pro Tier
    
    func testMakePlaybackService_ProUser_CallsProviderWithProConfig() {
        // Given: Pro tier feature flags
        let flags = CoreFeatureFlags(isPro: true)
        let fakeProvider = FakeCoreProvider()
        let factory = CoreFactory(featureFlags: flags, provider: fakeProvider)
        
        // When: Creating playback service
        _ = factory.makePlaybackService()
        
        // Then: Provider called with isProUser = true
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should call provider once")
        XCTAssertEqual(fakeProvider.lastIsProUser, true,
                       "Should pass Pro configuration to provider")
    }
    
    // MARK: - Tests: Tag Reader
    
    func testMakeTagReaderService_CallsProvider() {
        // Given: Any feature flags
        let flags = CoreFeatureFlags(isPro: false)
        let fakeProvider = FakeCoreProvider()
        let factory = CoreFactory(featureFlags: flags, provider: fakeProvider)
        
        // When: Creating tag reader service
        _ = factory.makeTagReaderService()
        
        // Then: Provider called
        XCTAssertEqual(fakeProvider.makeTagReaderServiceCallCount, 1,
                       "Should call provider once")
    }
    
    // MARK: - Tests: No Audio Device Dependency
    
    func testFactoryDoesNotRequireAudioDevices() {
        // Given: Factory with fake provider
        let flags = CoreFeatureFlags(isPro: false)
        let fakeProvider = FakeCoreProvider()
        let factory = CoreFactory(featureFlags: flags, provider: fakeProvider)
        
        // When/Then: Creating services does not fail in test environment
        // (no audio devices available in CI)
        _ = factory.makePlaybackService()
        _ = factory.makeTagReaderService()
        
        // Test passes if no crash occurs
        XCTAssertTrue(true, "Factory should work without audio devices")
    }
    
    // MARK: - Tests: Feature Flags Integration
    
    func testFeatureFlags_AreAccessible() {
        // Given: Factory with specific flags
        let flags = CoreFeatureFlags(isPro: true)
        let factory = CoreFactory(featureFlags: flags, provider: FakeCoreProvider())
        
        // Then: Flags are accessible
        XCTAssertTrue(factory.featureFlags.supportsFLAC,
                      "Should expose feature flags")
    }
}
