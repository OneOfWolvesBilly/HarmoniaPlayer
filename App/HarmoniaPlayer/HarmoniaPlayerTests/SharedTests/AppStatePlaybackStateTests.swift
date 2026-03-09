//
//  AppStatePlaybackStateTests.swift
//  HarmoniaPlayerTests
//
//  Slice 4-A: Verify AppState initial playback state.
//

import XCTest
@testable import HarmoniaPlayer

/// Tests for AppState initial playback state (Slice 4-A).
///
/// Verifies that `playbackState`, `currentTime`, and `duration` are correctly
/// initialised on a fresh `AppState`, and that `FakeCoreProvider.playbackServiceStub`
/// injection works as expected.
///
/// **Swift 6 / Xcode 26 note:**
/// `@MainActor` is required because `AppState` is `@MainActor`-isolated.
@MainActor
final class AppStatePlaybackStateTests: XCTestCase {

    // MARK: - Test Fixtures

    private var sut: AppState!
    private var fakeProvider: FakeCoreProvider!

    override func setUp() {
        super.setUp()
        fakeProvider = FakeCoreProvider()
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(iapManager: iap, provider: fakeProvider)
    }

    override func tearDown() {
        sut = nil
        fakeProvider = nil
        super.tearDown()
    }

    // MARK: - Slice 4-A: Initial State

    /// testAppState_InitialPlaybackState_IsIdle
    ///
    /// Given: Fresh AppState
    /// When:  `playbackState` is read
    /// Then:  `.idle`
    func testAppState_InitialPlaybackState_IsIdle() {
        XCTAssertEqual(sut.playbackState, .idle)
    }

    /// testAppState_InitialCurrentTime_IsZero
    ///
    /// Given: Fresh AppState
    /// When:  `currentTime` is read
    /// Then:  `0`
    func testAppState_InitialCurrentTime_IsZero() {
        XCTAssertEqual(sut.currentTime, 0)
    }

    /// testAppState_InitialDuration_IsZero
    ///
    /// Given: Fresh AppState
    /// When:  `duration` is read
    /// Then:  `0`
    func testAppState_InitialDuration_IsZero() {
        XCTAssertEqual(sut.duration, 0)
    }

    // MARK: - Slice 4-A: playbackServiceStub Injection

    /// testFakeCoreProvider_ReturnsInjectedPlaybackServiceStub
    ///
    /// Given: `FakeCoreProvider` created with a known `FakePlaybackService` instance
    /// When:  `AppState` is initialised using that provider
    /// Then:  `AppState.playbackService` is the same instance as the stub
    func testFakeCoreProvider_ReturnsInjectedPlaybackServiceStub() {
        // Given
        let knownFake = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: knownFake)
        let iap = MockIAPManager(isProUnlocked: false)

        // When
        let appState = AppState(iapManager: iap, provider: provider)

        // Then
        XCTAssertTrue(appState.playbackService === knownFake,
                      "AppState should hold the injected FakePlaybackService stub")
    }

    /// testFakeCoreProvider_DefaultStub_IsAccessible
    ///
    /// Given: `FakeCoreProvider` created with default stub
    /// When:  `playbackServiceStub` is accessed
    /// Then:  It is the same instance returned by `makePlaybackService`
    func testFakeCoreProvider_DefaultStub_IsAccessible() {
        // The stub created during FakeCoreProvider init should be
        // the same one that was injected into AppState via makePlaybackService.
        XCTAssertTrue(sut.playbackService === fakeProvider.playbackServiceStub,
                      "AppState.playbackService should be fakeProvider.playbackServiceStub")
    }
}
