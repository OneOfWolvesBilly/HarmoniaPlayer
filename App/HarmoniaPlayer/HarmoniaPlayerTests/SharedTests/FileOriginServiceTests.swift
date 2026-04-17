//
//  FileOriginServiceTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for FileOriginService via DarwinFileOriginAdapter — exercises the
//  real xattr pipeline (ExtendedAttributeService) against temporary files.
//
//  Test strategy:
//  - Each test creates a temporary empty file in the system temp directory.
//  - The temp file is cleaned up in tearDown regardless of test outcome.
//  - No App Sandbox on macOS, so direct xattr calls are permitted.
//  - SUT is the real DarwinFileOriginAdapter; no mocking of xattr I/O.
//    FakeFileOriginService exists for AppState-level tests and is not used here.
//
//  Swift 6 note:
//  - XCTestCase is MainActor-isolated under Swift 6 strict concurrency.
//  - DarwinFileOriginAdapter is marked `nonisolated` on the class declaration
//    so its conformance to FileOriginService remains nonisolated and can be
//    used freely from both MainActor and nonisolated call sites.
//

import XCTest
@testable import HarmoniaPlayer

final class FileOriginServiceTests: XCTestCase {

    // MARK: - Setup / Teardown

    private var tempFileURL: URL!
    private let sut: FileOriginService = DarwinFileOriginAdapter()

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        tempFileURL = tmp
    }

    override func tearDown() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURL = nil
        super.tearDown()
    }

    // MARK: - read

    func testFileOriginRead_WhenPresent_ReturnsURLs() throws {
        // Given — xattr pre-populated via the raw utility
        let expected = ["https://example.com/song.mp3", "https://example.com/album"]
        try ExtendedAttributeService().writeWhereFroms(expected, url: tempFileURL)

        // When
        let result = sut.read(url: tempFileURL)

        // Then
        XCTAssertEqual(result, expected)
    }

    func testFileOriginRead_WhenAbsent_ReturnsEmpty() {
        // Given — freshly created temp file with no xattr

        // When
        let result = sut.read(url: tempFileURL)

        // Then
        XCTAssertEqual(result, [])
    }

    // MARK: - write

    func testFileOriginWrite_PersistsValue() throws {
        // Given
        let sources = ["https://example.com/track.flac"]

        // When
        try sut.write(sources, url: tempFileURL)

        // Then — round-trip through read confirms persistence
        let roundTripped = sut.read(url: tempFileURL)
        XCTAssertEqual(roundTripped, sources)
    }

    // MARK: - clear

    func testFileOriginClear_RemovesAttribute() throws {
        // Given
        try sut.write(["https://example.com"], url: tempFileURL)
        XCTAssertEqual(sut.read(url: tempFileURL).count, 1)

        // When
        try sut.clear(url: tempFileURL)

        // Then
        XCTAssertEqual(sut.read(url: tempFileURL), [])
    }

    func testFileOriginClear_WhenAbsent_DoesNotThrow() {
        // Given — freshly created temp file with no xattr

        // When / Then — ENOATTR must be treated as a no-op
        XCTAssertNoThrow(try sut.clear(url: tempFileURL))
    }
}
