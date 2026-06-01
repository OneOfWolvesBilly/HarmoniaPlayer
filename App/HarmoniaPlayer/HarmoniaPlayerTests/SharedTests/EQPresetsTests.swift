//
//  EQPresetsTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Slice 9-K: built-in EQ presets contract.
//
//  RED PHASE
//  ---------
//  Both tests fail because EQPresets.builtin is currently an empty
//  array. The green phase populates it with 8 presets.
//

import XCTest
@testable import Harmonia_Player

final class EQPresetsTests: XCTestCase {

    // MARK: - Existence

    func testEQPresets_FlatBuiltinExists() {
        let names = EQPresets.builtin.map { $0.name }
        XCTAssertTrue(names.contains("Flat"),
                      "Built-in presets must include 'Flat'; got \(names)")
    }

    // MARK: - Shape

    /// `Rock` preset must boost low and high frequencies and scoop the
    /// mids (per spec §9-K Built-in Presets textual description).
    /// The exact dB values are an implementation choice; this test
    /// asserts only the qualitative shape.
    func testEQPresets_RockHasExpectedShape() {
        guard let rock = EQPresets.builtin.first(where: { $0.name == "Rock" }) else {
            XCTFail("Built-in presets must include 'Rock'")
            return
        }

        XCTAssertEqual(rock.bands.count, 10,
                       "Rock preset must have 10 band states")

        let low = rock.bands[0].gain   // 32 Hz
        let mid = rock.bands[4].gain   // 500 Hz
        let high = rock.bands[9].gain  // 16 kHz

        XCTAssertGreaterThan(low, 0,
                             "Rock: low band must be boosted (>0 dB); got \(low)")
        XCTAssertLessThan(mid, 0,
                          "Rock: mid band must be scooped (<0 dB); got \(mid)")
        XCTAssertGreaterThan(high, 0,
                             "Rock: high band must be boosted (>0 dB); got \(high)")
    }
}
