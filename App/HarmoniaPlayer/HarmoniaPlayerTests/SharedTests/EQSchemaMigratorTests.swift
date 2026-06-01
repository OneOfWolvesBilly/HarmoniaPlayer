//
//  EQSchemaMigratorTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Slice 9-K: schema migrator, version-1 identity branch.
//

import XCTest
@testable import Harmonia_Player

final class EQSchemaMigratorTests: XCTestCase {

    func testEQSchemaMigrator_Version1_IsIdentity() {
        let state = EQPersistedState(
            isEnabled: true,
            preamp: -3,
            bandGains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            currentPresetName: "Rock",
            customPresets: []
        )

        let migrated = EQSchemaMigrator.migrate(
            from: 1,
            to: 1,
            state: state
        )

        XCTAssertEqual(migrated.isEnabled, state.isEnabled,
                       "isEnabled must be unchanged")
        XCTAssertEqual(migrated.preamp, state.preamp,
                       "preamp must be unchanged")
        XCTAssertEqual(migrated.bandGains, state.bandGains,
                       "bandGains must be unchanged")
        XCTAssertEqual(migrated.currentPresetName, state.currentPresetName,
                       "currentPresetName must be unchanged")
        XCTAssertEqual(migrated.customPresets.count, state.customPresets.count,
                       "customPresets count must be unchanged")
    }
}
