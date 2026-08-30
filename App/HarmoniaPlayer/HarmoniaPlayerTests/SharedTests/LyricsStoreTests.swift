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
