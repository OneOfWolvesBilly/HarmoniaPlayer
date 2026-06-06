//
//  PlaylistStore.swift
//  HarmoniaPlayer / Shared / Services
//

import Foundation

/// Persists the playlist collection outside UserDefaults.
///
/// Playlists are too large for the UserDefaults single-value limit once a
/// library grows, so they are stored on disk instead. The store handles only
/// serialisation and file access; the application layer owns the in-memory
/// playlists and decides when to save or load.
protocol PlaylistStore {
    /// Writes the playlist collection to durable storage, overwriting any
    /// previous contents.
    func save(_ playlists: [Playlist]) throws

    /// Reads the playlist collection. Returns `nil` when nothing has been
    /// stored yet; throws when stored data exists but cannot be decoded.
    func load() throws -> [Playlist]?
}

/// Stores playlists as a single JSON file in the app's Application Support
/// directory (the sandbox container), which has no per-value size limit.
struct FilePlaylistStore: PlaylistStore {

    private let fileURL: URL

    /// - Parameter directory: Override the storage directory (used by tests).
    ///   Defaults to the user-domain Application Support directory.
    init(directory: URL? = nil) {
        let dir = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent("playlists.json")
    }

    func save(_ playlists: [Playlist]) throws {
        let data = try JSONEncoder().encode(playlists)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() throws -> [Playlist]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Playlist].self, from: data)
    }
}
