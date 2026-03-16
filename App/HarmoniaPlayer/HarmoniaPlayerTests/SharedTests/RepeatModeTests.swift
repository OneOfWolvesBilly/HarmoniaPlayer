//
//  RepeatModeTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class RepeatModeTests: XCTestCase {

    // MARK: - AppState default

    func testRepeatMode_DefaultIsOff() async {
        let sut = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider())
        XCTAssertEqual(sut.repeatMode, .off)
    }

    // MARK: - cycleRepeatMode

    func testCycleRepeatMode_OffToAll() async {
        let sut = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider())
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .all)
    }

    func testCycleRepeatMode_AllToOne() async {
        let sut = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider())
        sut.cycleRepeatMode()
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .one)
    }

    func testCycleRepeatMode_OneToOff() async {
        let sut = AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider())
        sut.cycleRepeatMode()
        sut.cycleRepeatMode()
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .off)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
