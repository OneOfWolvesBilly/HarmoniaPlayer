//
//  EQServiceTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Slice 9-K (commit 5): EQService protocol + HarmoniaEQAdapter +
//  CoreFactory wire.
//
//  TEST SCOPE
//  ----------
//  Three forward tests for HarmoniaEQAdapter — closure-binding adapter that
//  bridges Core's PlaybackService EQ control surface (setEQEnabled /
//  setEQPreamp / setEQBandGains) to the Application Layer EQService
//  protocol — plus one wire test for FakeCoreProvider.makeEQService.
//
//  HarmoniaEQAdapter does NOT import HarmoniaCore by design (closures are
//  bound by HarmoniaCoreProvider in the Integration Layer), so these tests
//  can verify forward behaviour without crossing the module boundary the
//  way IntegrationTests.swift forbids (line 28 there: "Does NOT import
//  HarmoniaCore — module boundary").
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - Test target builds with SWIFT_VERSION = 5.0; the main module builds
//    with 6.0 + SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor. Tests therefore
//    do not inherit MainActor inference and need no @MainActor annotation,
//    matching LyricsServiceTests / EQPersistenceStoreTests.
//  - No `nonisolated deinit {}` workaround needed: this test class is not
//    @MainActor, so the Xcode 26 beta TaskLocal teardown crash does not
//    apply.
//

import XCTest
@testable import HarmoniaPlayer

final class EQServiceTests: XCTestCase {

    // MARK: - HarmoniaEQAdapter — forward to setEnabled hook

    /// `HarmoniaEQAdapter.setEnabled(true)` must invoke the injected
    /// `setEnabled` closure with the same Bool argument. This is the
    /// Application Layer's only guarantee that EQ enable/disable reaches
    /// the underlying Core PlaybackService EQ control surface.
    func testEQService_SetEnabled_PassesThroughToPort() {
        var receivedValue: Bool?
        let adapter = HarmoniaEQAdapter(
            setEnabled:   { receivedValue = $0 },
            setPreamp:    { _ in },
            setBandGains: { _ in }
        )

        adapter.setEnabled(true)

        XCTAssertEqual(receivedValue, true,
                       "HarmoniaEQAdapter.setEnabled(true) must pass through to the injected setEnabled closure")
    }

    // MARK: - HarmoniaEQAdapter — forward to setPreamp hook

    /// `HarmoniaEQAdapter.setPreamp(-3)` must invoke the injected
    /// `setPreamp` closure with the same Float argument. Clamping is the
    /// adapter's responsibility downstream — this test only asserts
    /// faithful forwarding.
    func testEQService_SetPreamp_PassesThroughToPort() {
        var receivedValue: Float?
        let adapter = HarmoniaEQAdapter(
            setEnabled:   { _ in },
            setPreamp:    { receivedValue = $0 },
            setBandGains: { _ in }
        )

        adapter.setPreamp(-3)

        XCTAssertEqual(receivedValue, -3,
                       "HarmoniaEQAdapter.setPreamp(-3) must pass through to the injected setPreamp closure")
    }

    // MARK: - HarmoniaEQAdapter — forward to setBandGains hook

    /// `HarmoniaEQAdapter.setBandGains([...])` must invoke the injected
    /// `setBandGains` closure with the same `[Float]` array. Length and
    /// element order must be preserved.
    func testEQService_SetBandGains_PassesThroughToPort() {
        var receivedValue: [Float]?
        let adapter = HarmoniaEQAdapter(
            setEnabled:   { _ in },
            setPreamp:    { _ in },
            setBandGains: { receivedValue = $0 }
        )

        let gains: [Float] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        adapter.setBandGains(gains)

        XCTAssertEqual(receivedValue, gains,
                       "HarmoniaEQAdapter.setBandGains must pass through to the injected setBandGains closure with order and length preserved")
    }

    // MARK: - FakeCoreProvider — makeEQService wire

    /// `FakeCoreProvider(eqService:)` must return the injected stub from
    /// `makeEQService()` and record the call so EQCoordinator tests
    /// (commit 6) can verify identity without rebuilding the test
    /// scaffolding.
    func testFakeCoreProvider_MakeEQService_ReturnsInjectedStub() {
        let knownFake = FakeEQService()
        let provider = FakeCoreProvider(eqService: knownFake)

        let resolved = provider.makeEQService()

        XCTAssertTrue(resolved === knownFake,
                      "makeEQService must return the FakeEQService instance injected at provider construction time")
        XCTAssertEqual(provider.makeEQServiceCallCount, 1,
                       "makeEQService must be recorded exactly once per call")
    }
}
