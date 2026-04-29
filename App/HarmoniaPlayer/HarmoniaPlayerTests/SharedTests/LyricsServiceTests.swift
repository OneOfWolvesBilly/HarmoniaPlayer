//
//  LyricsServiceTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for DefaultLyricsService (Slice 9-J).
//  Uses a temp directory for sidecar .lrc file tests.
//

import XCTest
@testable import HarmoniaPlayer

final class LyricsServiceTests: XCTestCase {

    var sut: DefaultLyricsService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = DefaultLyricsService()
        // Isolated temp directory per test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        sut = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a Track pointing to a file in tempDir with the given filename.
    private func makeTrack(filename: String,
                           lyrics: [LyricsLanguageVariant]? = nil) -> Track {
        let url = tempDir.appendingPathComponent(filename)
        // Touch the audio file so the URL is non-dangling (sidecar tests use it)
        try? Data().write(to: url)
        return Track(url: url, title: "Test", lyrics: lyrics)
    }

    /// Writes a .lrc file next to the audio file.
    private func writeSidecar(name: String, content: String,
                               encoding: String.Encoding = .utf8) {
        let url = tempDir.appendingPathComponent(name)
        try? content.data(using: encoding)!.write(to: url)
    }

    /// Writes a .lrc file in a subdirectory of tempDir.
    private func writeSidecarInSubdir(subdir: String, name: String,
                                       content: String,
                                       encoding: String.Encoding = .utf8) {
        let dir = tempDir.appendingPathComponent(subdir)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? content.data(using: encoding)!.write(to: url)
    }

    // MARK: - resolveAvailability: hasAny

    func testResolveAvailability_HasAnyFalseWhenNothing() {
        let track = makeTrack(filename: "song.mp3")
        let result = sut.resolveAvailability(for: track)
        XCTAssertFalse(result.hasAny)
        XCTAssertNil(result.currentSource)
    }

