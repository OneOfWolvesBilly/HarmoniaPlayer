//
//  PlaylistContext.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// The playlist state the playback controller reads and writes: the
/// playlists it resolves tracks in, the index of the playlist the user is
/// looking at, and the current table selection.
///
/// `PlaylistCollection` conforms; the composition root passes it to
/// `PlaybackController.init`. Controller tests substitute an in-memory
/// double.
@MainActor
protocol PlaylistContext: AnyObject {
    var playlists: [Playlist] { get set }
    var activePlaylistIndex: Int { get set }
    var selectedTrackIDs: Set<Track.ID> { get }
}
