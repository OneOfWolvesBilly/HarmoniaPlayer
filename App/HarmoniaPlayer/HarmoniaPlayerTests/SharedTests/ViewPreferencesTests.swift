//
//  ViewPreferencesTests.swift
//  HarmoniaPlayerTests
//
//  Slice 1-E: Error Types and UI Preferences
//

import XCTest
@testable import HarmoniaPlayer

final class ViewPreferencesTests: XCTestCase {

    // MARK: - Default Values

    func testViewPreferences_DefaultValues() {
        let prefs = ViewPreferences.defaultPreferences
        XCTAssertTrue(prefs.isWaveformVisible)
        XCTAssertTrue(prefs.isPlaylistVisible)
        XCTAssertEqual(prefs.layoutPreset, .standard)
    }

    // MARK: - Equatable

    func testViewPreferences_Equatable_SameFields() {
        let a = ViewPreferences(isWaveformVisible: true,
                                isPlaylistVisible: false,
                                layoutPreset: .compact)
        let b = ViewPreferences(isWaveformVisible: true,
                                isPlaylistVisible: false,
                                layoutPreset: .compact)
        XCTAssertEqual(a, b)
    }

    func testViewPreferences_Equatable_DifferentFields() {
        let a = ViewPreferences(isWaveformVisible: true,
                                isPlaylistVisible: true,
                                layoutPreset: .standard)
        let b = ViewPreferences(isWaveformVisible: false,
                                isPlaylistVisible: true,
                                layoutPreset: .standard)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Mutability

    func testViewPreferences_Mutable_LayoutPreset() {
        var prefs = ViewPreferences.defaultPreferences
        prefs.layoutPreset = .compact
        XCTAssertEqual(prefs.layoutPreset, .compact)
    }

    // MARK: - LayoutPreset

    func testLayoutPreset_AllCasesCount() {
        XCTAssertEqual(LayoutPreset.allCases.count, 3)
    }

    func testLayoutPreset_RawValues() {
        XCTAssertEqual(LayoutPreset.compact.rawValue,       "compact")
        XCTAssertEqual(LayoutPreset.standard.rawValue,      "standard")
        XCTAssertEqual(LayoutPreset.waveformFocused.rawValue, "waveformFocused")
    }
}
