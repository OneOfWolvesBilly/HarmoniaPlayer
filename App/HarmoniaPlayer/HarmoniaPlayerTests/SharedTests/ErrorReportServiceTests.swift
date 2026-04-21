//
//  ErrorReportServiceTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  Tests for ErrorReportService: mailto URL construction and encoding.
//

import XCTest
@testable import HarmoniaPlayer

final class ErrorReportServiceTests: XCTestCase {

    // MARK: - Fixtures

    private let sampleDetail = "failedToDecode: /Users/test/song.mp3"
    private let sampleAppVersion = "0.1.0"
    private let sampleOSVersion = "Version 15.6 (Build 24G84)"

    // MARK: - Tests

    /// Given a detail and runtime versions, the built URL must:
    /// - have scheme `mailto`
    /// - have path equal to `ErrorReportService.reportEmail`
    /// - include `subject` query item equal to `ErrorReportService.subjectLine`
    /// - include a `body` query item whose value contains the detail,
    ///   the app version string, and the OS version string
    func testErrorReportService_BuildMailtoURL_ContainsToSubjectBody() throws {
        let url = ErrorReportService.buildMailtoURL(
            detail: sampleDetail,
            appVersion: sampleAppVersion,
            osVersion: sampleOSVersion
        )

        let unwrappedURL = try XCTUnwrap(url, "buildMailtoURL must return a non-nil URL for valid inputs")

        XCTAssertEqual(unwrappedURL.scheme, "mailto", "URL scheme must be mailto")

        // In `mailto:<address>?...`, `path` is the address portion.
        XCTAssertEqual(
            unwrappedURL.path,
            ErrorReportService.reportEmail,
            "URL path must equal the report email"
        )

        let components = try XCTUnwrap(
            URLComponents(url: unwrappedURL, resolvingAgainstBaseURL: false),
            "URL must be parseable by URLComponents"
        )
        let queryItems = try XCTUnwrap(components.queryItems, "URL must have query items")

        let subject = queryItems.first { $0.name == "subject" }?.value
        XCTAssertEqual(
            subject,
            ErrorReportService.subjectLine,
            "subject query item must equal subjectLine"
        )

        let body = try XCTUnwrap(
            queryItems.first { $0.name == "body" }?.value,
            "body query item must be present"
        )
        XCTAssertTrue(
            body.contains(sampleDetail),
            "body must contain the detail string, was: \(body)"
        )
        XCTAssertTrue(
            body.contains(sampleAppVersion),
            "body must contain the app version, was: \(body)"
        )
        XCTAssertTrue(
            body.contains(sampleOSVersion),
            "body must contain the OS version, was: \(body)"
        )
    }

    /// Given a detail containing `&` and a newline character, the produced URL's
    /// `absoluteString` must percent-encode these as `%26` and `%0A` so Mail.app
    /// parses the mailto parameters correctly.
    func testErrorReportService_BuildMailtoURL_EncodesSpecialChars() throws {
        let trickyDetail = "failedToDecode: a & b\nsecond line"

        let url = ErrorReportService.buildMailtoURL(
            detail: trickyDetail,
            appVersion: sampleAppVersion,
            osVersion: sampleOSVersion
        )

        let unwrappedURL = try XCTUnwrap(url, "buildMailtoURL must return a non-nil URL for valid inputs")
        let absolute = unwrappedURL.absoluteString

        XCTAssertTrue(
            absolute.contains("%26"),
            "'&' must be percent-encoded as %26, got: \(absolute)"
        )
        XCTAssertTrue(
            absolute.contains("%0A"),
            "newline must be percent-encoded as %0A, got: \(absolute)"
        )
    }
}
