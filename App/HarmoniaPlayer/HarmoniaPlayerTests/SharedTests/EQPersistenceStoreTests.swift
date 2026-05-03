//
//  EQPersistenceStoreTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Slice 9-K: EQ state persistence + schema versioning.
//

import XCTest
@testable import HarmoniaPlayer

final class EQPersistenceStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Isolated UserDefaults suite per test
        suiteName = "EQPersistenceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Round-trip

    func testEQPersistence_RoundTrip() {
        let state = EQPersistedState(
            isEnabled: true,
            preamp: -3,
            bandGains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            currentPresetName: "Rock",
            customPresets: []
        )

        let store = EQPersistenceStore(defaults: defaults)
        store.save(state)
        let loaded = store.load()

        XCTAssertEqual(loaded.isEnabled, true,
                       "isEnabled must round-trip")
        XCTAssertEqual(loaded.preamp, -3,
                       "preamp must round-trip")
        XCTAssertEqual(loaded.bandGains, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                       "bandGains must round-trip")
        XCTAssertEqual(loaded.currentPresetName, "Rock",
                       "currentPresetName must round-trip")
        XCTAssertEqual(loaded.customPresets.count, 0,
                       "customPresets must round-trip (empty)")
    }

    // MARK: - Schema version

    func testEQPersistence_WritesSchemaVersion() {
        let state = EQPersistedState.defaults
        let store = EQPersistenceStore(defaults: defaults)

        store.save(state)

        XCTAssertEqual(store.currentSchemaVersion(), 1,
                       "Saving any state must write hp.eq.schemaVersion = 1")
    }

    // MARK: - Fresh install

    func testEQPersistence_FreshInstall_ReturnsDefaults() {
        // Empty UserDefaults: no schema version, no state.
        let store = EQPersistenceStore(defaults: defaults)

        let loaded = store.load()

        XCTAssertEqual(loaded.isEnabled, false,
                       "Fresh install: isEnabled must be false")
        XCTAssertEqual(loaded.preamp, 0,
                       "Fresh install: preamp must be 0")
        XCTAssertEqual(loaded.bandGains, Array(repeating: Float(0), count: 10),
                       "Fresh install: bandGains must be all zeros")
        XCTAssertNil(loaded.currentPresetName,
                     "Fresh install: currentPresetName must be nil")
        XCTAssertEqual(loaded.customPresets.count, 0,
                       "Fresh install: customPresets must be empty")
    }

    func testEQPersistence_FreshInstall_StampsSchemaVersion() {
        // Empty UserDefaults: no schema version, no state.
        let store = EQPersistenceStore(defaults: defaults)

        _ = store.load()

        XCTAssertEqual(store.currentSchemaVersion(), 1,
                       "Fresh install load must initialise schemaVersion to 1")
    }
}
