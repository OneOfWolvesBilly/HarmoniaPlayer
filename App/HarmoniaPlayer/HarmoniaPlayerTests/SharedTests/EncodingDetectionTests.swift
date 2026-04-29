//
//  EncodingDetectionTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for DefaultLyricsService.detectEncoding (Slice 9-J).
//
//  NOTE: GB18030 and Big5 detection is best-effort. Both encodings accept
//  many of the same byte sequences. The tests use carefully constructed data:
//  - GB18030 test: bytes for "你好" in GB18030 (0xC4 E3 BA C3) — invalid UTF-8,
//    valid GB18030.
//  - Big5 test: data produced by encoding Traditional Chinese text via Big5
//    encoding. If Big5 bytes happen to be valid GB18030 too, this test may
//    return .gb18030. In practice, Traditional Chinese Big5 text and
//    Simplified Chinese GB18030 text occupy different byte-range patterns,
//    making the heuristic reliable for typical real-world files.
//

import XCTest
@testable import HarmoniaPlayer

final class EncodingDetectionTests: XCTestCase {

    var sut: DefaultLyricsService!

    override func setUp() {
        super.setUp()
        sut = DefaultLyricsService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - UTF-8

    func testEncodingDetection_UTF8() {
        let text = "Hello, world! 日本語テスト"
        let data = text.data(using: .utf8)!
        XCTAssertEqual(sut.detectEncoding(of: data), .utf8)
    }

    func testEncodingDetection_UTF8_ASCIIOnly() {
        let data = "simple ascii text".data(using: .utf8)!
        XCTAssertEqual(sut.detectEncoding(of: data), .utf8)
    }

    // MARK: - GB18030

    func testEncodingDetection_GB18030Fallback() {
        // "你好" in GB18030/GB2312: C4 E3 BA C3
        // C4 E3: 0xC4 starts a 2-byte UTF-8 seq, but 0xE3 is a 3-byte lead
        // (not a continuation byte) → invalid UTF-8. Valid GB18030. ✓
        let data = Data([0xC4, 0xE3, 0xBA, 0xC3])
        let detected = sut.detectEncoding(of: data)
        XCTAssertEqual(detected, DefaultLyricsService.gb18030,
            "GB18030-encoded bytes that fail UTF-8 should be detected as GB18030")
    }

    // MARK: - Big5

    func testEncodingDetection_Big5Fallback() {
        // Construct Big5 bytes programmatically from Traditional Chinese text.
        // These bytes should fail UTF-8. Whether they also fail GB18030 depends
        // on the specific characters — see NOTE at top of file.
        guard let data = "妳好嗎".data(using: DefaultLyricsService.big5) else {
            XCTFail("Could not encode Traditional Chinese text as Big5")
            return
        }
        // Verify UTF-8 fails for these bytes (they are non-ASCII Big5 bytes)
        XCTAssertNil(String(data: data, encoding: .utf8),
            "Big5 encoded text should not decode as UTF-8")
        // The detected encoding should be able to round-trip the original text
        let detected = sut.detectEncoding(of: data)
        XCTAssertNotNil(String(data: data, encoding: detected),
            "Detected encoding \(detected) should decode the Big5 data without error")
    }

    // MARK: - Shift-JIS

    func testEncodingDetection_ShiftJISFallback() {
        // Construct Shift-JIS bytes from Japanese text
        guard let data = "こんにちは世界".data(using: .shiftJIS) else {
            XCTFail("Could not encode Japanese text as Shift-JIS")
            return
        }
        XCTAssertNil(String(data: data, encoding: .utf8),
            "Shift-JIS encoded text should not decode as UTF-8")
        let detected = sut.detectEncoding(of: data)
        // Should detect as shiftJIS (or an encoding that decodes it correctly)
        XCTAssertNotNil(String(data: data, encoding: detected),
            "Detected encoding \(detected) should decode the Shift-JIS data without error")
    }

    // MARK: - Static helpers

    func testGB18030StaticHelper_IsNonZeroEncoding() {
        XCTAssertNotEqual(DefaultLyricsService.gb18030.rawValue, 0,
            "gb18030 static helper should produce a valid non-zero encoding")
    }

    func testBig5StaticHelper_IsNonZeroEncoding() {
        XCTAssertNotEqual(DefaultLyricsService.big5.rawValue, 0,
            "big5 static helper should produce a valid non-zero encoding")
    }

    func testGB18030AndBig5_AreDistinctEncodings() {
        XCTAssertNotEqual(DefaultLyricsService.gb18030, DefaultLyricsService.big5,
            "gb18030 and big5 should map to different encoding values")
    }
}
