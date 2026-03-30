//
//  FileDropService.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Validates URLs received from drag-and-drop before passing them to AppState.
//  Filters out non-file URLs and non-audio files by UTType conformance.
//
//  DESIGN NOTES
//  ------------
//  - Pure value type with no dependencies on AppState or UI.
//  - UTType conformance check handles all audio extensions (mp3, aac, alac,
//    wav, aiff, flac, etc.) without maintaining an explicit allowlist.
//  - No import HarmoniaCore.
//

import Foundation
import UniformTypeIdentifiers

/// Service that validates and filters URLs received from drag-and-drop.
struct FileDropService {

    // MARK: - Public API

    /// Returns only valid, local audio file URLs from the given array.
    ///
    /// A URL is considered valid if:
    /// - It is a file URL (`isFileURL == true`)
    /// - Its path extension maps to a UTType that conforms to `.audio`
    func validate(_ urls: [URL]) -> [URL] {
        urls.filter { isLocalAudioFile($0) }
    }

    // MARK: - Private Helpers

    /// Returns true if `url` points to a local audio file.
    private func isLocalAudioFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio)
    }
}
