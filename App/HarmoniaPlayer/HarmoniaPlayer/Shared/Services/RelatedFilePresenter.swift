//
//  RelatedFilePresenter.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  THROWAWAY — Slice 9-M baseline experiment only.
//  Delete this entire file before committing 9-M implementation.
//
//  PURPOSE
//  -------
//  Minimal `NSFilePresenter` conformance used by the 9-M experiment block in
//  `LyricsService.swift` to probe Apple's "Related Items" sandbox mechanism.
//
//  USAGE
//  -----
//  Construct with a primary item URL (the user-selected audio file) and a
//  presented item URL (the sibling `.lrc` candidate). Register with
//  `NSFileCoordinator.addFilePresenter` immediately before issuing a
//  coordinated read; deregister immediately after.
//
//  IMPORTANT — INFO.PLIST DEPENDENCY
//  ---------------------------------
//  This class alone does NOT grant sibling-read access. The target's
//  `CFBundleDocumentTypes` must declare an entry with:
//    - `CFBundleTypeExtensions = [ "lrc" ]`
//    - `CFBundleTypeRole = Editor`     (NOT None or Viewer — confirmed via
//                                       Apple Developer Forum thread 14718)
//    - `NSIsRelatedItemType = YES`
//  Configure these in Xcode → target → Info → Document Types.
//

import Foundation

/// THROWAWAY — Minimal `NSFilePresenter` for the 9-M Related Items probe.
final class RelatedFilePresenter: NSObject, NSFilePresenter {

    /// The user-chosen primary item (e.g. the `.mp3` URL).
    var primaryPresentedItemURL: URL?

    /// The sibling URL whose access we are probing (e.g. `<name>.lrc`).
    var presentedItemURL: URL?

    /// Operation queue on which `NSFileCoordinator` will deliver delegate
    /// callbacks. `.main` is sufficient for a one-shot probe.
    var presentedItemOperationQueue: OperationQueue = .main

    init(primaryItemURL: URL, presentedItemURL: URL) {
        self.primaryPresentedItemURL = primaryItemURL
        self.presentedItemURL = presentedItemURL
        super.init()
    }
}
