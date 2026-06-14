//
//  PlaylistReorderItem.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Transferable wrapper carrying the ID of a single track being dragged to
//  reorder the playlist Table.
//
//  DESIGN NOTES
//  ------------
//  - Conforms to Transferable (CoreTransferable, macOS 13+) by transferring the
//    track ID as plain text (a UUID string) via ProxyRepresentation. Plain text
//    is a system-known content type, so no custom UTType declaration / Info.plist
//    registration is required. (A custom exported UTType was tried first but a
//    GENERATE_INFOPLIST_FILE target could not instantiate it at drop time —
//    "Failed to instantiate a content type from NSPasteboardType(...)".)
//  - Distinctness from AudioFileItem: AudioFileItem transfers a file URL, this
//    transfers text, so a Finder file drop (file URL) routes to the table-level
//    AudioFileItem destination while an in-app row drag (text) routes here.
//  - A foreign text drop carrying a non-UUID string yields an id that matches no
//    track; AppState.moveTrack(id:before:) treats an unknown id as a no-op, so
//    such drops are harmless.
//  - This type lives in the Model layer; it has no UI dependencies.
//

import Foundation
import CoreTransferable

/// A drag-and-drop transferable wrapper for the ID of a track being reordered.
struct PlaylistReorderItem: Transferable {

    /// The ID of the dragged track.
    let id: Track.ID

    // MARK: - Transferable

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (item: PlaylistReorderItem) in item.id.uuidString },
            importing: { (string: String) in
                PlaylistReorderItem(id: UUID(uuidString: string) ?? UUID())
            }
        )
    }
}
