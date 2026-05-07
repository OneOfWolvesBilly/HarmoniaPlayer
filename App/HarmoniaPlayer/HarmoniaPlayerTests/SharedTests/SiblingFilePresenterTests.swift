//
//  SiblingFilePresenterTests.swift
//  HarmoniaPlayerTests / SharedTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for `SiblingFilePresenter`.
///
/// Trivial-init contract tests: the class is a pure data carrier for
/// `NSFilePresenter` conformance, with no behavioural callbacks. These
/// tests verify the constructor stores both URLs in the correct properties
/// and that the operation queue defaults to `.main` (the expected setting
/// for the small sibling-file sizes this app uses).
///
/// The actual sibling-read behaviour is tested via the LyricsService
/// integration test (`testLyricsService_LrcRead_UsesNSFileCoordinator`)
/// and verified end-to-end via manual QA per spec §Layer 1.
final class SiblingFilePresenterTests: XCTestCase {

    // MARK: - Slice 9-M Layer 1: SiblingFilePresenter contract

    /// 9-M green-phase contract test.
    /// Verifies that constructor stores both URLs in the correct
    /// properties.
    func testSiblingFilePresenter_StoresURLPair() {
        let primaryURL = URL(fileURLWithPath: "/tmp/test/song.mp3")
        let presentedURL = URL(fileURLWithPath: "/tmp/test/song.lrc")

        let presenter = SiblingFilePresenter(
            primaryItemURL: primaryURL,
            presentedItemURL: presentedURL
        )

        XCTAssertEqual(presenter.primaryPresentedItemURL, primaryURL,
            "primaryPresentedItemURL must equal the primary URL passed "
            + "to init.")
        XCTAssertEqual(presenter.presentedItemURL, presentedURL,
            "presentedItemURL must equal the sibling URL passed to init.")
    }

    /// 9-M green-phase contract test.
    /// Verifies that `presentedItemOperationQueue` defaults to `.main`.
    /// The class deliberately does not expose an init parameter for this
    /// — the small file sizes expected (typical `.lrc` < 16 KB) and the
    /// main-actor call sites do not warrant a separate queue.
    func testSiblingFilePresenter_QueueIsMain() {
        let presenter = SiblingFilePresenter(
            primaryItemURL: URL(fileURLWithPath: "/tmp/a"),
            presentedItemURL: URL(fileURLWithPath: "/tmp/b")
        )

        XCTAssertEqual(presenter.presentedItemOperationQueue, .main,
            "presentedItemOperationQueue must default to .main per "
            + "design rationale documented in SiblingFilePresenter.swift.")
    }
}
