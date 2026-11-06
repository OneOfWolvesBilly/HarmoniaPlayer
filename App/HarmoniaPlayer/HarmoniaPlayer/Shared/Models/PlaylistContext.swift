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
/// `AppState` conforms today; the playlist store conforms once the
/// playlist state moves out of `AppState`.
@MainActor
protocol PlaylistContext: AnyObject {
    var playlists: [Playlist] { get set }
    var activePlaylistIndex: Int { get set }
    var selectedTrackIDs: Set<Track.ID> { get }
}

extension AppState: PlaylistContext {}
