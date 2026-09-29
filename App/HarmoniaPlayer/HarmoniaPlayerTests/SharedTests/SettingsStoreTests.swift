//
//  SettingsStoreTests.swift
//  HarmoniaPlayerTests
//

import XCTest
@testable import Harmonia_Player

/// Tests for `SettingsStore` — the store owning the user settings, the
/// Free/Pro tier state, and the UI string bundle.
///
/// Every test builds the store directly on an isolated `UserDefaults`
/// suite. A relaunch is simulated by constructing a second store on the
/// same suite. `MockIAPManager` dictates the tier and the purchase /
/// refresh outcomes.
///
/// `@MainActor` is required because `SettingsStore` is `@MainActor` isolated.
@MainActor
final class SettingsStoreTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: SettingsStore!
    private var mockIAP: MockIAPManager!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-settings-store-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        mockIAP = MockIAPManager(isProUnlocked: false)
        sut = SettingsStore(iapManager: mockIAP, userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        sut = nil
        mockIAP = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a second store on the same suite, simulating a relaunch.
    private func makeRelaunchedStore(
        iapManager: IAPManager = MockIAPManager()
    ) -> SettingsStore {
        SettingsStore(iapManager: iapManager, userDefaults: testDefaults)
    }

    // MARK: - Defaults

    func testAllowDuplicateTracks_DefaultIsFalse() {
        XCTAssertFalse(sut.allowDuplicateTracks)
    }

    func testViewPreferences_DefaultMatchesDefaultPreferences() {
        XCTAssertEqual(sut.viewPreferences, ViewPreferences.defaultPreferences,
                       "viewPreferences should equal .defaultPreferences on init")
    }

    func testReplayGainMode_DefaultIsOff() {
        XCTAssertEqual(sut.replayGainMode, .off)
    }

    // MARK: - Persistence

    func testAllowDuplicateTracks_SurvivesRelaunch() {
        sut.allowDuplicateTracks = true

        let relaunched = makeRelaunchedStore()

        XCTAssertTrue(relaunched.allowDuplicateTracks,
                      "allowDuplicateTracks must persist at change time, with no save call")
    }

    func testReplayGainMode_PersistsOnChange() {
        sut.replayGainMode = .album

        XCTAssertEqual(testDefaults.string(forKey: "hp.replayGainMode"), "album",
                       "replayGainMode must write its key at change time, with no save call")
    }

    func testReplayGainMode_SurvivesRelaunch() {
        sut.replayGainMode = .album

        let relaunched = makeRelaunchedStore()

        XCTAssertEqual(relaunched.replayGainMode, .album)
    }

    func testSelectedLanguage_PersistsOnChange() {
        sut.selectedLanguage = "ja"

        XCTAssertEqual(testDefaults.string(forKey: "hp.selectedLanguage"), "ja",
                       "selectedLanguage must write its key at change time, with no save call")
    }

    func testInit_RestoresPersistedSettings() {
        testDefaults.set(true, forKey: "hp.allowDuplicateTracks")
        testDefaults.set("zh-Hant", forKey: "hp.selectedLanguage")
        testDefaults.set("track", forKey: "hp.replayGainMode")

        let restored = makeRelaunchedStore()

        XCTAssertTrue(restored.allowDuplicateTracks)
        XCTAssertEqual(restored.selectedLanguage, "zh-Hant")
        XCTAssertEqual(restored.replayGainMode, .track)
    }

    func testInit_InvalidReplayGainRaw_KeepsOff() {
        testDefaults.set("bogus", forKey: "hp.replayGainMode")

        let restored = makeRelaunchedStore()

        XCTAssertEqual(restored.replayGainMode, .off,
                       "An unrecognised persisted raw value must leave the default in place")
    }

    // MARK: - ReplayGain Notification

    func testReplayGainModeChange_NotifiesClosure() {
        var received: [ReplayGainMode] = []
        sut.onReplayGainModeChanged = { received.append($0) }

        sut.replayGainMode = .track

        XCTAssertEqual(received, [.track],
                       "onReplayGainModeChanged must be called once with the new mode")
    }

    // MARK: - Tier State

    func testInit_FreeIAP_TierIsFree() {
        XCTAssertFalse(sut.isProUnlocked)
        XCTAssertFalse(sut.featureFlags.supportsFLAC)
        XCTAssertFalse(sut.featureFlags.supportsDSD)
    }

    func testInit_ProIAP_TierIsPro() {
        let proStore = makeRelaunchedStore(iapManager: MockIAPManager(isProUnlocked: true))

        XCTAssertTrue(proStore.isProUnlocked)
        XCTAssertTrue(proStore.featureFlags.supportsFLAC)
        XCTAssertTrue(proStore.featureFlags.supportsDSD)
    }

    func testPurchasePro_Success_UnlocksProAndUpdatesFlags() async throws {
        mockIAP.purchaseResult = .success

        try await sut.purchasePro()

        XCTAssertEqual(mockIAP.purchaseProCallCount, 1)
        XCTAssertTrue(sut.isProUnlocked)
        XCTAssertTrue(sut.featureFlags.supportsFLAC,
                      "featureFlags must reflect Pro tier after successful purchase")
    }

    func testPurchasePro_Failure_ThrowsAndStaysFree() async {
        do {
            try await sut.purchasePro()
            XCTFail("purchasePro() must rethrow the IAP manager's error")
        } catch {
            // Expected: MockIAPManager defaults to .failure(.notAvailable).
        }

        XCTAssertFalse(sut.isProUnlocked)
        XCTAssertFalse(sut.featureFlags.supportsFLAC)
    }

    func testRefreshEntitlements_RereadsIAPState() async {
        mockIAP.entitlementAfterRefresh = true

        await sut.refreshEntitlements()

        XCTAssertEqual(mockIAP.refreshEntitlementsCallCount, 1)
        XCTAssertTrue(sut.isProUnlocked)
        XCTAssertTrue(sut.featureFlags.supportsFLAC)
    }

    // MARK: - Language Bundle

    func testLanguageBundle_PersistedLanguage_ResolvesLproj() {
        testDefaults.set("ja", forKey: "hp.selectedLanguage")

        let store = makeRelaunchedStore()

        XCTAssertEqual(store.languageBundle.bundleURL.lastPathComponent, "ja.lproj")
    }

    func testLanguageBundle_NoPersistedLanguage_ResolvesEnglish() {
        XCTAssertEqual(sut.languageBundle.bundleURL.lastPathComponent, "en.lproj",
                       "A never-written language key resolves the English bundle")
    }

    func testLanguageBundle_System_UsesMainBundle() {
        testDefaults.set("system", forKey: "hp.selectedLanguage")

        let store = makeRelaunchedStore()

        XCTAssertEqual(store.languageBundle, Bundle.main)
    }

    // MARK: - Paywall

    func testShowPaywallIfNeeded_Free_RequestsAndReturnsTrue() {
        var requestCount = 0
        sut.onPaywallRequested = { requestCount += 1 }

        let result = sut.showPaywallIfNeeded()

        XCTAssertTrue(result, "showPaywallIfNeeded() must return true for a Free user")
        XCTAssertEqual(requestCount, 1, "The Free tier must request the paywall once")
    }

    func testShowPaywallIfNeeded_Pro_NoRequestReturnsFalse() {
        let proStore = makeRelaunchedStore(iapManager: MockIAPManager(isProUnlocked: true))
        var requestCount = 0
        proStore.onPaywallRequested = { requestCount += 1 }

        let result = proStore.showPaywallIfNeeded()

        XCTAssertFalse(result, "showPaywallIfNeeded() must return false for a Pro user")
        XCTAssertEqual(requestCount, 0, "The Pro tier must not request the paywall")
    }
}
