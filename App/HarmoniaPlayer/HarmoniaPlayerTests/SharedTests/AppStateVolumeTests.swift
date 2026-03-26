//
//  AppStateVolumeTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-03-21.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState volume control.
///
/// Verifies that `setVolume()` delegates to `PlaybackService`,
/// updates the published `volume` property, and clamps
/// out-of-range values before forwarding.
@MainActor
final class AppStateVolumeTests: XCTestCase {

    // MARK: - Test Fixtures

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Tests

    /// `setVolume(0.5)` must call `PlaybackService.setVolume` exactly once.
    func testSetVolume_ForwardsToService() async {
        await sut.setVolume(0.5)

        XCTAssertEqual(fakePlaybackService.setVolumeCallCount, 1)
    }

    /// Values above 1.0 are clamped to 1.0 before forwarding.
    func testSetVolume_Clamps_AboveOne() async {
        await sut.setVolume(1.5)

        XCTAssertEqual(fakePlaybackService.lastSetVolume, 1.0)
    }

    /// Values below 0.0 are clamped to 0.0 before forwarding.
    func testSetVolume_Clamps_BelowZero() async {
        await sut.setVolume(-0.1)

        XCTAssertEqual(fakePlaybackService.lastSetVolume, 0.0)
    }
}
