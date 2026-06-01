//
//  EQCoordinatorTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Slice 9-K (commit 6): EQCoordinator owns all EQ-related observable
//  state and coordinates between EQService (Core control surface) and
//  EQPersistenceStore (UserDefaults).
//
//  TEST SCOPE
//  ----------
//  Six contract tests from the spec TDD matrix (rows
//  testEQCoordinator_*) plus testEQDisabled_BypassesEntirely (spec
//  row testEQDisabled_BypassesEntirely, asserted at coordinator level
//  as a forwarding test — when the coordinator is disabled, the
//  service receives setEnabled(false) and the band gains are
//  irrelevant to audio output).
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - Test target builds with SWIFT_VERSION = 5.0; the main module
//    builds with 6.0 + SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//  - `@MainActor` IS applied to this test class because
//    `EQCoordinator` itself is @MainActor — calling its methods from
//    test methods must happen on the main actor. This differs from
//    LyricsServiceTests (whose SUT is not @MainActor) and matches
//    AppStateReplayGainTests (whose SUT, AppState, is @MainActor).
//  - No explicit `deinit` body in this class, so the Xcode 26 beta
//    `swift_task_deinitOnExecutorImpl` TaskLocal teardown crash does
//    not apply (the bug only bites @MainActor classes that DO declare
//    an explicit deinit).
//

import XCTest
@testable import Harmonia_Player

@MainActor
final class EQCoordinatorTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: EQCoordinator!
    private var fakeService: FakeEQService!
    private var store: EQPersistenceStore!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-eq-coord-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        fakeService = FakeEQService()
        store = EQPersistenceStore(defaults: testDefaults)
        sut = EQCoordinator(service: fakeService, store: store)
    }

    override func tearDown() {
        sut = nil
        store = nil
        fakeService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - selectPreset (builtin)

    /// Selecting a built-in preset must apply that preset's per-band
    /// gains to both the coordinator's own published `bandGains` and
    /// the underlying EQService.
    func testEQCoordinator_SelectBuiltinPreset_AppliesGains() {
        let rock = EQPresets.builtin.first { $0.name == "Rock" }!
        let expectedGains = rock.bands.map { $0.gain }

        sut.selectPreset("Rock")

        XCTAssertEqual(sut.bandGains, expectedGains,
                       "Coordinator's bandGains must match the selected built-in preset")
        XCTAssertEqual(fakeService.lastSetBandGains, expectedGains,
                       "EQService must receive the selected preset's gains")
    }

    // MARK: - Modify band -> custom

    /// After selecting a built-in preset and then modifying a single
    /// band, `currentPresetName` must clear to nil — the live state
    /// no longer matches any saved preset.
    func testEQCoordinator_ModifyBand_MarksAsCustomState() {
        sut.selectPreset("Rock")
        XCTAssertEqual(sut.currentPresetName, "Rock",
                       "Precondition: a built-in preset must be selected before modification")

        sut.setBand(index: 2, gain: 0)

        XCTAssertNil(sut.currentPresetName,
                     "Modifying any band must clear currentPresetName to nil")
    }

    // MARK: - Save custom preset

    /// `saveAsCustomPreset(name:)` with a non-colliding name must
    /// append the current state as a new preset to `customPresets`.
    func testEQCoordinator_SaveCustomPreset_AppendsToList() throws {
        sut.setBand(index: 0, gain: 4)
        sut.setBand(index: 9, gain: -2)

        try sut.saveAsCustomPreset(name: "My EQ")

        XCTAssertTrue(sut.customPresets.contains { $0.name == "My EQ" },
                      "customPresets must contain the saved entry")
    }

    /// `saveAsCustomPreset(name:)` must reject names that collide
    /// with built-in presets. The save must not mutate
    /// `customPresets`.
    func testEQCoordinator_SaveCustomPreset_RejectsBuiltinName() {
        let countBefore = sut.customPresets.count

        XCTAssertThrowsError(try sut.saveAsCustomPreset(name: "Rock"),
                             "Saving with built-in name 'Rock' must throw")

        XCTAssertEqual(sut.customPresets.count, countBefore,
                       "customPresets must be unchanged after a rejected save")
    }

    // MARK: - Delete custom preset

    /// `deleteCustomPreset(_:)` must remove a previously saved custom
    /// preset from the list.
    func testEQCoordinator_DeleteCustomPreset_RemovesFromList() throws {
        try sut.saveAsCustomPreset(name: "My EQ")
        XCTAssertTrue(sut.customPresets.contains { $0.name == "My EQ" },
                      "Precondition: 'My EQ' must exist before delete")

        sut.deleteCustomPreset("My EQ")

        XCTAssertFalse(sut.customPresets.contains { $0.name == "My EQ" },
                       "'My EQ' must be removed from customPresets after delete")
    }

    /// `deleteCustomPreset(_:)` must NOT remove built-in presets even
    /// if the caller passes a built-in name. The list of built-in
    /// presets is immutable from the user's perspective.
    func testEQCoordinator_DeleteBuiltin_Rejected() {
        // Save one custom preset so the customPresets list is non-empty
        // and we can prove "Rock" delete didn't accidentally hit it.
        try? sut.saveAsCustomPreset(name: "Custom A")
        let customsBefore = sut.customPresets

        sut.deleteCustomPreset("Rock")

        XCTAssertEqual(sut.customPresets, customsBefore,
                       "deleteCustomPreset on a built-in name must leave customPresets unchanged")
        XCTAssertTrue(EQPresets.builtin.contains { $0.name == "Rock" },
                      "Rock must remain available as a built-in preset")
    }

    // MARK: - Disabled bypass

    /// When the coordinator is disabled, the EQ node receives
    /// `setEnabled(false)` and audio bypasses the EQ entirely —
    /// regardless of the per-band gain values. The coordinator may
    /// still hold non-zero gain values internally; they must not
    /// affect the bypass.
    func testEQDisabled_BypassesEntirely() {
        sut.setEnabled(false)
        for index in 0..<10 {
            sut.setBand(index: index, gain: 6)
        }

        XCTAssertFalse(sut.isEnabled,
                       "Coordinator must reflect disabled state")
        XCTAssertEqual(fakeService.lastSetEnabled, false,
                       "EQService must receive setEnabled(false) so audio bypasses the EQ node")
    }
}
