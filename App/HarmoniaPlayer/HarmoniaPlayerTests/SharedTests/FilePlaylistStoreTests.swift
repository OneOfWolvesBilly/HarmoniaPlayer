//
//  FilePlaylistStoreTests.swift
//  HarmoniaPlayerTests
//

import XCTest
@testable import Harmonia_Player

/// Unit tests for `FilePlaylistStore` (Slice 9-W Part B).
///
/// Validates that the file-backed store round-trips playlists, reports an
/// absent file as `nil`, and surfaces a corrupt file as a thrown error.
@MainActor
final class FilePlaylistStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilePlaylistStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Tests

    /// W6: save → load round-trips a `[Playlist]`.
    func testFilePlaylistStore_SaveLoad_RoundTrips() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FilePlaylistStore(directory: dir)

        let track = Track(url: URL(fileURLWithPath: "/tmp/a.mp3"), title: "A")
        let playlists = [Playlist(name: "P1", tracks: [track])]

        try store.save(playlists)
        let loaded = try store.load()

        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.first?.name, "P1")
        XCTAssertEqual(loaded?.first?.tracks.first?.title, "A")
    }

    /// W7a: load returns nil when no file exists.
    func testFilePlaylistStore_Load_NilWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FilePlaylistStore(directory: dir)

        XCTAssertNil(try store.load())
    }

    /// W7b: load throws on a corrupt file.
    func testFilePlaylistStore_Load_ThrowsOnCorruptFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not json".utf8).write(to: dir.appendingPathComponent("playlists.json"))
        let store = FilePlaylistStore(directory: dir)

        XCTAssertThrowsError(try store.load())
    }
}
