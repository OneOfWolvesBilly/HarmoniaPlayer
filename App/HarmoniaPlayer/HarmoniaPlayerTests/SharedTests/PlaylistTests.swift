//
//  PlaylistTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-20.
//
//  Slice 2-B: Playlist Model
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for Playlist model
///
/// Validates that Playlist correctly:
/// - Conforms to Identifiable with unique IDs
/// - Conforms to Equatable by value
/// - Stores and mutates fields correctly
/// - Computes isEmpty and count correctly
///
/// **Design constraints (Slice 2-B):**
/// - No HarmoniaCore dependency
/// - No UIKit / AppKit dependency
/// - Pure value type tests
final class PlaylistTests: XCTestCase {

    // MARK: - Helpers

    private let trackA = Track(url: URL(fileURLWithPath: "/Music/a.mp3"), title: "Track A")
    private let trackB = Track(url: URL(fileURLWithPath: "/Music/b.mp3"), title: "Track B")
    private let trackC = Track(url: URL(fileURLWithPath: "/Music/c.mp3"), title: "Track C")

    // MARK: - Tests: Identifiable

    func testPlaylist_HasUniqueID() {
        // Given: Two separate Playlist instances
        let playlist1 = Playlist()
        let playlist2 = Playlist()

        // Then: Each instance receives its own UUID
        XCTAssertNotEqual(playlist1.id, playlist2.id,
                          "Two Playlist instances must have different IDs")
    }

    func testPlaylist_IDIsStable() {
        // Given: A playlist
        let playlist = Playlist()
        let capturedID = playlist.id

        // Then: ID does not change across accesses
        XCTAssertEqual(playlist.id, capturedID,
                       "Playlist ID must be stable after creation")
    }

    // MARK: - Tests: Equatable

    func testPlaylist_Equatable_SameFields_AreEqual() {
        // Given: Two playlists sharing the same explicit ID and fields
        let sharedID = UUID()
        let tracks = [trackA, trackB]
        let playlist1 = Playlist(id: sharedID, name: "My List", tracks: tracks)
        let playlist2 = Playlist(id: sharedID, name: "My List", tracks: tracks)

        // Then: They are equal
        XCTAssertEqual(playlist1, playlist2,
                       "Playlists with identical fields must be equal")
    }

    func testPlaylist_Equatable_DifferentID_AreNotEqual() {
        // Given: Two playlists with same content but different IDs
        let playlist1 = Playlist(name: "Same Name", tracks: [trackA])
        let playlist2 = Playlist(name: "Same Name", tracks: [trackA])

        // Then: Different IDs → not equal
        XCTAssertNotEqual(playlist1, playlist2,
                          "Playlists with different IDs must not be equal")
    }

    func testPlaylist_Equatable_DifferentName_AreNotEqual() {
        // Given: Same ID, different names
        let sharedID = UUID()
        let playlist1 = Playlist(id: sharedID, name: "Name A", tracks: [])
        let playlist2 = Playlist(id: sharedID, name: "Name B", tracks: [])

        // Then: Not equal
        XCTAssertNotEqual(playlist1, playlist2,
                          "Playlists with different names must not be equal")
    }

    func testPlaylist_Equatable_DifferentTracks_AreNotEqual() {
        // Given: Same ID and name, different tracks
        let sharedID = UUID()
        let playlist1 = Playlist(id: sharedID, name: "List", tracks: [trackA])
        let playlist2 = Playlist(id: sharedID, name: "List", tracks: [trackB])

        // Then: Not equal
        XCTAssertNotEqual(playlist1, playlist2,
                          "Playlists with different tracks must not be equal")
    }

    // MARK: - Tests: isEmpty

    func testPlaylist_IsEmpty_WhenNoTracks() {
        // Given: Empty playlist
        let playlist = Playlist()

        // Then
        XCTAssertTrue(playlist.isEmpty,
                      "Playlist with no tracks must report isEmpty = true")
    }

    func testPlaylist_IsNotEmpty_WhenHasTrack() {
        // Given: Playlist with one track
        let playlist = Playlist(tracks: [trackA])

        // Then
        XCTAssertFalse(playlist.isEmpty,
                       "Playlist with tracks must report isEmpty = false")
    }

    // MARK: - Tests: count

    func testPlaylist_Count_EmptyPlaylist() {
        let playlist = Playlist()
        XCTAssertEqual(playlist.count, 0)
    }

    func testPlaylist_Count_WithTracks() {
        // Given: Playlist with 3 tracks
        let playlist = Playlist(tracks: [trackA, trackB, trackC])

        // Then
        XCTAssertEqual(playlist.count, 3,
                       "count must reflect number of tracks")
    }

    // MARK: - Tests: Field access and mutation

    func testPlaylist_DefaultName() {
        let playlist = Playlist()
        XCTAssertEqual(playlist.name, "Playlist",
                       "Default name must be 'Playlist'")
    }

    func testPlaylist_InitWithCustomName() {
        let playlist = Playlist(name: "Favourites")
        XCTAssertEqual(playlist.name, "Favourites")
    }

    func testPlaylist_InitWithTracks() {
        let playlist = Playlist(tracks: [trackA, trackB])
        XCTAssertEqual(playlist.tracks, [trackA, trackB])
    }

    func testPlaylist_MutableName_CanBeUpdated() {
        // Given
        var playlist = Playlist(name: "Original")

        // When
        playlist.name = "Updated"

        // Then
        XCTAssertEqual(playlist.name, "Updated")
    }

    func testPlaylist_MutableTracks_CanAppend() {
        // Given
        var playlist = Playlist()

        // When
        playlist.tracks.append(trackA)

        // Then
        XCTAssertEqual(playlist.count, 1)
        XCTAssertEqual(playlist.tracks.first, trackA)
    }

    func testPlaylist_MutableTracks_CanRemove() {
        // Given
        var playlist = Playlist(tracks: [trackA, trackB, trackC])

        // When
        playlist.tracks.removeAll { $0.id == trackB.id }

        // Then
        XCTAssertEqual(playlist.count, 2)
        XCTAssertFalse(playlist.tracks.contains(trackB))
    }

    // MARK: - Tests: Primary initializer

    func testPlaylist_InitWithAllFields_StoresAllValues() {
        // Given
        let id = UUID()
        let tracks = [trackA, trackB]

        // When
        let playlist = Playlist(id: id, name: "Full Init", tracks: tracks)

        // Then
        XCTAssertEqual(playlist.id, id)
        XCTAssertEqual(playlist.name, "Full Init")
        XCTAssertEqual(playlist.tracks, tracks)
    }

    func testPlaylist_DefaultInit_HasEmptyTracks() {
        let playlist = Playlist()
        XCTAssertTrue(playlist.tracks.isEmpty)
    }
}