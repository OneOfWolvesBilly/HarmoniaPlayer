//
//  IAPManagerTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-11.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for IAPManager protocol and MockIAPManager implementation
///
/// Scope: Verify IAP abstraction works correctly for Free/Pro gating
/// Dependencies: None (no HarmoniaCore)
final class IAPManagerTests: XCTestCase {
    
    // MARK: - MockIAPManager Tests
    
    /// Test that MockIAPManager defaults to Free (isProUnlocked = false)
    func testMockIAPManager_DefaultIsFree() {
        // Arrange & Act
        let iapManager = MockIAPManager()
        
        // Assert
        XCTAssertFalse(
            iapManager.isProUnlocked,
            "MockIAPManager should default to Free (isProUnlocked = false)"
        )
    }
    
    /// Test that MockIAPManager can be initialized as Pro
    func testMockIAPManager_CanBeInitializedAsPro() {
        // Arrange & Act
        let iapManager = MockIAPManager(isProUnlocked: true)
        
        // Assert
        XCTAssertTrue(
            iapManager.isProUnlocked,
            "MockIAPManager(isProUnlocked: true) should return Pro status"
        )
    }
    
    /// Test that MockIAPManager can be initialized as Free explicitly
    func testMockIAPManager_CanBeInitializedAsFree() {
        // Arrange & Act
        let iapManager = MockIAPManager(isProUnlocked: false)
        
        // Assert
        XCTAssertFalse(
            iapManager.isProUnlocked,
            "MockIAPManager(isProUnlocked: false) should return Free status"
        )
    }
    
    /// Test that MockIAPManager state is immutable after initialization
    func testMockIAPManager_StateIsImmutableAfterInit() {
        // Arrange
        let freeMock = MockIAPManager(isProUnlocked: false)
        let proMock = MockIAPManager(isProUnlocked: true)
        
        // Act
        let freeStatus1 = freeMock.isProUnlocked
        let freeStatus2 = freeMock.isProUnlocked
        let proStatus1 = proMock.isProUnlocked
        let proStatus2 = proMock.isProUnlocked
        
        // Assert
        XCTAssertEqual(freeStatus1, freeStatus2, "Free status should remain consistent")
        XCTAssertEqual(proStatus1, proStatus2, "Pro status should remain consistent")
        XCTAssertFalse(freeStatus1, "Free mock should stay Free")
        XCTAssertTrue(proStatus1, "Pro mock should stay Pro")
    }
    
    // MARK: - IAPManager Protocol Conformance
    
    /// Test that MockIAPManager conforms to IAPManager protocol
    func testMockIAPManager_ConformsToProtocol() {
        // Arrange & Act
        let iapManager: IAPManager = MockIAPManager()
        
        // Assert
        // This test compiles if MockIAPManager conforms to IAPManager
        XCTAssertNotNil(iapManager, "MockIAPManager should conform to IAPManager protocol")
    }
    
    /// Test that IAPManager protocol can be used polymorphically
    func testIAPManager_PolymorphicUsage() {
        // Arrange
        let freeManager: IAPManager = MockIAPManager(isProUnlocked: false)
        let proManager: IAPManager = MockIAPManager(isProUnlocked: true)
        
        // Act & Assert
        XCTAssertFalse(freeManager.isProUnlocked, "Free manager via protocol should return false")
        XCTAssertTrue(proManager.isProUnlocked, "Pro manager via protocol should return true")
    }
}
