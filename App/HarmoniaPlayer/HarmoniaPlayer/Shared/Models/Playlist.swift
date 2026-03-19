//
//  Playlist.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-20.
//
//  Slice 2-B: Playlist Model
//

import Foundation

/// Playlist model
///
/// Represents an ordered collection of tracks.
///
/// **Design constraints (Slice 2-B):**
/// - Pure value type (no HarmoniaCore dependency)
/// - Mutable name and tracks, immutable ID
/// - No side effects
///
/// **Usage:**
/// ```swift
/// var playlist = Playlist(name: "Session")
/// playlist.tracks.append(track)
/// ```
/// Column by which the playlist is currently sorted.
///
/// `.none` means insertion order (the natural `tracks` array order).
/// Stored in `Playlist` so each playlist can have its own independent
/// sort state, and so the state survives playlist switching and can be
/// persisted with the playlist in a future save/load implementation.
enum PlaylistSortKey: String, Equatable, Sendable {
    case none       // insertion order
    case title
    case artist
    case duration
}

struct Playlist: Identifiable, Equatable, Sendable {

    // MARK: - Identity

    /// Unique identifier (immutable after creation)
    let id: UUID

    // MARK: - Mutable State

    /// Display name of the playlist
    var name: String

    /// Ordered list of tracks
    var tracks: [Track]

    /// Current sort column. `.none` = insertion order.
    var sortKey: PlaylistSortKey = .none

    /// Sort direction. `true` = ascending, `false` = descending.
    var sortAscending: Bool = true

    /// Original insertion order (track IDs). Populated by AppState when
    /// tracks are added; used to restore insertion order when sortKey == .none.
    var insertionOrder: [Track.ID] = []

    // MARK: - Computed Properties

    /// Whether the playlist contains no tracks
    var isEmpty: Bool { tracks.isEmpty }

    /// Number of tracks in the playlist
    var count: Int { tracks.count }

    // MARK: - Initialization

    /// Initialize with all fields
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates new UUID if not provided)
    ///   - name: Display name (defaults to "Playlist")
    ///   - tracks: Initial track list (defaults to empty)
    init(
        id: UUID = UUID(),
        name: String = "Playlist",
        tracks: [Track] = [],
        sortKey: PlaylistSortKey = .none,
        sortAscending: Bool = true
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.sortKey = sortKey
        self.sortAscending = sortAscending
        self.insertionOrder = tracks.map { $0.id }
    }
    
    // MARK: - Equatable
    // Explicit nonisolated == required for Swift 6 / Xcode 26 beta.
    // Without this, the synthesized conformance may be inferred as
    // @MainActor isolated, causing errors in nonisolated contexts.
    nonisolated static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.tracks == rhs.tracks &&
        lhs.sortKey == rhs.sortKey &&
        lhs.sortAscending == rhs.sortAscending
    }
}
