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
//  Recursively expands directories into their contained audio files.
//
//  DESIGN NOTES
//  ------------
//  - Pure value type with no dependencies on AppState or UI.
//  - UTType conformance check handles all audio extensions (mp3, aac, alac,
//    wav, aiff, flac, etc.) without maintaining an explicit allowlist.
//  - Directories are recursively expanded; non-audio files inside are skipped.
//  - No import HarmoniaCore.
//

import Foundation
import UniformTypeIdentifiers

/// Service that validates and filters URLs received from drag-and-drop.
struct FileDropService {

    // MARK: - Public API

    /// Returns valid, local audio file URLs from the given array.
    ///
    /// Directories are recursively expanded into their contained audio files.
    /// Non-file URLs and non-audio files are filtered out.
    ///
    /// A URL is included if:
    /// - It is a file URL (`isFileURL == true`)
    /// - It is an audio file (UTType conforms to `.audio`), OR
    /// - It is a directory containing audio files (recursively expanded)
    func validate(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            guard url.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                continue
            }
            if isDir.boolValue {
                result.append(contentsOf: audioFilesInDirectory(url))
            } else if isAudioFile(url) {
                result.append(url)
            }
        }
        return result
    }

    // MARK: - Private Helpers

    /// Returns true if `url` points to an audio file based on UTType.
    private func isAudioFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio)
    }

    /// Recursively enumerates all audio files within a directory.
    ///
    /// Files are returned in alphabetical order per directory level
    /// (natural FileManager enumeration order).
    private func audioFilesInDirectory(_ directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if isAudioFile(fileURL) {
                files.append(fileURL)
            }
        }
        return files
    }
}
