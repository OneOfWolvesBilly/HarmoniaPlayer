//
//  ExtendedAttributeServiceTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for ExtendedAttributeService — Darwin xattr read/write/clear
//  for the kMDItemWhereFroms extended attribute.
//
//  Test strategy:
//  - Each test creates a temporary file in the system temp directory.
//  - The temp file is cleaned up in tearDown regardless of test outcome.
//  - No App Sandbox on macOS, so direct xattr calls are permitted.
//

import XCTest
@testable import HarmoniaPlayer

final class ExtendedAttributeServiceTests: XCTestCase {

    // MARK: - Setup / Teardown

    private var tempFileURL: URL!
    private let sut = ExtendedAttributeService()

    override func setUp() {
        super.setUp()
        // Create a temporary empty file for xattr manipulation
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

    // MARK: - Tests

    /// Reading WhereFroms on a file that already has the attribute
    /// must return the stored URL strings unchanged.
    func testReadWhereFroms_WhenPresent_ReturnsURLs() throws {
        let expected = ["https://example.com/song.flac", "https://bandcamp.com/track/1"]
        try sut.writeWhereFroms(expected, url: tempFileURL)

        let result = sut.readWhereFroms(url: tempFileURL)

        XCTAssertEqual(result, expected,
            "readWhereFroms should return the exact array that was written")
    }

    /// Reading WhereFroms on a file with no extended attribute
    /// must return an empty array (not throw, not crash).
    func testReadWhereFroms_WhenAbsent_ReturnsEmpty() {
        let result = sut.readWhereFroms(url: tempFileURL)

        XCTAssertTrue(result.isEmpty,
            "readWhereFroms should return [] when the attribute is absent")
    }

    /// Writing WhereFroms and reading back must produce identical values,
    /// confirming data round-trips through plist serialization correctly.
    func testWriteWhereFroms_PersistsValue() throws {
        let sources = ["https://store.example.com/purchase/42"]
        try sut.writeWhereFroms(sources, url: tempFileURL)

        let readBack = sut.readWhereFroms(url: tempFileURL)

        XCTAssertEqual(readBack, sources,
            "writeWhereFroms should persist values readable by readWhereFroms")
    }

    /// After clearWhereFroms, readWhereFroms must return an empty array.
    func testClearWhereFroms_RemovesAttribute() throws {
        try sut.writeWhereFroms(["https://example.com"], url: tempFileURL)

        try sut.clearWhereFroms(url: tempFileURL)
        let result = sut.readWhereFroms(url: tempFileURL)

        XCTAssertTrue(result.isEmpty,
            "clearWhereFroms should remove the attribute so readWhereFroms returns []")
    }

    /// Calling clearWhereFroms on a file that has no attribute
    /// must not throw — it is a no-op.
    func testClearWhereFroms_WhenAbsent_DoesNotThrow() {
        XCTAssertNoThrow(
            try sut.clearWhereFroms(url: tempFileURL),
            "clearWhereFroms on a file without the attribute must not throw"
        )
    }
}
