//
//  M3U8ServiceTests.swift
//  HarmoniaPlayerTests
//

import XCTest
@testable import HarmoniaPlayer

@MainActor
final class M3U8ServiceTests: XCTestCase {

    var sut: M3U8Service!

    override func setUp() {
        super.setUp()
        sut = M3U8Service()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Export: Absolute Paths

    func testExport_ProducesValidM3U8() {
        let tracks = [
            Track(url: URL(fileURLWithPath: "/music/a.mp3"), title: "Track A", artist: "Artist A", duration: 180),
            Track(url: URL(fileURLWithPath: "/music/b.mp3"), title: "Track B", artist: "Artist B", duration: 240)
        ]
        let playlist = Playlist(name: "Test", tracks: tracks)

        let result = sut.export(playlist: playlist, pathStyle: .absolute)

        XCTAssertTrue(result.hasPrefix("#EXTM3U"), "Output must start with #EXTM3U")
        XCTAssertTrue(result.contains("/music/a.mp3"))
        XCTAssertTrue(result.contains("/music/b.mp3"))
    }

    func testExport_EXTINF_WithArtist() {
        let track = Track(
            url: URL(fileURLWithPath: "/music/creep.mp3"),
            title: "Creep",
            artist: "Radiohead",
            duration: 237
        )
        let playlist = Playlist(name: "Test", tracks: [track])

        let result = sut.export(playlist: playlist, pathStyle: .absolute)

        XCTAssertTrue(result.contains("#EXTINF:237,Radiohead - Creep"))
    }

    func testExport_EXTINF_EmptyArtist() {
        let track = Track(
            url: URL(fileURLWithPath: "/music/untitled.mp3"),
            title: "Untitled",
            artist: "",
            duration: 180
        )
        let playlist = Playlist(name: "Test", tracks: [track])

        let result = sut.export(playlist: playlist, pathStyle: .absolute)

        XCTAssertTrue(result.contains("#EXTINF:180,Untitled"))
        XCTAssertFalse(result.contains(" - Untitled"))
    }

    func testExport_EXTINF_UnknownDuration() {
        let track = Track(
            url: URL(fileURLWithPath: "/music/unknown.mp3"),
            title: "Unknown",
            artist: "Artist",
            duration: 0
        )
        let playlist = Playlist(name: "Test", tracks: [track])

        let result = sut.export(playlist: playlist, pathStyle: .absolute)

        XCTAssertTrue(result.contains("#EXTINF:-1,"))
    }

    // MARK: - Export: Relative Paths

    func testExport_RelativePaths_SameDirectory() {
        let track = Track(
            url: URL(fileURLWithPath: "/music/a.mp3"),
            title: "Track A",
            duration: 180
        )
        let playlist = Playlist(name: "Test", tracks: [track])
        let m3u8URL = URL(fileURLWithPath: "/music/export.m3u8")

        let result = sut.export(playlist: playlist, pathStyle: .relative(to: m3u8URL))

        XCTAssertTrue(result.contains("a.mp3"))
        XCTAssertFalse(result.contains("/music/a.mp3"))
    }

    func testExport_RelativePaths_SubDirectory() {
        let track = Track(
            url: URL(fileURLWithPath: "/music/rock/a.mp3"),
            title: "Track A",
            duration: 180
        )
        let playlist = Playlist(name: "Test", tracks: [track])
        let m3u8URL = URL(fileURLWithPath: "/music/export.m3u8")

        let result = sut.export(playlist: playlist, pathStyle: .relative(to: m3u8URL))

        XCTAssertTrue(result.contains("rock/a.mp3"))
        XCTAssertFalse(result.contains("/music/rock/a.mp3"))
    }

    // MARK: - Parse

    func testParse_AbsolutePaths_ReturnsURLs() {
        let m3u8 = """
        #EXTM3U
        #EXTINF:180,Artist A - Track A
        /music/a.mp3
        #EXTINF:240,Artist B - Track B
        /music/b.mp3
        """

        let result = sut.parse(m3u8: m3u8, baseURL: nil)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], URL(fileURLWithPath: "/music/a.mp3"))
        XCTAssertEqual(result[1], URL(fileURLWithPath: "/music/b.mp3"))
    }

    func testParse_RelativePaths_ResolvesAgainstBase() {
        let m3u8 = """
        #EXTM3U
        #EXTINF:180,Track A
        a.mp3
        """
        let baseURL = URL(fileURLWithPath: "/music/export.m3u8")

        let result = sut.parse(m3u8: m3u8, baseURL: baseURL)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], URL(fileURLWithPath: "/music/a.mp3"))
    }

    func testParse_IgnoresCommentLines() {
        let m3u8 = """
        #EXTM3U
        #EXTINF:180,Some Artist - Some Title
        /music/a.mp3
        """

        let result = sut.parse(m3u8: m3u8, baseURL: nil)

        XCTAssertEqual(result.count, 1)
    }

    func testParse_EmptyString() {
        let result = sut.parse(m3u8: "", baseURL: nil)

        XCTAssertTrue(result.isEmpty)
    }
}
