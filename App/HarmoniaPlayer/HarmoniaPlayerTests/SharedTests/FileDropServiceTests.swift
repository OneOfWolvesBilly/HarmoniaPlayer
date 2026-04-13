//
//  FileDropServiceTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for FileDropService: audio file validation and directory expansion.
//

import XCTest
@testable import HarmoniaPlayer

final class FileDropServiceTests: XCTestCase {

    private var sut: FileDropService!
    private var tempDir: URL?

    override func setUp() {
        super.setUp()
        sut = FileDropService()
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a temp directory with the given file structure and returns its URL.
    private func makeTempDir(files: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        for name in files {
            let fileURL = dir.appendingPathComponent(name)
            // Create intermediate directories if needed (e.g. "sub/track.mp3")
            let parent = fileURL.deletingLastPathComponent()
            if parent != dir {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        return dir
    }

    // MARK: - Individual file validation

    func testValidate_AudioFile_Accepted() throws {
        let dir = try makeTempDir(files: ["track.mp3"])
        let fileURL = dir.appendingPathComponent("track.mp3")

        let result = sut.validate([fileURL])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, fileURL)
    }

    func testValidate_NonAudioFile_Rejected() throws {
        let dir = try makeTempDir(files: ["readme.txt"])
        let fileURL = dir.appendingPathComponent("readme.txt")

        let result = sut.validate([fileURL])

        XCTAssertTrue(result.isEmpty,
                      "Non-audio file must be filtered out")
    }

    // MARK: - Directory expansion

    func testValidate_Directory_ExpandsAudioFiles() throws {
        let dir = try makeTempDir(files: ["a.mp3", "b.flac", "c.wav"])

        let result = sut.validate([dir])

        XCTAssertEqual(result.count, 3,
                       "All audio files in directory must be expanded")
    }

    func testValidate_Directory_SkipsNonAudioFiles() throws {
        let dir = try makeTempDir(files: ["track.mp3", "cover.jpg", "notes.txt"])

        let result = sut.validate([dir])

        XCTAssertEqual(result.count, 1,
                       "Only audio files must be included from directory")
        XCTAssertEqual(result.first?.lastPathComponent, "track.mp3")
    }

    func testValidate_NestedDirectory_ExpandsRecursively() throws {
        let dir = try makeTempDir(files: [
            "disc1/01.mp3",
            "disc1/02.mp3",
            "disc2/01.flac"
        ])

        let result = sut.validate([dir])

        XCTAssertEqual(result.count, 3,
                       "Audio files in nested subdirectories must be expanded recursively")
    }

    func testValidate_EmptyDirectory_ReturnsEmpty() throws {
        let dir = try makeTempDir(files: [])

        let result = sut.validate([dir])

        XCTAssertTrue(result.isEmpty)
    }

    func testValidate_MixedFilesAndDirectory_AllExpanded() throws {
        let dir = try makeTempDir(files: [
            "album/track1.mp3",
            "album/track2.mp3"
        ])
        let singleFile = dir.appendingPathComponent("album/track1.mp3")
        let albumDir = dir.appendingPathComponent("album")

        // Pass both a single file and a directory
        let result = sut.validate([singleFile, albumDir])

        // singleFile contributes 1, albumDir contributes 2 (including track1 again)
        XCTAssertEqual(result.count, 3,
                       "Both individual files and directory contents must be included")
    }
}
