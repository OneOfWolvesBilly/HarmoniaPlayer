//
//  AudioFileItem.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Transferable wrapper for an audio file URL received via drag-and-drop.
//
//  DESIGN NOTES
//  ------------
//  - Conforms to Transferable (CoreTransferable, macOS 13+) so PlaylistView
//    can use .dropDestination(for: AudioFileItem.self) for Finder drags.
//  - Uses ProxyRepresentation with both import and export via URL.
//    This preserves the original file path — FileRepresentation must NOT be
//    used for importing because received.file is a temporary copy that is
//    deleted after the callback, causing playback to fail with file-not-found.
//  - The ProxyRepresentation export path also serves as the workaround for
//    macOS 13/14 where FileRepresentation alone is not accepted by Finder.
//    (Apple Feedback: FB13454434)
//  - This type lives in the Model layer; it has no UI dependencies.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// A drag-and-drop transferable wrapper for a local audio file URL.
struct AudioFileItem: Transferable {

    /// The file URL of the audio file.
    let url: URL

    // MARK: - Transferable

    static var transferRepresentation: some TransferRepresentation {
        // ProxyRepresentation bridges through URL (which is already Transferable).
        // Import: Finder provides the original file URL — no file copying occurs.
        // Export: exposes the URL so receiving apps (including Finder) can resolve
        //         the file path without needing a FileRepresentation.
        ProxyRepresentation(
            exporting: { $0.url },
            importing: { AudioFileItem(url: $0) }
        )
    }
}
