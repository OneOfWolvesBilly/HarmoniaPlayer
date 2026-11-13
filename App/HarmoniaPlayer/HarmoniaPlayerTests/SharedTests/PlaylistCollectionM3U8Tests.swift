//
//  PlaylistCollectionM3U8Tests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for the M3U8 import and export of `PlaylistCollection`.
@MainActor
final class PlaylistCollectionM3U8Tests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private struct Fixture {
        let sut: PlaylistCollection
        let alertCenter: AlertCenter
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let alertCenter = AlertCenter()
        let sut = PlaylistCollection(
            tagReaderService: FakeTagReaderService(),
            fileDropService: FileDropService(),
            playlistStore: FakePlaylistStore(),
            undoManager: UndoManager(),
            alertCenter: alertCenter,
            settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
            userDefaults: defaults
        )
        return Fixture(sut: sut, alertCenter: alertCenter)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    /// Creates a temp directory with empty stub files and a `.m3u8` referencing them.
    private func makeM3U8(named name: String = "test", filenames: [String]) throws -> URL {
        let dir = try makeTempDir()
        for filename in filenames {
            let fileURL = dir.appendingPathComponent(filename)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let m3u8URL = dir.appendingPathComponent("\(name).m3u8")
        var lines = ["#EXTM3U"]
        for filename in filenames {
            let absPath = dir.appendingPathComponent(filename).path
            lines.append("#EXTINF:-1,\(filename)")
            lines.append(absPath)
        }
        try lines.joined(separator: "\n").write(to: m3u8URL, atomically: true, encoding: .utf8)
        return m3u8URL
    }

    // MARK: - importPlaylist(from:)

    func testImportPlaylist_ResetsBlockingFlagOnCompletion() async {
        let f = makeSUT()

        // importPlaylist with a non-existent file hits the early return guard;
        // defer must still reset the flag.
        await f.sut.importPlaylist(from: URL(fileURLWithPath: "/tmp/nonexistent.m3u8"))

        XCTAssertFalse(f.sut.isPerformingBlockingOperation,
                       "Flag must be reset after importPlaylist completes (even on error path)")
    }

    func testImportPlaylist_SkipsUnsupportedFormat() async throws {
        let f = makeSUT()
        let m3u8 = try makeM3U8(filenames: ["track.xyz"])

        await f.sut.importPlaylist(from: m3u8)

        XCTAssertTrue(f.sut.playlist.tracks.isEmpty,
                      "Unsupported format must not be added via importPlaylist")
        XCTAssertEqual(f.alertCenter.skippedImportURLs.count, 1,
                       "Unsupported file must appear in skippedImportURLs")
    }

    func testImportPlaylist_SkipsUnsupportedFormat_KeepsSupported() async throws {
        let f = makeSUT()
        let m3u8 = try makeM3U8(filenames: ["good.mp3", "bad.xyz"])

        await f.sut.importPlaylist(from: m3u8)

        XCTAssertEqual(f.sut.playlist.tracks.count, 1,
                       "Only the supported format track must be added")
        XCTAssertEqual(f.alertCenter.skippedImportURLs.count, 1,
                       "The unsupported file must be reported in skippedImportURLs")
    }

    /// FLAC is blocked in importPlaylist too (treated as unsupported).
    func testImportPlaylist_FLAC_BlockedAsUnsupported() async throws {
        let f = makeSUT()
        let m3u8 = try makeM3U8(filenames: ["track.flac"])

        await f.sut.importPlaylist(from: m3u8)

        XCTAssertTrue(f.sut.playlist.tracks.isEmpty, "FLAC must be blocked in importPlaylist")
        XCTAssertEqual(f.alertCenter.skippedImportURLs.count, 1)
    }

    func testImportPlaylist_CreatesTabNamedAfterFile() async throws {
        let f = makeSUT()
        let m3u8 = try makeM3U8(named: "mix", filenames: ["one.mp3"])

        await f.sut.importPlaylist(from: m3u8)

        XCTAssertEqual(f.sut.playlists.count, 2, "import must create a new playlist tab")
        XCTAssertEqual(f.sut.activePlaylistIndex, 1, "the new tab must become active")
        XCTAssertEqual(f.sut.playlist.name, "mix", "the tab is named after the file")
        XCTAssertEqual(f.sut.playlist.tracks.count, 1)
    }

    func testImportPlaylist_UnreadableFile_SetsLastError() async {
        let f = makeSUT()

        await f.sut.importPlaylist(from: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m3u8"))

        XCTAssertEqual(f.alertCenter.lastError, .failedToOpenFile)
        XCTAssertEqual(f.sut.playlists.count, 1, "an unreadable file must not create a tab")
    }

    // MARK: - writeExport

    func testWriteExport_WritesActivePlaylistAsM3U8() async throws {
        let f = makeSUT()
        let trackURL = URL(fileURLWithPath: "/tmp/export-a.mp3")
        await f.sut.load(urls: [trackURL])
        let destination = try makeTempDir().appendingPathComponent("out.m3u8")

        try f.sut.writeExport(to: destination, pathStyle: .absolute)

        let content = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("#EXTM3U"), "export must start with the M3U8 header")
        XCTAssertTrue(content.contains(trackURL.path), "export must list the track path")
    }

    func testWriteExport_PlaylistAt_WritesThatPlaylist() async throws {
        let f = makeSUT()
        let trackURL = URL(fileURLWithPath: "/tmp/export-b.mp3")
        await f.sut.load(urls: [trackURL])          // into playlist 0
        f.sut.newPlaylist(name: "Other")            // active becomes 1 (empty)
        let destination = try makeTempDir().appendingPathComponent("out.m3u8")

        try f.sut.writeExport(playlistAt: 0, to: destination, pathStyle: .absolute)

        let content = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(content.contains(trackURL.path), "export must target the playlist at the given index")
    }

    func testWriteExport_PlaylistAt_OutOfRange_WritesNothing() throws {
        let f = makeSUT()
        let destination = try makeTempDir().appendingPathComponent("out.m3u8")

        try f.sut.writeExport(playlistAt: 99, to: destination, pathStyle: .absolute)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                       "an out-of-range index must write no file")
    }
}
