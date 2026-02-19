//
//  Track.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Audio track model
///
/// Represents a single audio file in the playlist.
///
/// **Note:** This is a minimal version for Slice 1 (Foundation).
/// Full metadata support will be added in later slices.
struct Track: Identifiable, Equatable {
    
    /// Unique identifier
    let id: UUID
    
    /// File URL
    let url: URL
    
    /// Track title (defaults to filename)
    var title: String
    
    /// Artist name (optional)
    var artist: String
    
    /// Album name (optional)
    var album: String
    
    /// Track duration in seconds (optional)
    var duration: TimeInterval?

    /// URL to album artwork (optional, future use)
    var artworkURL: URL?
    
    /// Initialize with all fields
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates new UUID if not provided)
    ///   - url: File URL
    ///   - title: Track title
    ///   - artist: Artist name (defaults to empty)
    ///   - album: Album name (defaults to empty)
    ///   - duration: Track duration
    ///   - artworkURL: Artwork URL (defaults to nil)
    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
    }

    /// Convenience initializer that derives title from URL filename
    ///
    /// - Parameter url: File URL
    init(url: URL) {
        self.init(
            url: url,
            title: url.deletingPathExtension().lastPathComponent
        )
    }
    
    nonisolated static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.duration == rhs.duration &&
        lhs.artworkURL == rhs.artworkURL
    }

}
