//
//  PlaybackErrorTests.swift
//  HarmoniaPlayerTests
//
//  Slice 1-E: Error Types and UI Preferences
//

import XCTest
@testable import HarmoniaPlayer

final class PlaybackErrorTests: XCTestCase {

    // MARK: - Equatable: Same Case

    func testPlaybackError_Equatable_SameCase() {
        XCTAssertEqual(PlaybackError.unsupportedFormat, PlaybackError.unsupportedFormat)
    }

    // MARK: - Equatable: Different Cases

    func testPlaybackError_Equatable_DifferentCase() {
        XCTAssertNotEqual(PlaybackError.failedToOpenFile, PlaybackError.failedToDecode)
    }

    // MARK: - Associated Value: coreError

    func testPlaybackError_CoreError_SameString() {
        XCTAssertEqual(PlaybackError.coreError("X"), PlaybackError.coreError("X"))
    }

    func testPlaybackError_CoreError_DifferentString() {
        XCTAssertNotEqual(PlaybackError.coreError("X"), PlaybackError.coreError("Y"))
    }

    // MARK: - Exhaustive Case Check (compile-time)
    //
    // If any of the 5 cases is missing this file will not compile,
    // which is the intended red-bar signal.

    func testPlaybackError_AllCasesExist() {
        let error: PlaybackError = .unsupportedFormat
        switch error {
        case .unsupportedFormat: break
        case .failedToOpenFile:  break
        case .failedToDecode:    break
        case .outputError:       break
        case .coreError:         break
        }
    }

    // MARK: - Error Conformance (compile-time)

    func testPlaybackError_ConformsToError() {
        // Verifies Error conformance at compile time.
        let _: Error = PlaybackError.outputError
    }
}
