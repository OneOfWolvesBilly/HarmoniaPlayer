//
//  AlertCenterTests.swift
//  HarmoniaPlayerTests
//

import XCTest
@testable import Harmonia_Player

// MARK: - Helpers

private func makeTrack(_ name: String = "track") -> Track {
    Track(
        url: URL(fileURLWithPath: "/tmp/\(name).mp3"),
        title: name,
        artist: "",
        album: ""
    )
}

// MARK: - Test Suite

/// Tests for `AlertCenter` — the store owning the alert, paywall, and
/// File Info request presentation state.
///
/// `@MainActor` is required because `AlertCenter` is `@MainActor` isolated.
@MainActor
final class AlertCenterTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: AlertCenter!

    override func setUp() async throws {
        try await super.setUp()
        sut = AlertCenter()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initial state

    /// Given a fresh `AlertCenter`,
    /// when all 11 properties are read,
    /// then every surface is cleared (nil / false / empty).
    func testInitialState_AllSurfacesCleared() {
        XCTAssertNil(sut.lastError, "lastError must start nil")
        XCTAssertNil(sut.lastErrorDetail, "lastErrorDetail must start nil")
        XCTAssertNil(sut.failedTrackName, "failedTrackName must start nil")
        XCTAssertFalse(sut.showFileNotFoundAlert, "showFileNotFoundAlert must start false")
        XCTAssertTrue(sut.skippedInaccessibleNames.isEmpty, "skippedInaccessibleNames must start empty")
        XCTAssertTrue(sut.skippedDuplicateURLs.isEmpty, "skippedDuplicateURLs must start empty")
        XCTAssertTrue(sut.skippedImportURLs.isEmpty, "skippedImportURLs must start empty")
        XCTAssertTrue(sut.skippedUnsupportedURLs.isEmpty, "skippedUnsupportedURLs must start empty")
        XCTAssertNil(sut.fileInfoTrack, "fileInfoTrack must start nil")
        XCTAssertFalse(sut.showPaywall, "showPaywall must start false")
        XCTAssertFalse(sut.paywallDismissedThisSession, "paywallDismissedThisSession must start false")
    }

    // MARK: - clearLastError

    /// Given a fully populated playback-error surface (5 fields),
    /// when `clearLastError()` is called,
    /// then all 5 fields are cleared.
    func testClearLastError_ClearsErrorSurface() {
        // Given
        sut.lastError = .failedToOpenFile
        sut.lastErrorDetail = "failedToOpenFile: /tmp/gone.mp3"
        sut.failedTrackName = "Gone Track"
        sut.showFileNotFoundAlert = true
        sut.skippedInaccessibleNames = ["Gone Track"]

        // When
        sut.clearLastError()

        // Then
        XCTAssertNil(sut.lastError, "clearLastError() must clear lastError")
        XCTAssertNil(sut.lastErrorDetail, "clearLastError() must clear lastErrorDetail")
        XCTAssertNil(sut.failedTrackName, "clearLastError() must clear failedTrackName")
        XCTAssertFalse(sut.showFileNotFoundAlert, "clearLastError() must lower showFileNotFoundAlert")
        XCTAssertTrue(sut.skippedInaccessibleNames.isEmpty, "clearLastError() must clear skippedInaccessibleNames")
    }

    /// Given the 3 batch-skip lists are populated,
    /// when `clearLastError()` is called,
    /// then the batch-operation lists remain unchanged — they are cleared
    /// by their own alerts' dismiss buttons, not by the error surface.
    func testClearLastError_KeepsBatchSkipLists() {
        // Given
        let duplicates = [URL(fileURLWithPath: "/tmp/dup.mp3")]
        let imports = [URL(fileURLWithPath: "/tmp/missing.mp3")]
        let unsupported = [URL(fileURLWithPath: "/tmp/odd.xyz")]
        sut.skippedDuplicateURLs = duplicates
        sut.skippedImportURLs = imports
        sut.skippedUnsupportedURLs = unsupported

        // When
        sut.clearLastError()

        // Then
        XCTAssertEqual(sut.skippedDuplicateURLs, duplicates,
                       "clearLastError() must not touch skippedDuplicateURLs")
        XCTAssertEqual(sut.skippedImportURLs, imports,
                       "clearLastError() must not touch skippedImportURLs")
        XCTAssertEqual(sut.skippedUnsupportedURLs, unsupported,
                       "clearLastError() must not touch skippedUnsupportedURLs")
    }

    // MARK: - File Info request

    /// Given a `Track`,
    /// when `presentFileInfo(_:)` is called,
    /// then `fileInfoTrack` carries that track.
    func testPresentFileInfo_SetsRequest() {
        // Given
        let track = makeTrack("info")

        // When
        sut.presentFileInfo(track)

        // Then
        XCTAssertEqual(sut.fileInfoTrack, track,
                       "presentFileInfo(_:) must set fileInfoTrack to the given track")
    }

    /// Given `fileInfoTrack` is set,
    /// when `clearFileInfoRequest()` is called,
    /// then `fileInfoTrack` is reset to `nil`.
    func testClearFileInfoRequest_Resets() {
        // Given
        sut.fileInfoTrack = makeTrack("info")

        // When
        sut.clearFileInfoRequest()

        // Then
        XCTAssertNil(sut.fileInfoTrack,
                     "clearFileInfoRequest() must reset fileInfoTrack to nil")
    }

    // MARK: - Paywall

    /// Given a fresh store,
    /// when `presentPaywall()` is called,
    /// then `showPaywall` is raised and `paywallDismissedThisSession`
    /// stays `false`.
    func testPresentPaywall_SetsFlag() {
        // When
        sut.presentPaywall()

        // Then
        XCTAssertTrue(sut.showPaywall,
                      "presentPaywall() must raise showPaywall")
        XCTAssertFalse(sut.paywallDismissedThisSession,
                       "presentPaywall() must not touch paywallDismissedThisSession")
    }
}
