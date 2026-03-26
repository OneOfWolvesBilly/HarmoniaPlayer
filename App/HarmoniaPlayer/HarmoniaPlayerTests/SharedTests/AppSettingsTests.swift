//
//  AppSettingsTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppSettingsTests: XCTestCase {

    private var sut: AppState!
    private var fakeService: FakePlaybackService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "hp-test-\(UUID().uuidString)"

        testDefaults = UserDefaults(suiteName: suiteName)!
        fakeService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakeService)
        sut = AppState(iapManager: MockIAPManager(), provider: provider, userDefaults: testDefaults)
    }

    override func tearDown() {
        sut = nil
        fakeService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
    }

    private func makeURL(_ name: String) -> URL {
        URL(string: "file:///audio/\(name).mp3")!
    }

    // MARK: - Default Value

    func testAllowDuplicateTracks_DefaultIsFalse() {
        XCTAssertFalse(sut.allowDuplicateTracks)
    }

    // MARK: - Default Behaviour (allowDuplicateTracks == false)

    func testLoad_DuplicateURL_DefaultBehaviour_IsSkipped() async {
        let url = makeURL("track1")
        await sut.load(urls: [url])
        XCTAssertEqual(sut.playlist.tracks.count, 1, "Precondition")

        await sut.load(urls: [url])

        XCTAssertEqual(sut.playlist.tracks.count, 1,
                       "Duplicate should be skipped when allowDuplicateTracks == false")
        XCTAssertEqual(sut.skippedDuplicateURLs.count, 1,
                       "Skipped URL should be reported")
    }

    // MARK: - Allow Duplicate Behaviour (allowDuplicateTracks == true)

    func testLoad_DuplicateURL_WhenAllowed_IsAdded() async {
        sut.allowDuplicateTracks = true
        let url = makeURL("track1")
        await sut.load(urls: [url])
        XCTAssertEqual(sut.playlist.tracks.count, 1, "Precondition")

        await sut.load(urls: [url])

        XCTAssertEqual(sut.playlist.tracks.count, 2,
                       "Duplicate should be added when allowDuplicateTracks == true")
        XCTAssertTrue(sut.skippedDuplicateURLs.isEmpty,
                      "skippedDuplicateURLs must be empty when duplicate is allowed")
    }
}
