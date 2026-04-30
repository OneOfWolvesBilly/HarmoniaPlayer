//
//  LyricsPreferenceStoreTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for DefaultLyricsPreferenceStore (Slice 9-J).
//

import XCTest
@testable import HarmoniaPlayer

final class LyricsPreferenceStoreTests: XCTestCase {

    var sut: DefaultLyricsPreferenceStore!
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        // Isolated UserDefaults suite per test
        suiteName = "LyricsPreferenceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        sut = DefaultLyricsPreferenceStore(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func track(at path: String) -> Track {
        Track(url: URL(fileURLWithPath: path))
    }

    // MARK: - key(for:)

    func testPreferenceStore_NonCueKey() {
        let t = track(at: "/Music/song.mp3")
        XCTAssertEqual(sut.key(for: t), "hp.lyrics.prefs./Music/song.mp3")
    }

    func testPreferenceStore_KeyUsesAbsolutePath() {
        let t = track(at: "/Users/test/Library/Audio/file.flac")
        XCTAssertEqual(sut.key(for: t),
            "hp.lyrics.prefs./Users/test/Library/Audio/file.flac")
    }

    // MARK: - load / save round-trip

    func testPreferenceStore_LoadReturnsNilWhenAbsent() {
        let t = track(at: "/Music/missing.mp3")
        XCTAssertNil(sut.load(for: t))
    }

    func testPreferenceStore_SaveAndLoadRoundTrip() {
        let t = track(at: "/Music/song.mp3")
        let pref = LyricsPreference(
            source: .lrc,
            encoding: "utf-8",
            languageCode: "eng",
            customPath: nil
        )
        sut.save(pref, for: t)
        let loaded = sut.load(for: t)
        XCTAssertEqual(loaded, pref)
    }

    func testPreferenceStore_SaveOverwritesPrevious() {
        let t = track(at: "/Music/song.mp3")
        let first = LyricsPreference(source: .embedded, encoding: "auto",
                                     languageCode: "eng", customPath: nil)
        let second = LyricsPreference(source: .lrc, encoding: "big5",
                                      languageCode: nil, customPath: nil)
        sut.save(first, for: t)
        sut.save(second, for: t)
        XCTAssertEqual(sut.load(for: t), second)
    }

    // MARK: - Different tracks isolated

    func testPreferenceStore_DifferentTracksAreIsolated() {
        let a = track(at: "/Music/a.mp3")
        let b = track(at: "/Music/b.mp3")
        let prefA = LyricsPreference(source: .embedded, encoding: "auto",
                                     languageCode: "eng", customPath: nil)
        sut.save(prefA, for: a)
        XCTAssertNil(sut.load(for: b),
            "Saving preference for track A must not affect track B")
    }
}
