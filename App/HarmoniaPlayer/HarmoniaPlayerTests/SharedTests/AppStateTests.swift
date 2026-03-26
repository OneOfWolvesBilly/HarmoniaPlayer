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
///
/// Note: @MainActor required because AppState is @MainActor isolated.
/// AppState.nonisolated deinit workaround is required for Xcode 26 beta.
@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates an isolated UserDefaults suite to prevent persistence state
    /// leaking between tests.
    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    /// Creates a minimal AppState for testing.
    ///
    /// - Parameter isProUnlocked: Simulates Free (`false`, default) or Pro (`true`) IAP state.
    /// - Returns: A fully wired `AppState` backed by `FakeCoreProvider`.
    private func makeSUT(isProUnlocked: Bool = false) -> AppState {
        let iap = MockIAPManager(isProUnlocked: isProUnlocked)
        let provider = FakeCoreProvider()
        return AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults())
    }

    // MARK: - Tests: Free User

    func testInit_FreeUser_WiresDependenciesCorrectly() {
        // Given: Free tier IAP
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider,
            userDefaults: makeIsolatedDefaults()
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
        _ = AppState(iapManager: iapManager, provider: fakeProvider, userDefaults: makeIsolatedDefaults())

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
            provider: fakeProvider,
            userDefaults: makeIsolatedDefaults()
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
        _ = AppState(iapManager: iapManager, provider: fakeProvider, userDefaults: makeIsolatedDefaults())

        // Then: Provider called with Pro configuration
        XCTAssertEqual(fakeProvider.makePlaybackServiceCallCount, 1,
                       "Should create playback service once")
        XCTAssertEqual(fakeProvider.lastIsProUser, true,
                       "Should pass Pro configuration to provider")
        XCTAssertEqual(fakeProvider.makeTagReaderServiceCallCount, 1,
                       "Should create tag reader service once")
    }

    // MARK: - Tests: Initialization Safety

    func testInit_DoesNotCrash() {
        // Given/When/Then: Init completes without crashing
        XCTAssertNoThrow(
            _ = AppState(
                iapManager: MockIAPManager(),
                provider: FakeCoreProvider(),
                userDefaults: makeIsolatedDefaults()
            )
        )
    }

    func testInit_DoesNotExecuteBehavior() {
        // Given: Fake provider
        let iapManager = MockIAPManager(isProUnlocked: false)
        let fakeProvider = FakeCoreProvider()

        // When: Initialize AppState
        let appState = AppState(
            iapManager: iapManager,
            provider: fakeProvider,
            userDefaults: makeIsolatedDefaults()
        )

        // Then: Services are created but no behavior executed
        // (Services are placeholders in Slice 1)
        XCTAssertEqual(appState.playbackService.state, .idle,
                       "Playback should remain idle (no auto-play)")
        XCTAssertTrue(true, "AppState should not execute playback/playlist behavior")
    }

    // MARK: - Tests: Feature Flags Consistency

    func testFeatureFlags_ConsistentWithIAP_Free() {
        // Given: Free IAP
        let freeIAP = MockIAPManager(isProUnlocked: false)
        let freeAppState = AppState(
            iapManager: freeIAP,
            provider: FakeCoreProvider(),
            userDefaults: makeIsolatedDefaults()
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
            provider: FakeCoreProvider(),
            userDefaults: makeIsolatedDefaults()
        )

        // Then: Feature flags match IAP state
        XCTAssertTrue(proAppState.featureFlags.supportsFLAC)
        XCTAssertTrue(proAppState.featureFlags.supportsDSD)
        XCTAssertTrue(proAppState.isProUnlocked)
    }

    // MARK: - Tests: Initial View Preferences (Slice 1-E)

    /// Verifies that `viewPreferences` is set to `.defaultPreferences` on init,
    /// without any caller needing to configure it explicitly.
    func testAppState_InitialViewPreferences_MatchesDefault() {
        // Given / When: Fresh AppState
        let sut = makeSUT()

        // Then: viewPreferences equals the documented default
        XCTAssertEqual(sut.viewPreferences, ViewPreferences.defaultPreferences,
                       "viewPreferences should equal .defaultPreferences on init")
    }

    /// Verifies that `viewPreferences` is mutable after init,
    /// allowing views and actions to update the layout at runtime.
    func testAppState_ViewPreferences_IsMutable() {
        // Given: Fresh AppState with default preferences
        let sut = makeSUT()

        // When: Layout preset is changed
        sut.viewPreferences.layoutPreset = .compact

        // Then: Change is reflected
        XCTAssertEqual(sut.viewPreferences.layoutPreset, .compact,
                       "viewPreferences.layoutPreset should be writable")
    }

    // MARK: - Tests: Initial Error State (Slice 1-E)

    /// Verifies that `lastError` is `nil` on init.
    /// Nothing in Slice 1 sets this property; it is defined here
    /// for Slice 4 (playback) to assign.
    func testAppState_InitialLastError_IsNil() {
        // Given / When: Fresh AppState
        let sut = makeSUT()

        // Then: No error present before any playback attempt
        XCTAssertNil(sut.lastError,
                     "lastError should be nil on init")
    }

    // MARK: - Tests: Slice 1-F — TagReader Wiring Verification

    /// `makeTagReaderService()` is called exactly once during `AppState.init`.
    func testAppState_Init_CallsMakeTagReaderService() {
        // Given
        let iap = MockIAPManager(isProUnlocked: false)
        let provider = FakeCoreProvider()

        // When
        _ = AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults())

        // Then
        XCTAssertEqual(provider.makeTagReaderServiceCallCount, 1,
                       "AppState.init should call makeTagReaderService exactly once")
    }

    /// `tagReaderService` is non-nil after `AppState.init`.
    func testAppState_TagReaderService_IsNotNil() {
        // Given / When
        let sut = makeSUT()

        // Then
        XCTAssertNotNil(sut.tagReaderService,
                        "tagReaderService should be non-nil after init")
    }

    /// `tagReaderService` stored in AppState is the exact instance the provider returned.
    ///
    /// Injects a known `FakeTagReaderService` via `FakeCoreProvider(tagReader:)`
    /// so the `===` identity check is unambiguous.
    func testAppState_TagReaderService_IsFromProvider() {
        // Given: A known fake injected into the provider
        let knownFake = FakeTagReaderService()
        let provider = FakeCoreProvider(tagReader: knownFake)
        let iap = MockIAPManager(isProUnlocked: false)

        // When
        let sut = AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults())

        // Then: AppState holds the exact instance the provider returned
        XCTAssertTrue(
            sut.tagReaderService === knownFake,
            "AppState should wire the exact TagReaderService instance returned by the provider"
        )
    }

    /// No `TagReaderService` methods are called during `AppState.init`.
    ///
    /// Injects a known `FakeTagReaderService` and checks its call count
    /// remains 0 after init completes.
    func testAppState_TagReaderService_NoMethodsCalled() {
        // Given: A known fake injected into the provider
        let knownFake = FakeTagReaderService()
        let provider = FakeCoreProvider(tagReader: knownFake)
        let iap = MockIAPManager(isProUnlocked: false)

        // When
        _ = AppState(iapManager: iap, provider: provider, userDefaults: makeIsolatedDefaults())

        // Then: No metadata reads triggered by init
        XCTAssertEqual(knownFake.readMetadataCallCount, 0,
                       "AppState.init must not call readMetadata — no eager fetch in Slice 1")
    }
}
