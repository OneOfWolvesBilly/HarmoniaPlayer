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

    // MARK: - New Cases: invalidState and invalidArgument

    func testPlaybackError_InvalidState_NotEqualInvalidArgument() {
        XCTAssertNotEqual(PlaybackError.invalidState, PlaybackError.invalidArgument)
    }

    func testPlaybackError_InvalidState_EqualsSelf() {
        XCTAssertEqual(PlaybackError.invalidState, PlaybackError.invalidState)
    }

    func testPlaybackError_InvalidArgument_EqualsSelf() {
        XCTAssertEqual(PlaybackError.invalidArgument, PlaybackError.invalidArgument)
    }

    // MARK: - Exhaustive Case Check (compile-time)
    //
    // If any case is missing this file will not compile,
    // which is the intended red-bar signal.

    func testPlaybackError_AllCasesExist() {
        let error: PlaybackError = .unsupportedFormat
        switch error {
        case .unsupportedFormat: break
        case .failedToOpenFile:  break
        case .failedToDecode:    break
        case .outputError:       break
        case .invalidState:      break
        case .invalidArgument:   break
        }
    }

    // MARK: - Error Conformance (compile-time)

    func testPlaybackError_ConformsToError() {
        // Verifies Error conformance at compile time.
        let _: Error = PlaybackError.outputError
    }
}
