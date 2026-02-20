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
struct Playlist: Identifiable, Equatable {

    // MARK: - Identity

    /// Unique identifier (immutable after creation)
    let id: UUID

    // MARK: - Mutable State

    /// Display name of the playlist
    var name: String

    /// Ordered list of tracks
    var tracks: [Track]

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
        tracks: [Track] = []
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
    }
    
    // MARK: - Equatable
    // Explicit nonisolated == required for Swift 6 / Xcode 26 beta.
    // Without this, the synthesized conformance may be inferred as
    // @MainActor isolated, causing errors in nonisolated contexts.
    nonisolated static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.tracks == rhs.tracks
    }
}
