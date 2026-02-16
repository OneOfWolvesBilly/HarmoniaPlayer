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
    
    /// Initialize with minimal information
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates new UUID if not provided)
    ///   - url: File URL
    ///   - title: Track title (defaults to filename)
    ///   - artist: Artist name (defaults to empty)
    ///   - album: Album name (defaults to empty)
    ///   - duration: Track duration
    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        artist: String = "",
        album: String = "",
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}
