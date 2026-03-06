//
//  PlaybackStateTests.swift
//  HarmoniaPlayerTests
//
//  Slice 1-E: Error Types and UI Preferences
//  Tests the new `error(PlaybackError)` case added to PlaybackState.
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class PlaybackStateTests: XCTestCase {

    // MARK: - error case: Equatable

    func testPlaybackState_ErrorCase_Equatable() {
        XCTAssertEqual(
            PlaybackState.error(.unsupportedFormat),
            PlaybackState.error(.unsupportedFormat)
        )
    }

    func testPlaybackState_ErrorCase_NotEqualWhenPayloadDiffers() {
        XCTAssertNotEqual(
            PlaybackState.error(.failedToOpenFile),
            PlaybackState.error(.failedToDecode)
        )
    }

    // MARK: - error case is not .playing

    func testPlaybackState_ErrorIsNotPlaying() {
        XCTAssertNotEqual(PlaybackState.error(.outputError), PlaybackState.playing)
    }

    // MARK: - Exhaustive Switch (compile-time guard for all cases)
    //
    // Ensures the error case is present alongside the existing 5 cases.
    // This file will not compile if any case is missing.

    func testPlaybackState_AllCasesExist() {
        let state: PlaybackState = .idle
        switch state {
        case .idle:    break
        case .loading: break
        case .playing: break
        case .paused:  break
        case .stopped: break
        case .error:   break
        }
    }
}
