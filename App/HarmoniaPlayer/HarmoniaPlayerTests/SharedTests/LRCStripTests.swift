//
//  LRCStripTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for DefaultLyricsService.stripLRCTimestamps (Slice 9-J).
//

import XCTest
@testable import HarmoniaPlayer

final class LRCStripTests: XCTestCase {

    var sut: DefaultLyricsService!

    override func setUp() {
        super.setUp()
        sut = DefaultLyricsService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Timestamp stripping

    func testLRCStrip_RemovesTimestamps() {
        let input = "[00:12.00]line1\n[00:15.50]line2"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "line1\nline2")
    }

    func testLRCStrip_RemovesTimestampsWithoutDecimals() {
        let input = "[00:12]line1\n[01:30]line2"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "line1\nline2")
    }

    func testLRCStrip_MultipleTimestampsOnOneLine() {
        // Some LRC files have multiple timestamps per lyric line
        let input = "[00:12.00][00:45.00]chorus line"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "chorus line")
    }

    // MARK: - Metadata tag stripping

    func testLRCStrip_RemovesMetadataTags() {
        let input = "[ti:title]\n[ar:artist]\n[00:12.00]line"
        let result = sut.stripLRCTimestamps(input)
        // Metadata tag lines removed entirely; only the lyric line remains
        XCTAssertEqual(result, "line")
    }

    func testLRCStrip_RemovesOffsetTag() {
        let input = "[offset:200]\n[00:12.00]line"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "line")
    }

    func testLRCStrip_RemovesAlbumAndByricistTags() {
        let input = "[al:Album]\n[by:Lyricist]\n[00:12.00]line"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "line")
    }

    // MARK: - Blank line preservation

    func testLRCStrip_KeepsBlankLines() {
        let input = "[00:12]a\n\n[00:15]b"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "a\n\nb")
    }

    func testLRCStrip_KeepsMultipleConsecutiveBlankLines() {
        let input = "[00:12]verse1\n\n\n[00:30]verse2"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "verse1\n\n\nverse2")
    }

    // MARK: - Lines without timestamps

    func testLRCStrip_PlainTextLinesUnchanged() {
        let input = "plain text\nno timestamps here"
        let result = sut.stripLRCTimestamps(input)
        XCTAssertEqual(result, "plain text\nno timestamps here")
    }

    func testLRCStrip_EmptyStringReturnsEmpty() {
        XCTAssertEqual(sut.stripLRCTimestamps(""), "")
    }
}
