//
//  SiblingFilePresenter.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// Minimal `NSFilePresenter` conformance for reading a sibling file (same
/// base name, different extension) of a user-selected primary file under
/// the App Sandbox.
///
/// ## Usage
///
/// Used together with `NSFileCoordinator.coordinate(readingItemAt:)`
/// after registering with `NSFileCoordinator.addFilePresenter(_:)`. The
/// register / deregister pair must be tightly scoped (typically via
/// `defer`) around the coordinated read.
///
/// ## Info.plist requirement
///
/// The sibling extension MUST be declared in the app bundle's
/// `CFBundleDocumentTypes` with:
///
/// - `CFBundleTypeExtensions = [ "<ext>" ]`
/// - `CFBundleTypeRole = Editor` — required; `None` and `Viewer` cause
///   `addFilePresenter` to silently fail without diagnostic output (per
///   Apple Developer Forum thread 14718).
/// - `NSIsRelatedItemType = YES`
///
/// Without this declaration the App Sandbox refuses to issue a
/// related-item extension and the coordinated read fails with
/// `NSCocoaErrorDomain Code=257`.
///
/// ## Lifecycle
///
/// `presentedItemOperationQueue` is `.main`; sibling reads in this app
/// are small (typical `.lrc` < 16 KB) and the call sites are already on
/// the main actor, so a separate queue is unnecessary.
final class SiblingFilePresenter: NSObject, NSFilePresenter {

    /// The user-chosen primary item (e.g. the `.mp3` URL).
    var primaryPresentedItemURL: URL?

    /// The sibling URL whose access is being coordinated (e.g.
    /// `<basename>.lrc`).
    var presentedItemURL: URL?

    /// Operation queue on which `NSFileCoordinator` delivers delegate
    /// callbacks. `.main` is appropriate for the small file sizes
    /// expected for sibling reads.
    var presentedItemOperationQueue: OperationQueue = .main

    init(primaryItemURL: URL, presentedItemURL: URL) {
        self.primaryPresentedItemURL = primaryItemURL
        self.presentedItemURL = presentedItemURL
        super.init()
    }
}
