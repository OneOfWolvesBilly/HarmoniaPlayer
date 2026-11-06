//
//  PlaybackControllerErrorMappingTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the `PlaybackController` error paths: the one-line
/// `lastErrorDetail` written to the alert store on `play(trackID:)` and
/// `seek(to:)` failures.
@MainActor
final class PlaybackControllerErrorMappingTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() async throws {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private struct Fixture {
        let sut: PlaybackController
        let fake: FakePlaybackService
        let context: FakePlaylistContext
        let alertCenter: AlertCenter
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let fake = FakePlaybackService()
        let context = FakePlaylistContext()
        let alertCenter = AlertCenter()
        let sut = PlaybackController(
            playbackService: fake,
            alertCenter: alertCenter,
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        sut.playlistContext = context
        return Fixture(sut: sut, fake: fake, context: context, alertCenter: alertCenter)
    }

    /// Seeds one track named `name` into the context and returns it.
    private func seedOneTrack(_ f: Fixture, named name: String) -> Track {
        let track = Track(url: URL(fileURLWithPath: "/tmp/\(name).mp3"))
        f.context.playlists[0].tracks = [track]
        return track
    }

    // MARK: - Tests

    /// Given `play(trackID:)` throws `.failedToDecode`,
    /// when the error occurs,
    /// then `lastErrorDetail` contains `"failedToDecode"` and `track.url.path`.
    func testLastErrorDetail_PlayTrackDecodeFailure_ContainsCodeAndPath() async throws {
        let f = makeSUT()
        f.fake.stubbedLoadError = PlaybackError.failedToDecode
        let track = seedOneTrack(f, named: "decode-fail")

        await f.sut.play(trackID: track.id)

        let detail = try XCTUnwrap(f.alertCenter.lastErrorDetail, "lastErrorDetail must be set on play(trackID:) failure")
        XCTAssertTrue(detail.contains("failedToDecode"),
                      "lastErrorDetail must contain error code, got: \(detail)")
        XCTAssertTrue(detail.contains(track.url.path),
                      "lastErrorDetail must contain track.url.path, got: \(detail)")
    }

    /// Given `play(trackID:)` is called with an inaccessible track,
    /// when the inaccessibility gate trips,
    /// then `lastErrorDetail` contains `"failedToOpenFile"` and `track.url.path`.
    func testLastErrorDetail_InaccessibleTrack_ContainsCodeAndPath() async throws {
        let f = makeSUT()
        let track = seedOneTrack(f, named: "inaccessible")
        f.context.playlists[0].tracks[0].isAccessible = false

        await f.sut.play(trackID: track.id)

        let detail = try XCTUnwrap(f.alertCenter.lastErrorDetail, "lastErrorDetail must be set when inaccessibility gate trips")
        XCTAssertTrue(detail.contains("failedToOpenFile"),
                      "lastErrorDetail must contain error code, got: \(detail)")
        XCTAssertTrue(detail.contains(track.url.path),
                      "lastErrorDetail must contain track.url.path, got: \(detail)")
    }

    /// Given `seek(to:)` throws,
    /// when the error occurs,
    /// then `lastErrorDetail` contains the error code and `"(no active track)"`
    /// because the seek catch path does not know which track it was seeking in.
    func testLastErrorDetail_SeekFailure_ContainsCodeAndNoTrack() async throws {
        let f = makeSUT()
        f.fake.stubbedSeekError = PlaybackError.invalidState

        await f.sut.seek(to: 30)

        let detail = try XCTUnwrap(f.alertCenter.lastErrorDetail, "lastErrorDetail must be set on seek failure")
        XCTAssertTrue(detail.contains("invalidState"),
                      "lastErrorDetail must contain error code, got: \(detail)")
        XCTAssertTrue(detail.contains("(no active track)"),
                      "lastErrorDetail must contain '(no active track)' marker on seek catch path, got: \(detail)")
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
