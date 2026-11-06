//
//  FakePlaylistContext.swift
//  HarmoniaPlayerTests / FakeInfrastructure
//
//  SPDX-License-Identifier: MIT
//

import Foundation
@testable import Harmonia_Player

/// In-memory `PlaylistContext` for `PlaybackController` tests.
///
/// Starts with one empty playlist at index 0 and no selection; tests seed
/// `playlists[0].tracks` directly instead of going through `load(urls:)`.
@MainActor
final class FakePlaylistContext: PlaylistContext {
    var playlists: [Playlist] = [Playlist(name: "Playlist 1")]
    var activePlaylistIndex: Int = 0
    var selectedTrackIDs = Set<Track.ID>()

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    nonisolated deinit {}
}
