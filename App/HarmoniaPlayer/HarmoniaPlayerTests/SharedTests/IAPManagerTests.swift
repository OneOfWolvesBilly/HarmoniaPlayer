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
@MainActor
final class IAPManagerTests: XCTestCase {

    // MARK: - Helpers

    /// Returns the URL for a test bundle audio resource, or skips the test if absent.
    ///
    /// - Parameters:
    ///   - name: Resource file name without extension (e.g. `"test_format"`).
    ///   - ext:  File extension (e.g. `"flac"`, `"mp3"`).
    func bundleURL(forResource name: String, withExtension ext: String) throws -> URL {
        guard let url = Bundle(for: type(of: self))
            .url(forResource: name, withExtension: ext) else {
            throw XCTSkip("Bundle resource '\(name).\(ext)' not found")
        }
        return url
    }

    // MARK: - MockIAPManager Tests

    /// Test that MockIAPManager defaults to Free (isProUnlocked = false)
    func testMockIAPManager_DefaultIsFree() {
        let iapManager = MockIAPManager()
        XCTAssertFalse(
            iapManager.isProUnlocked,
            "MockIAPManager should default to Free (isProUnlocked = false)"
        )
    }

    /// Test that MockIAPManager can be initialized as Pro
    func testMockIAPManager_CanBeInitializedAsPro() {
        let iapManager = MockIAPManager(isProUnlocked: true)
        XCTAssertTrue(
            iapManager.isProUnlocked,
            "MockIAPManager(isProUnlocked: true) should return Pro status"
        )
    }

    /// Test that MockIAPManager can be initialized as Free explicitly
    func testMockIAPManager_CanBeInitializedAsFree() {
        let iapManager = MockIAPManager(isProUnlocked: false)
        XCTAssertFalse(
            iapManager.isProUnlocked,
            "MockIAPManager(isProUnlocked: false) should return Free status"
        )
    }

    /// Test that consecutive reads return the same value before any purchase
    func testMockIAPManager_StatusIsConsistentBeforePurchase() {
        let freeMock = MockIAPManager(isProUnlocked: false)
        let proMock  = MockIAPManager(isProUnlocked: true)

        XCTAssertEqual(freeMock.isProUnlocked, freeMock.isProUnlocked,
                       "Free status should remain consistent")
        XCTAssertEqual(proMock.isProUnlocked, proMock.isProUnlocked,
                       "Pro status should remain consistent")
        XCTAssertFalse(freeMock.isProUnlocked, "Free mock should stay Free")
        XCTAssertTrue(proMock.isProUnlocked,   "Pro mock should stay Pro")
    }

    // MARK: - IAPManager Protocol Conformance

    /// Test that MockIAPManager conforms to IAPManager protocol
    func testMockIAPManager_ConformsToProtocol() {
        let iapManager: IAPManager = MockIAPManager()
        XCTAssertNotNil(iapManager, "MockIAPManager should conform to IAPManager protocol")
    }

    /// Test that IAPManager protocol can be used polymorphically
    func testIAPManager_PolymorphicUsage() {
        let freeManager: IAPManager = MockIAPManager(isProUnlocked: false)
        let proManager:  IAPManager = MockIAPManager(isProUnlocked: true)

        XCTAssertFalse(freeManager.isProUnlocked, "Free manager via protocol should return false")
        XCTAssertTrue(proManager.isProUnlocked,   "Pro manager via protocol should return true")
    }

    // MARK: - Slice 9-A: showPaywallIfNeeded tests

    /// testIsProUnlocked_DefaultIsFalse
    func testIsProUnlocked_DefaultIsFalse() {
        let mock = MockIAPManager()
        XCTAssertFalse(mock.isProUnlocked)
    }

    /// testShowPaywallIfNeeded_ReturnsTrueForFreeUser
    func testShowPaywallIfNeeded_ReturnsTrueForFreeUser() {
        let appState = AppState(
            iapManager: MockIAPManager(isProUnlocked: false),
            provider: FakeCoreProvider()
        )
        let result = appState.showPaywallIfNeeded()
        XCTAssertTrue(result,              "should return true for Free user")
        XCTAssertTrue(appState.showPaywall,"showPaywall should be true")
    }

    /// testShowPaywallIfNeeded_ReturnsFalseForProUser
    func testShowPaywallIfNeeded_ReturnsFalseForProUser() {
        let appState = AppState(
            iapManager: MockIAPManager(isProUnlocked: true),
            provider: FakeCoreProvider()
        )
        let result = appState.showPaywallIfNeeded()
        XCTAssertFalse(result,              "should return false for Pro user")
        XCTAssertFalse(appState.showPaywall,"showPaywall should remain false")
    }

    /// testShowPaywall_WhenFreeUserPlaysFlac
    func testShowPaywall_WhenFreeUserPlaysFlac() async throws {
        let suite = UserDefaults(suiteName: "hp-test-\(UUID().uuidString)")!
        let appState = AppState(
            iapManager: MockIAPManager(isProUnlocked: false),
            provider: FakeCoreProvider(),
            userDefaults: suite
        )
        let flacURL = try bundleURL(forResource: "test_format", withExtension: "flac")
        await appState.load(urls: [flacURL])
        guard let trackID = appState.playlist.tracks.first(where: { $0.url == flacURL })?.id else {
            XCTFail("FLAC track not loaded"); return
        }
        await appState.play(trackID: trackID)
        XCTAssertTrue(appState.showPaywall, "showPaywall should be true when Free user plays FLAC")
    }

    /// testShowPaywall_NotSet_WhenProUserPlaysFlac
    func testShowPaywall_NotSet_WhenProUserPlaysFlac() async throws {
        let suite = UserDefaults(suiteName: "hp-test-\(UUID().uuidString)")!
        let appState = AppState(
            iapManager: MockIAPManager(isProUnlocked: true),
            provider: FakeCoreProvider(),
            userDefaults: suite
        )
        let flacURL = try bundleURL(forResource: "test_format", withExtension: "flac")
        await appState.load(urls: [flacURL])
        guard let trackID = appState.playlist.tracks.first(where: { $0.url == flacURL })?.id else {
            XCTFail("FLAC track not loaded"); return
        }
        await appState.play(trackID: trackID)
        XCTAssertFalse(appState.showPaywall, "showPaywall should remain false for Pro user")
    }
}
