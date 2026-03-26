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

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT() -> AppState {
        let name = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(name)
        let defaults = UserDefaults(suiteName: name)!
        return AppState(iapManager: MockIAPManager(), provider: FakeCoreProvider(), userDefaults: defaults)
    }

    // MARK: - AppState default

    func testRepeatMode_DefaultIsOff() async {
        let sut = makeSUT()
        XCTAssertEqual(sut.repeatMode, .off)
    }

    // MARK: - cycleRepeatMode

    func testCycleRepeatMode_OffToAll() async {
        let sut = makeSUT()
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .all)
    }

    func testCycleRepeatMode_AllToOne() async {
        let sut = makeSUT()
        sut.cycleRepeatMode()
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .one)
    }

    func testCycleRepeatMode_OneToOff() async {
        let sut = makeSUT()
        sut.cycleRepeatMode()
        sut.cycleRepeatMode()
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .off)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
