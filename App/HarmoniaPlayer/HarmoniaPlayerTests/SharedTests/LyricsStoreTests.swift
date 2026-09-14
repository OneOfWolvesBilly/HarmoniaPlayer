//
//  LyricsStoreTests.swift
//  HarmoniaPlayerTests
//

import XCTest
@testable import Harmonia_Player

/// Tests for `LyricsStore` — the store owning the lyrics panel visibility,
/// the lyrics resolution, and the lyrics service dependencies.
///
/// The store never reads current-track state, so every test passes the
/// track explicitly. `StubLyricsService` dictates exactly what
/// `resolveAvailability(for:)` returns, driving the store's state machine
/// without exercising the real `LyricsService` logic (covered separately
/// in `LyricsServiceTests`).
///
/// `@MainActor` is required because `LyricsStore` is `@MainActor` isolated.
@MainActor
final class LyricsStoreTests: XCTestCase {

    // MARK: - Fixtures

    private var sut: LyricsStore!
    private var stubLyricsService: StubLyricsService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-lyrics-store-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        stubLyricsService = StubLyricsService()
        sut = LyricsStore(
            lyricsService: stubLyricsService,
            lyricsPreferenceStore: DefaultLyricsPreferenceStore(
                userDefaults: testDefaults
            )
        )
    }

    override func tearDown() async throws {
        sut = nil
        stubLyricsService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeTrack(
        path: String = "/tmp/song.mp3",
        lyrics: [LyricsLanguageVariant]? = nil
    ) -> Track {
        Track(url: URL(fileURLWithPath: path), title: "Test", lyrics: lyrics)
    }

    /// Constructs a stubbed embedded-source resolution.
    private func embeddedResolution(
        languages: [String?] = ["eng"],
        currentLanguage: String? = "eng"
    ) -> LyricsResolution {
        LyricsResolution(
            hasAny: true,
            currentSource: .embedded,
            availableSources: [.embedded],
            availableLanguages: languages,
            currentLanguage: currentLanguage,
            content: nil
        )
    }

    /// Constructs a stubbed resolution where both sources are available and
    /// `.embedded` is current.
    private func dualSourceResolution() -> LyricsResolution {
        LyricsResolution(
            hasAny: true,
            currentSource: .embedded,
            availableSources: [.embedded, .lrc],
            availableLanguages: ["eng"],
            currentLanguage: "eng",
            content: nil
        )
    }

    // MARK: - Initial state

    /// Given a fresh `LyricsStore`,
    /// when both properties are read,
    /// then the panel is hidden and no resolution is set.
    func testInitialState_Defaults() {
        XCTAssertFalse(sut.showLyrics, "showLyrics must start false")
        XCTAssertNil(sut.lyricsResolution, "lyricsResolution must start nil")
    }

    // MARK: - toggleLyrics

    /// Given a fresh store,
    /// when `toggleLyrics()` is called twice,
    /// then `showLyrics` flips true, then back to false.
    func testToggleLyrics_FlipsVisibility() {
        XCTAssertFalse(sut.showLyrics)
        sut.toggleLyrics()
        XCTAssertTrue(sut.showLyrics, "first toggle must show the panel")
        sut.toggleLyrics()
        XCTAssertFalse(sut.showLyrics, "second toggle must hide the panel")
    }

    // MARK: - updateResolution

    /// Given the stub returns a non-empty resolution,
    /// when `updateResolution(for:)` is called with a track,
    /// then the service is queried once with that track and the resolution
    /// is stored.
    func testUpdateResolution_NonNilTrack_QueriesServiceAndStores() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hello"),
        ])

        // When
        sut.updateResolution(for: track)

        // Then
        XCTAssertEqual(stubLyricsService.resolveAvailabilityCallCount, 1,
            "updateResolution must query lyricsService for the track")
        XCTAssertEqual(stubLyricsService.lastResolvedTrack?.id, track.id)
        XCTAssertEqual(sut.lyricsResolution?.hasAny, true)
        XCTAssertEqual(sut.lyricsResolution?.currentSource, .embedded)
    }

    /// Given a resolution is currently set,
    /// when `updateResolution(for: nil)` is called,
    /// then the resolution is cleared.
    func testUpdateResolution_NilTrack_ClearsResolution() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution()
        sut.updateResolution(for: makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ]))
        XCTAssertNotNil(sut.lyricsResolution)

        // When
        sut.updateResolution(for: nil)

        // Then
        XCTAssertNil(sut.lyricsResolution,
            "updateResolution(for: nil) should clear lyricsResolution")
    }

    /// Given the stub says no lyrics are available,
    /// when `updateResolution(for:)` is called,
    /// then the stored resolution has `hasAny == false`.
    func testUpdateResolution_NoLyrics_HasAnyFalse() {
        // Given
        stubLyricsService.stubbedResolution = .none
        let track = makeTrack(lyrics: nil)

        // When
        sut.updateResolution(for: track)

        // Then
        XCTAssertEqual(sut.lyricsResolution?.hasAny, false)
    }

    /// Given the stub returns multi-language embedded lyrics and a persisted
    /// preference selects "chi",
    /// when `updateResolution(for:)` is called,
    /// then the persisted language overrides the service default.
    func testUpdateResolution_AppliesPersistedLanguage() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution(
            languages: ["eng", "chi"],
            currentLanguage: "eng"  // service default
        )
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
            LyricsLanguageVariant(languageCode: "chi", text: "你好"),
        ])
        let pref = LyricsPreference(
            source: .embedded,
            encoding: "auto",
            languageCode: "chi",
            customPath: nil
        )
        sut.lyricsPreferenceStore.save(pref, for: track)

        // When
        sut.updateResolution(for: track)

        // Then
        XCTAssertEqual(sut.lyricsResolution?.currentLanguage, "chi",
            "persisted languageCode must override the service default")
    }

    // MARK: - setLyricsSource

    /// Given a resolution with both sources available and `.embedded`
    /// current,
    /// when `setLyricsSource(.lrc, for:)` is called,
    /// then the resolution switches to `.lrc` and the choice is persisted.
    func testSetLyricsSource_SwitchesSourceAndPersists() {
        // Given
        stubLyricsService.stubbedResolution = dualSourceResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ])
        sut.updateResolution(for: track)

        // When
        sut.setLyricsSource(.lrc, for: track)

        // Then
        XCTAssertEqual(sut.lyricsResolution?.currentSource, .lrc)
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.source, .lrc,
            "setLyricsSource must persist the chosen source")
    }

    /// Given a resolution where only `.embedded` is available,
    /// when `setLyricsSource(.lrc, for:)` is called,
    /// then the call is a no-op: the resolution keeps its source and nothing
    /// is persisted.
    func testSetLyricsSource_UnavailableSource_NoOp() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ])
        sut.updateResolution(for: track)

        // When
        sut.setLyricsSource(.lrc, for: track)

        // Then
        XCTAssertNotEqual(sut.lyricsResolution?.currentSource, .lrc,
            "an unavailable source must not become current")
        XCTAssertNil(sut.lyricsPreferenceStore.load(for: track),
            "a rejected source switch must not persist a preference")
    }

    // MARK: - setLyricsLanguage

    /// Given multi-language embedded lyrics are loaded,
    /// when `setLyricsLanguage("chi", for:)` is called,
    /// then the resolution reflects the language and the choice is persisted.
    func testSetLyricsLanguage_UpdatesResolutionAndPersists() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution(
            languages: ["eng", "chi"],
            currentLanguage: "eng"
        )
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
            LyricsLanguageVariant(languageCode: "chi", text: "你好"),
        ])
        sut.updateResolution(for: track)

        // When
        sut.setLyricsLanguage("chi", for: track)

        // Then
        XCTAssertEqual(sut.lyricsResolution?.currentLanguage, "chi")
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.languageCode, "chi",
            "setLyricsLanguage must persist the chosen language")
    }

    // MARK: - setLyricsEncoding

    /// Given a resolution is loaded,
    /// when `setLyricsEncoding("big5", for:)` is called,
    /// then the encoding is persisted.
    func testSetLyricsEncoding_PersistsValue() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ])
        sut.updateResolution(for: track)

        // When
        sut.setLyricsEncoding("big5", for: track)

        // Then
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.encoding, "big5",
            "setLyricsEncoding must persist the chosen charset")
    }

    // MARK: - attachLyricsFile

    /// Given no current track,
    /// when `attachLyricsFile(_:for: nil)` is called,
    /// then the drop is rejected and nothing happens.
    func testAttachLyricsFile_NilTrack_Rejected() {
        // When
        let accepted = sut.attachLyricsFile(
            URL(fileURLWithPath: "/tmp/dropped.lrc"), for: nil)

        // Then
        XCTAssertFalse(accepted, "a drop with no track must be rejected")
        XCTAssertEqual(stubLyricsService.installSidecarCallCount, 0)
        XCTAssertNil(sut.pendingAttach)
    }

    /// Given a track,
    /// when a non-`.lrc` file is attached,
    /// then the drop is rejected and nothing happens.
    func testAttachLyricsFile_NonLrcExtension_Rejected() {
        // Given
        let track = makeTrack()

        // When
        let accepted = sut.attachLyricsFile(
            URL(fileURLWithPath: "/tmp/notes.txt"), for: track)

        // Then
        XCTAssertFalse(accepted, "only .lrc files are accepted")
        XCTAssertEqual(stubLyricsService.installSidecarCallCount, 0)
        XCTAssertNil(sut.pendingAttach)
    }

    /// Given a track whose resolution offers no `.lrc` source,
    /// when a `.lrc` is attached,
    /// then the service installs it, the preference is persisted with
    /// `source: .lrc` / `encoding: "auto"`, the resolution is re-queried,
    /// and the panel opens.
    func testAttachLyricsFile_NoExistingLrc_InstallsAndShows() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack()
        let url = URL(fileURLWithPath: "/tmp/dropped.lrc")

        // When
        let accepted = sut.attachLyricsFile(url, for: track)

        // Then
        XCTAssertTrue(accepted)
        XCTAssertEqual(stubLyricsService.installSidecarCallCount, 1,
            "attach must install the dropped file as the sidecar")
        XCTAssertEqual(stubLyricsService.lastInstallSourceURL, url)
        XCTAssertEqual(stubLyricsService.lastInstallTrack?.id, track.id)
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.source, .lrc,
            "attach must persist the .lrc source")
        XCTAssertEqual(saved?.encoding, "auto",
            "attach must reset the encoding to auto-detect")
        XCTAssertEqual(stubLyricsService.resolveAvailabilityCallCount, 1,
            "attach must re-query availability after installing")
        XCTAssertTrue(sut.showLyrics,
            "attach must open the lyrics panel")
    }

    /// Given a track whose resolution already offers a `.lrc` source,
    /// when a `.lrc` is attached,
    /// then the replacement is staged for confirmation and nothing is
    /// installed yet.
    func testAttachLyricsFile_ExistingLrc_StagesPendingWithoutInstall() {
        // Given
        stubLyricsService.stubbedResolution = dualSourceResolution()
        let track = makeTrack()
        sut.updateResolution(for: track)
        let url = URL(fileURLWithPath: "/tmp/dropped.lrc")

        // When
        let accepted = sut.attachLyricsFile(url, for: track)

        // Then
        XCTAssertTrue(accepted)
        XCTAssertEqual(sut.pendingAttach?.sourceURL, url,
            "an existing .lrc source must stage a confirmation")
        XCTAssertEqual(sut.pendingAttach?.track.id, track.id)
        XCTAssertEqual(stubLyricsService.installSidecarCallCount, 0,
            "nothing may be installed before the user confirms")
    }

    /// Given a staged replacement,
    /// when `confirmPendingAttach()` is called,
    /// then the install runs and the staged request is cleared.
    func testConfirmPendingAttach_InstallsAndClears() {
        // Given
        stubLyricsService.stubbedResolution = dualSourceResolution()
        let track = makeTrack()
        sut.updateResolution(for: track)
        let url = URL(fileURLWithPath: "/tmp/dropped.lrc")
        sut.attachLyricsFile(url, for: track)
        XCTAssertNotNil(sut.pendingAttach)

        // When
        sut.confirmPendingAttach()

        // Then
        XCTAssertEqual(stubLyricsService.installSidecarCallCount, 1,
            "confirm must perform the staged install")
        XCTAssertNil(sut.pendingAttach,
            "confirm must clear the staged request")
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.source, .lrc)
    }

    /// Given a staged replacement,
    /// when `cancelPendingAttach()` is called,
    /// then the staged request is discarded and nothing is installed.
    func testCancelPendingAttach_ClearsWithoutInstall() {
        // Given
        let track = makeTrack()
        sut.pendingAttach = LyricsStore.PendingLyricsAttach(
            sourceURL: URL(fileURLWithPath: "/tmp/dropped.lrc"),
            track: track
        )

        // When
        sut.cancelPendingAttach()

        // Then
        XCTAssertNil(sut.pendingAttach,
            "cancel must discard the staged request")
        XCTAssertEqual(stubLyricsService.installSidecarCallCount, 0,
            "cancel must never install")
    }

    /// Given the service fails to install,
    /// when a `.lrc` is attached,
    /// then the failure surfaces on `attachErrorKey` and nothing is
    /// persisted.
    func testAttachLyricsFile_InstallThrows_SetsErrorAndPersistsNothing() {
        // Given
        stubLyricsService.stubbedInstallError = LyricsServiceError.decodingFailed
        let track = makeTrack()

        // When
        sut.attachLyricsFile(
            URL(fileURLWithPath: "/tmp/dropped.lrc"), for: track)

        // Then
        XCTAssertNotNil(sut.attachErrorKey,
            "an install failure must surface on attachErrorKey")
        XCTAssertNil(sut.lyricsPreferenceStore.load(for: track),
            "a failed install must not persist a preference")
        XCTAssertFalse(sut.showLyrics,
            "a failed install must not open the panel")
    }

    // MARK: - recheckLyrics

    /// Given a fresh store and a stubbed resolution,
    /// when `recheckLyrics(for:)` is called with a track,
    /// then the service is re-queried and the resolution is stored.
    func testRecheckLyrics_RequeriesService() {
        // Given
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ])

        // When
        sut.recheckLyrics(for: track)

        // Then
        XCTAssertEqual(stubLyricsService.resolveAvailabilityCallCount, 1,
            "recheckLyrics must re-query lyricsService for the track")
        XCTAssertEqual(sut.lyricsResolution?.hasAny, true)
    }
}
