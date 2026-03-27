//
//  Playlist.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-20.
//

import Foundation

/// Column by which the playlist is currently sorted.
///
/// `.none` means insertion order (the natural `tracks` array order).
/// Stored in `Playlist` so each playlist can have its own independent
/// sort state, and persisted with the playlist.
enum PlaylistSortKey: String, Equatable, Sendable, Codable {
    case none           // insertion order
    // Core
    case title
    case artist
    case album
    case duration
    // Group A
    case albumArtist
    case composer
    case genre
    case year
    case trackNumber
    case discNumber
    case bpm
    // Group D
    case bitrate
    case sampleRate
    case channels
    case fileSize
    case fileFormat
}

struct Playlist: Identifiable, Equatable, Sendable, Codable {

    // MARK: - Identity

    let id: UUID

    // MARK: - Mutable State

    var name: String
    var tracks: [Track]

    /// Current sort column. `.none` = insertion order.
    var sortKey: PlaylistSortKey = .none

    /// Sort direction. `true` = ascending, `false` = descending.
    var sortAscending: Bool = true

    /// Original insertion order (track IDs). Populated by AppState when
    /// tracks are added; used to restore insertion order when sortKey == .none.
    var insertionOrder: [Track.ID] = []

    // MARK: - Computed Properties

    var isEmpty: Bool { tracks.isEmpty }
    var count: Int    { tracks.count }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String = "Playlist",
        tracks: [Track] = [],
        sortKey: PlaylistSortKey = .none,
        sortAscending: Bool = true
    ) {
        self.id           = id
        self.name         = name
        self.tracks       = tracks
        self.sortKey      = sortKey
        self.sortAscending = sortAscending
        self.insertionOrder = tracks.map { $0.id }
    }

    // MARK: - Equatable

    nonisolated static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id           == rhs.id &&
        lhs.name         == rhs.name &&
        lhs.tracks       == rhs.tracks &&
        lhs.sortKey      == rhs.sortKey &&
        lhs.sortAscending == rhs.sortAscending
    }
}
