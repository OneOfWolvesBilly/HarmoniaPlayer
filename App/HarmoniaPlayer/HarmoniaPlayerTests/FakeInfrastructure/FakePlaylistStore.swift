//
//  FakePlaylistStore.swift
//  HarmoniaPlayerTests
//

import Foundation
@testable import Harmonia_Player

/// In-memory PlaylistStore for deterministic persistence tests.
///
/// Holds playlists in memory so that a save followed by a load round-trips
/// without touching the file system. A single instance is shared between a
/// save-side AppState and a restore-side AppState to simulate relaunch.
final class FakePlaylistStore: PlaylistStore {

    /// The currently stored playlists, or nil when nothing has been saved.
    var stored: [Playlist]?

    /// Number of times `save(_:)` has been called.
    private(set) var saveCallCount = 0

    /// When set, `load()` throws this instead of returning `stored`.
    var loadError: Error?

    init(stored: [Playlist]? = nil) {
        self.stored = stored
    }

    func save(_ playlists: [Playlist]) throws {
        saveCallCount += 1
        stored = playlists
    }

    func load() throws -> [Playlist]? {
        if let loadError { throw loadError }
        return stored
    }
}
