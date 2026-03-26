//
//  AppStatePlaybackStateTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-03-09.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState initial playback state (Slice 4-A).
///
/// Verifies that `playbackState`, `currentTime`, and `duration` are
/// initialised to their documented defaults on a fresh `AppState` instance.
///
/// **Swift 6 / Xcode 26 note:**
/// Test class is `@MainActor` — XCTest runs `@MainActor`-isolated classes on
/// the main actor automatically, so no `await MainActor.run {}` wrappers are
/// needed in individual test methods.
@MainActor
final class AppStatePlaybackStateTests: XCTestCase {

    // MARK: - Fixture

    private var sut: AppState!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        sut = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider(), userDefaults: testDefaults)
    }

    override func tearDown() {
        sut = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Slice 4-A: Initial State

    /// `testAppState_InitialPlaybackState_IsIdle`
    ///
    /// Given a freshly created AppState,
    /// when `playbackState` is read,
    /// then it is `.idle`.
    func testAppState_InitialPlaybackState_IsIdle() {
        XCTAssertEqual(sut.playbackState, .idle)
    }

    /// `testAppState_InitialCurrentTime_IsZero`
    ///
    /// Given a freshly created AppState,
    /// when `currentTime` is read,
    /// then it is `0`.
    func testAppState_InitialCurrentTime_IsZero() {
        XCTAssertEqual(sut.currentTime, 0)
    }

    /// `testAppState_InitialDuration_IsZero`
    ///
    /// Given a freshly created AppState,
    /// when `duration` is read,
    /// then it is `0`.
    func testAppState_InitialDuration_IsZero() {
        XCTAssertEqual(sut.duration, 0)
    }
}