    func testResolveAvailability_FallsBackToEmbeddedNoLRC() {
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [LyricsLanguageVariant(languageCode: "eng", text: "Hello")])
        let result = sut.resolveAvailability(for: track)
        XCTAssertTrue(result.hasAny)
        XCTAssertEqual(result.currentSource, .embedded)
        XCTAssertTrue(result.availableSources.contains(.embedded))
        XCTAssertFalse(result.availableSources.contains(.lrc))
    }

    func testResolveAvailability_PrefersLRCWhenNoPref() {
        // Both USLT and .lrc present — .lrc wins by default
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [LyricsLanguageVariant(languageCode: "eng", text: "Hello")])
        writeSidecar(name: "song.lrc", content: "[00:12.00]line1")
        let result = sut.resolveAvailability(for: track)
        XCTAssertTrue(result.hasAny)
        XCTAssertEqual(result.currentSource, .lrc)
        XCTAssertTrue(result.availableSources.contains(.embedded))
        XCTAssertTrue(result.availableSources.contains(.lrc))
    }

    // MARK: - resolveAvailability: language selection

    func testResolveAvailability_EmbeddedMultiLang_ListsAllLanguages() {
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [
                LyricsLanguageVariant(languageCode: "eng", text: "Hello"),
                LyricsLanguageVariant(languageCode: "chi", text: "你好"),
            ])
        let result = sut.resolveAvailability(for: track)
        XCTAssertEqual(result.availableLanguages.count, 2)
        XCTAssertTrue(result.availableLanguages.contains("eng"))
        XCTAssertTrue(result.availableLanguages.contains("chi"))
    }

    /// Verifies that when system locale matches a USLT variant, that
    /// variant's language is selected as the default.
    ///
    /// Mutates `sut.preferredLanguageCode` instead of constructing a second
    /// service — avoids a toolchain double-free when two instances coexist.
    func testResolveAvailability_PicksSystemLocaleFirst() {
        sut.preferredLanguageCode = "zh"
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [
                LyricsLanguageVariant(languageCode: "eng", text: "Hello"),
                LyricsLanguageVariant(languageCode: "chi", text: "你好"),
            ])
        let result = sut.resolveAvailability(for: track)
        XCTAssertEqual(result.currentLanguage, "chi")
    }

    /// Verifies that when system locale doesn't match any USLT variant,
    /// resolution falls back to the first variant in file order.
    ///
    /// Mutates `sut.preferredLanguageCode` instead of constructing a second
    /// service — avoids a toolchain double-free when two instances coexist.
    func testResolveAvailability_FallsBackToFirstWhenNoLocaleMatch() {
        // Locale ja → eng+chi → no match → first = "eng"
        sut.preferredLanguageCode = "ja"
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [
                LyricsLanguageVariant(languageCode: "eng", text: "Hello"),
                LyricsLanguageVariant(languageCode: "chi", text: "你好"),
            ])
        let result = sut.resolveAvailability(for: track)
        XCTAssertEqual(result.currentLanguage, "eng",
            "With no locale match, should fall back to first variant's language code")
    }

    // MARK: - Sidecar search order

    func testSidecarSearch_SameFilename() {
        let track = makeTrack(filename: "song.mp3")
        writeSidecar(name: "song.lrc", content: "Hello")
        let result = sut.resolveAvailability(for: track)
        XCTAssertTrue(result.hasAny)
        XCTAssertEqual(result.currentSource, .lrc)
    }

    func testSidecarSearch_FilenameWithExt() {
        // song.mp3.lrc (no song.lrc present)
        let track = makeTrack(filename: "song.mp3")
        writeSidecar(name: "song.mp3.lrc", content: "Hello")
        let result = sut.resolveAvailability(for: track)
        XCTAssertTrue(result.hasAny)
        XCTAssertEqual(result.currentSource, .lrc)
    }

    func testSidecarSearch_LyricsSubdir() {
        // Lyrics/song.lrc (no song.lrc or song.mp3.lrc)
        let track = makeTrack(filename: "song.mp3")
        writeSidecarInSubdir(subdir: "Lyrics", name: "song.lrc", content: "Hello")
        let result = sut.resolveAvailability(for: track)
        XCTAssertTrue(result.hasAny)
        XCTAssertEqual(result.currentSource, .lrc)
    }

    func testSidecarSearch_PrefersDirectFirst() {
        // Both song.lrc AND song.mp3.lrc exist — song.lrc wins
        let track = makeTrack(filename: "song.mp3")
        writeSidecar(name: "song.lrc",     content: "primary")
        writeSidecar(name: "song.mp3.lrc", content: "secondary")
        // resolveContent to verify which file was picked
        let result = sut.resolveAvailability(for: track)
        XCTAssertEqual(result.currentSource, .lrc)
        // Verify content is from the first-priority file
        let content = try? sut.resolveContent(
            for: track, source: .lrc, languageCode: nil, encodingName: "utf-8")
        XCTAssertEqual(content, "primary")
    }

    // MARK: - resolveContent: embedded

    func testResolveContent_EmbeddedReturnsUSLT() throws {
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [LyricsLanguageVariant(languageCode: "eng", text: "Verse one")])
        let content = try sut.resolveContent(
            for: track, source: .embedded, languageCode: "eng", encodingName: nil)
        XCTAssertEqual(content, "Verse one")
    }

    func testResolveContent_EmbeddedFallsBackToFirstWhenNoCode() throws {
        let track = makeTrack(
            filename: "song.mp3",
            lyrics: [LyricsLanguageVariant(languageCode: "eng", text: "First")])
        // Pass nil languageCode → first variant
        let content = try sut.resolveContent(
            for: track, source: .embedded, languageCode: nil, encodingName: nil)
        XCTAssertEqual(content, "First")
    }

    func testResolveContent_EmbeddedThrowsWhenNoLyrics() {
        let track = makeTrack(filename: "song.mp3") // no lyrics
        XCTAssertThrowsError(
            try sut.resolveContent(
                for: track, source: .embedded, languageCode: nil, encodingName: nil)
        )
    }

    // MARK: - resolveContent: lrc

    func testResolveContent_LRCStripsTimestamps() throws {
        let track = makeTrack(filename: "song.mp3")
        writeSidecar(name: "song.lrc",
                     content: "[ti:Song]\n[00:12.00]line1\n[00:15.50]line2")
        let content = try sut.resolveContent(
            for: track, source: .lrc, languageCode: nil, encodingName: "utf-8")
        XCTAssertEqual(content, "line1\nline2")
    }

    func testResolveContent_LRCThrowsWhenNoSidecar() {
        let track = makeTrack(filename: "song.mp3")
        XCTAssertThrowsError(
            try sut.resolveContent(
                for: track, source: .lrc, languageCode: nil, encodingName: nil)
        )
    }

    func testResolveContent_UsesPreferredEncoding() throws {
        // Write .lrc in Big5 encoding
        guard let big5Content = "測試歌詞".data(using: DefaultLyricsService.big5) else {
            throw XCTSkip("Big5 encoding not available on this platform")
        }
        let track = makeTrack(filename: "song.mp3")
        let lrcURL = tempDir.appendingPathComponent("song.lrc")
        try big5Content.write(to: lrcURL)

        let content = try sut.resolveContent(
            for: track, source: .lrc, languageCode: nil, encodingName: "big5")
        XCTAssertEqual(content, "測試歌詞")
    }
}