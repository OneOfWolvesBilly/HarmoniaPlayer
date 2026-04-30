//
//  AppStateLyricsTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests AppState lyrics integration (Slice 9-J):
//  - showLyrics toggle
//  - updateLyricsResolution applies persisted preferences
//  - setLyricsLanguage / setLyricsEncoding actions persist preference
//
//  TEST STRATEGY
//  -------------
//  These tests verify AppState's lyrics business logic synchronously by
//  calling `updateLyricsResolution(for:)` and the action methods directly.
//  They do NOT exercise the `$currentTrack` Combine subscription, because:
//
//  1. The subscription is plumbing (one-line `.sink` that forwards the
//     value to `updateLyricsResolution`). Verifying its dispatch timing
//     would test Combine framework, not our code (Khorikov DON'T #3).
//
//  2. Sleep-based async tests violate F.I.R.S.T. (Fast / Repeatable):
//     they slow the suite and become flaky under load.
//
//  3. The injected stub `StubLyricsService` lets us control exactly what
//     `resolveAvailability(for:)` returns, so we can drive AppState's
//     state machine without exercising the real LyricsService logic
//     (covered separately in LyricsServiceTests).
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStateLyricsTests: XCTestCase {

    private var sut: AppState!
    private var fakeTagReader: FakeTagReaderService!
    private var stubLyricsService: StubLyricsService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "hp-lyrics-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        fakeTagReader = FakeTagReaderService()
        // Match TagBundle.currentSchemaVersion to avoid spurious metadata refresh
        fakeTagReader.stubbedSchemaVersion = 2
        stubLyricsService = StubLyricsService()
        let provider = FakeCoreProvider(
            tagReader: fakeTagReader,
            lyricsService: stubLyricsService
        )
        sut = AppState(
            iapManager: MockIAPManager(),
            provider: provider,
            userDefaults: testDefaults
        )
    }

    override func tearDown() async throws {
        sut = nil
        fakeTagReader = nil
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

    // MARK: - Initial state

    func testAppState_InitialState_LyricsDefaults() {
        XCTAssertFalse(sut.showLyrics)
        XCTAssertNil(sut.lyricsResolution)
    }

    // MARK: - toggleLyrics

    func testAppState_ToggleLyrics_FlipsVisibility() {
        XCTAssertFalse(sut.showLyrics)
        sut.toggleLyrics()
        XCTAssertTrue(sut.showLyrics)
        sut.toggleLyrics()
        XCTAssertFalse(sut.showLyrics)
    }

    // MARK: - updateLyricsResolution

    func testAppState_UpdateLyricsResolution_NonNilTrack_QueriesServiceAndStores() {
        // Given: stub returns a non-empty resolution
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hello"),
        ])

        // When
        sut.updateLyricsResolution(for: track)

        // Then
        XCTAssertEqual(stubLyricsService.resolveAvailabilityCallCount, 1,
            "updateLyricsResolution must query lyricsService for the track")
        XCTAssertEqual(stubLyricsService.lastResolvedTrack?.id, track.id)
        XCTAssertEqual(sut.lyricsResolution?.hasAny, true)
        XCTAssertEqual(sut.lyricsResolution?.currentSource, .embedded)
    }

    func testAppState_UpdateLyricsResolution_NilTrack_ClearsResolution() {
        // Given: a resolution is currently set
        stubLyricsService.stubbedResolution = embeddedResolution()
        sut.updateLyricsResolution(for: makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ]))
        XCTAssertNotNil(sut.lyricsResolution)

        // When
        sut.updateLyricsResolution(for: nil)

        // Then
        XCTAssertNil(sut.lyricsResolution,
            "updateLyricsResolution(for: nil) should clear lyricsResolution")
    }

    func testAppState_UpdateLyricsResolution_NoLyrics_HasAnyFalse() {
        // Given: stub says no lyrics available
        stubLyricsService.stubbedResolution = .none
        let track = makeTrack(lyrics: nil)

        // When
        sut.updateLyricsResolution(for: track)

        // Then
        XCTAssertEqual(sut.lyricsResolution?.hasAny, false)
    }

    // MARK: - Persisted preference applied on update

    func testAppState_UpdateLyricsResolution_AppliesPersistedLanguage() {
        // Given: stub returns multi-lang embedded; persisted pref says "chi"
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
        sut.updateLyricsResolution(for: track)

        // Then: persisted languageCode "chi" overrides service default "eng"
        XCTAssertEqual(sut.lyricsResolution?.currentLanguage, "chi")
    }

    // MARK: - setLyricsLanguage

    func testAppState_SetLyricsLanguage_UpdatesResolutionAndPersists() {
        // Given: track loaded with embedded lyrics
        stubLyricsService.stubbedResolution = embeddedResolution(
            languages: ["eng", "chi"],
            currentLanguage: "eng"
        )
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
            LyricsLanguageVariant(languageCode: "chi", text: "你好"),
        ])
        sut.currentTrack = track
        sut.updateLyricsResolution(for: track)

        // When
        sut.setLyricsLanguage("chi")

        // Then: resolution reflects + pref persisted
        XCTAssertEqual(sut.lyricsResolution?.currentLanguage, "chi")
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.languageCode, "chi")
    }

    // MARK: - setLyricsEncoding

    func testAppState_SetLyricsEncoding_PersistsValue() {
        // Given: track loaded
        stubLyricsService.stubbedResolution = embeddedResolution()
        let track = makeTrack(lyrics: [
            LyricsLanguageVariant(languageCode: "eng", text: "Hi"),
        ])
        sut.currentTrack = track
        sut.updateLyricsResolution(for: track)

        // When
        sut.setLyricsEncoding("big5")

        // Then
        let saved = sut.lyricsPreferenceStore.load(for: track)
        XCTAssertEqual(saved?.encoding, "big5")
    }
}
