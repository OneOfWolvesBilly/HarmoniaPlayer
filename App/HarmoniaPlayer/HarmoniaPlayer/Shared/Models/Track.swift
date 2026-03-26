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
struct Track: Identifiable, Equatable, Sendable, Codable {
    
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
    
    /// Track duration in seconds. Defaults to 0 if metadata is unavailable.
    var duration: TimeInterval

    /// Raw artwork image data read from file metadata (optional).
    var artworkData: Data?

    /// Whether the file is accessible at the stored URL.
    ///
    /// Set to `false` when bookmark resolution fails during restore.
    /// This is a runtime-only field — it is intentionally excluded from
    /// `CodingKeys` and never written to or read from persistent storage.
    /// Defaults to `true` for tracks created in the current session.
    var isAccessible: Bool = true

    /// The original POSIX path stored at encode time.
    ///
    /// Used by `AppState.restoreState()` to check whether the file still exists
    /// at its original location, independently of where the bookmark resolves to.
    /// Runtime-only — excluded from `CodingKeys`.
    var originalPath: String = ""

    
    /// Initialize with all fields
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates new UUID if not provided)
    ///   - url: File URL
    ///   - title: Track title
    ///   - artist: Artist name (defaults to empty)
    ///   - album: Album name (defaults to empty)
    ///   - duration: Track duration
    ///   - artworkData: Raw artwork image data (defaults to nil)
    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        artworkData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkData = artworkData
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

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, urlPath, title, artist, album, duration, artworkData
        case accessBookmark
        // Legacy key used before urlPath was introduced
        case legacyURL = "url"
    }

    /// Encodes `url` as a plain POSIX path string under `urlPath`.
    ///
    /// Also generates a macOS bookmark at encode time — while the OS-granted
    /// access to the file is still valid — so the URL can be resolved across
    /// app relaunches without requiring the user to re-select the file.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id,       forKey: .id)
        try container.encode(url.path, forKey: .urlPath)
        // Generate bookmark while we still have OS access to this file.
        // minimalBookmark produces a compact, non-security-scoped bookmark
        // suitable for non-sandboxed apps.
        if url.isFileURL,
           let bookmark = try? url.bookmarkData(
               options: .minimalBookmark,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            try container.encode(bookmark, forKey: .accessBookmark)
        }
        try container.encode(title,    forKey: .title)
        try container.encode(artist,   forKey: .artist)
        try container.encode(album,    forKey: .album)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(artworkData, forKey: .artworkData)
    }

    /// Decodes `url` by resolving from a stored bookmark when available.
    ///
    /// A resolved bookmark URL carries the OS-level access grant needed for
    /// AVFoundation to open protected directories (Desktop, Documents, etc.)
    /// after an app relaunch. Falls back to `urlPath` if bookmark resolution
    /// fails, and to the legacy `url` key for backward compatibility.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        // Resolve URL: bookmark → urlPath → legacy url key (in priority order)
        if let bookmark = try container.decodeIfPresent(Data.self, forKey: .accessBookmark) {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                url = resolved
                isAccessible = true
            } else if let path = try container.decodeIfPresent(String.self, forKey: .urlPath) {
                url = URL(fileURLWithPath: path)
                isAccessible = false
            } else {
                let legacy = try container.decode(URL.self, forKey: .legacyURL)
                url = URL(fileURLWithPath: legacy.path)
                isAccessible = false
            }
        } else if let path = try container.decodeIfPresent(String.self, forKey: .urlPath) {
            url = URL(fileURLWithPath: path)
            isAccessible = true
        } else {
            let legacy = try container.decode(URL.self, forKey: .legacyURL)
            url = URL(fileURLWithPath: legacy.path)
            isAccessible = true
        }

        // Store the original path so restoreState() can check fileExists
        // against the stored location, not the bookmark-resolved location.
        if let path = try container.decodeIfPresent(String.self, forKey: .urlPath) {
            originalPath = path
        } else if let legacy = try? container.decode(URL.self, forKey: .legacyURL) {
            originalPath = legacy.path
        } else {
            originalPath = url.path
        }

        title       = try container.decode(String.self,       forKey: .title)
        artist      = try container.decode(String.self,       forKey: .artist)
        album       = try container.decode(String.self,       forKey: .album)
        duration    = try container.decode(TimeInterval.self, forKey: .duration)
        artworkData = try container.decodeIfPresent(Data.self, forKey: .artworkData)
    }

    // MARK: - Equatable

    nonisolated static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.duration == rhs.duration &&
        lhs.artworkData == rhs.artworkData &&
        lhs.isAccessible == rhs.isAccessible
    }

}
