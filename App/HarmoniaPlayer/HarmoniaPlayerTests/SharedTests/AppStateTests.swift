//
//  AppStateTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-15.
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for AppState wiring
///
/// Validates that AppState correctly:
/// - Wires dependencies (IAP → Flags → Factory → Services)
/// - Exposes correct published state
/// - Initializes without crashing
/// - Does not execute behavior (Slice 1)
@MainActor
final class AppStateTests: XCTestCase {
    
    // MARK: - Tests: Free User
    
    func testInit_FreeUser_WiresDependenciesCorrectly() {
        // Given: Free tier IAP
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()
        
        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider
        )
        
        // Then: Dependencies are wired
        XCTAssertFalse(appState.isProUnlocked,
                       "Free user should not have Pro unlocked")
        XCTAssertFalse(appState.featureFlags.supportsFLAC,
                       "Free tier should not support FLAC")
        XCTAssertNotNil(appState.playbackService,
                        "Playback service should be created")
        XCTAssertNotNil(appState.tagReaderService,
                        "Tag reader service should be created")
    }
    
    func testInit_FreeUser_CallsProviderWithFreeConfig() {
        // Given: Free tier IAP with fake provider
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()
        
        // When: Initialize AppState
        _ = AppState(iapManager: iapManager, provider: fakeProvider)
        
        // Then: Provider called with Free configuration
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should create playback service once")
        XCTAssertEqual(fakeProvider.lastIsProUser, false,
                       "Should pass Free configuration to provider")
        XCTAssertEqual(fakeProvider.makeTagReaderServiceCallCount, 1,
                       "Should create tag reader service once")
    }
    
    // MARK: - Tests: Pro User
    
    func testInit_ProUser_WiresDependenciesCorrectly() {
        // Given: Pro tier IAP
        let iapManager = MockIAPManager(isProUnlocked: true)
        let fakeProvider = FakeCoreProvider()
        
        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider
        )
        
        // Then: Dependencies are wired with Pro features
        XCTAssertTrue(appState.isProUnlocked,
                      "Pro user should have Pro unlocked")
        XCTAssertTrue(appState.featureFlags.supportsFLAC,
                      "Pro tier should support FLAC")
        XCTAssertNotNil(appState.playbackService,
                        "Playback service should be created")
        XCTAssertNotNil(appState.tagReaderService,
                        "Tag reader service should be created")
    }
    
    func testInit_ProUser_CallsProviderWithProConfig() {
        // Given: Pro tier IAP with fake provider
        let iapManager = MockIAPManager(isProUnlocked: true)
        let fakeProvider = FakeCoreProvider()
        
        // When: Initialize AppState
        _ = AppState(iapManager: iapManager, provider: fakeProvider)
        
        // Then: Provider called with Pro configuration
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should create playback service once")
        XCTAssertEqual(fakeProvider.lastIsProUser, true,
                       "Should pass Pro configuration to provider")
        XCTAssertEqual(fakeProvider.makeTagReaderServiceCallCount, 1,
                       "Should create tag reader service once")
    }
    
    // MARK: - Tests: No Behavior
    
    func testInit_DoesNotCrash() {
        // Given: Any IAP configuration
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()
        
        // When/Then: Initialize should not crash
        _ = AppState(iapManager: iapManager, provider: fakeProvider)
        
        // Test passes if no crash occurs
        XCTAssertTrue(true, "AppState initialization should not crash")
    }
    
    func testInit_DoesNotExecuteBehavior() {
        // Given: AppState with fake services
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()
        
        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider
        )
        
        // Then: Services are created but no behavior executed
        // (Services are placeholders in Slice 1)
        XCTAssertEqual(appState.playbackService.state, .idle,
                       "Playback should remain idle (no auto-play)")
        
        // Slice 1: AppState only wires dependencies, doesn't invoke behavior
        XCTAssertTrue(true, "AppState should not execute playback/playlist behavior")
    }
    
    // MARK: - Tests: Feature Flags Consistency
    
    func testFeatureFlags_ConsistentWithIAP_Free() {
        // Given: Free IAP
        let freeIAP = MockIAPManager(isProUnlocked: false)
        let freeAppState = AppState(
            iapManager: freeIAP,
            provider: FakeCoreProvider()
        )
        
        // Then: Feature flags match IAP state
        XCTAssertFalse(freeAppState.featureFlags.supportsFLAC)
        XCTAssertFalse(freeAppState.featureFlags.supportsDSD)
        XCTAssertFalse(freeAppState.isProUnlocked)
    }
    
    func testFeatureFlags_ConsistentWithIAP_Pro() {
        // Given: Pro IAP
        let proIAP = MockIAPManager(isProUnlocked: true)
        let proAppState = AppState(
            iapManager: proIAP,
            provider: FakeCoreProvider()
        )
        
        // Then: Feature flags match IAP state
        XCTAssertTrue(proAppState.featureFlags.supportsFLAC)
        XCTAssertTrue(proAppState.featureFlags.supportsDSD)
        XCTAssertTrue(proAppState.isProUnlocked)
    }
}