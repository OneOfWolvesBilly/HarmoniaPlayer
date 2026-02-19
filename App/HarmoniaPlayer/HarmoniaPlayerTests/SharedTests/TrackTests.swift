//
//  TrackTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-18.
//
//  Slice 2-A: Track Model
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for Track model
///
/// Validates that Track correctly:
/// - Conforms to Identifiable with unique IDs
/// - Conforms to Equatable by value
/// - Stores all metadata fields correctly
/// - Derives title from URL in convenience initializer
///
/// **Design constraints (Slice 2-A):**
/// - No HarmoniaCore dependency
/// - No UIKit / AppKit dependency
/// - Pure value type tests
final class TrackTests: XCTestCase {

    // MARK: - Helpers

    private let sampleURL = URL(fileURLWithPath: "/Music/sample.mp3")
    private let otherURL  = URL(fileURLWithPath: "/Music/other.flac")

    // MARK: - Tests: Identifiable

    func testTrack_HasUniqueID() {
        // Given: Two separate Track instances created from the same URL
        let track1 = Track(url: sampleURL)
        let track2 = Track(url: sampleURL)

        // Then: Each instance receives its own UUID
        XCTAssertNotEqual(track1.id, track2.id,
                          "Two Track instances must have different IDs")
    }

    func testTrack_IDIsStable() {
        // Given: A track
        let track = Track(url: sampleURL)
        let capturedID = track.id

        // Then: ID does not change across accesses
        XCTAssertEqual(track.id, capturedID,
                       "Track ID must be stable after creation")
    }

    // MARK: - Tests: Equatable

    func testTrack_Equatable_SameFields_AreEqual() {
        // Given: Two tracks sharing the same explicit ID and fields
        let sharedID = UUID()
        let track1 = Track(id: sharedID,
                           url: sampleURL,
                           title: "Song",
                           artist: "Artist",
                           album: "Album",
                           duration: 180.0)
        let track2 = Track(id: sharedID,
                           url: sampleURL,
                           title: "Song",
                           artist: "Artist",
                           album: "Album",
                           duration: 180.0)

        // Then: They are equal
        XCTAssertEqual(track1, track2,
                       "Tracks with identical fields must be equal")
    }

    func testTrack_Equatable_DifferentID_AreNotEqual() {
        // Given: Two tracks with same URL but different IDs (default UUID())
        let track1 = Track(url: sampleURL)
        let track2 = Track(url: sampleURL)

        // Then: Different IDs → not equal
        XCTAssertNotEqual(track1, track2,
                          "Tracks with different IDs must not be equal")
    }

    func testTrack_Equatable_DifferentURL_AreNotEqual() {
        // Given: Same ID, different URLs
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "Song")
        let track2 = Track(id: sharedID, url: otherURL,  title: "Song")

        // Then: Not equal
        XCTAssertNotEqual(track1, track2,
                          "Tracks with different URLs must not be equal")
    }

    func testTrack_Equatable_DifferentTitle_AreNotEqual() {
        // Given: Same ID and URL, different title
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "Title A")
        let track2 = Track(id: sharedID, url: sampleURL, title: "Title B")

        // Then: Not equal
        XCTAssertNotEqual(track1, track2,
                          "Tracks with different titles must not be equal")
    }

    // MARK: - Tests: Convenience initializer (URL-derived title)

    func testTrack_InitWithURL_DerivesTitleFromFilename() {
        // Given: URL with a filename
        let url = URL(fileURLWithPath: "/Music/My Favourite Song.mp3")

        // When: Use convenience initializer
        let track = Track(url: url)

        // Then: Title is the filename without extension
        XCTAssertEqual(track.title, "My Favourite Song",
                       "Convenience init should derive title from URL filename (no extension)")
    }

    func testTrack_InitWithURL_SetsURL() {
        // Given / When
        let track = Track(url: sampleURL)

        // Then
        XCTAssertEqual(track.url, sampleURL,
                       "URL should be stored as-is")
    }

    func testTrack_InitWithURL_DefaultsMetadataToEmpty() {
        // Given / When
        let track = Track(url: sampleURL)

        // Then: Artist and album default to empty strings
        XCTAssertEqual(track.artist, "",
                       "Convenience init should default artist to empty string")
        XCTAssertEqual(track.album, "",
                       "Convenience init should default album to empty string")
    }

    func testTrack_InitWithURL_DefaultsDurationToNil() {
        // Given / When
        let track = Track(url: sampleURL)

        // Then
        XCTAssertNil(track.duration,
                     "Convenience init should default duration to nil (unknown until Slice 3)")
    }

    func testTrack_InitWithURL_DefaultsArtworkToNil() {
        // Given / When
        let track = Track(url: sampleURL)

        // Then
        XCTAssertNil(track.artworkURL,
                     "Convenience init should default artworkURL to nil")
    }

    // MARK: - Tests: Primary initializer (all fields)

    func testTrack_InitWithAllFields_StoresAllValues() {
        // Given
        let id       = UUID()
        let duration = TimeInterval(213.5)
        let artwork  = URL(fileURLWithPath: "/Music/cover.jpg")

        // When
        let track = Track(id: id,
                          url: sampleURL,
                          title: "Full Song",
                          artist: "Full Artist",
                          album: "Full Album",
                          duration: duration,
                          artworkURL: artwork)

        // Then: Every field matches
        XCTAssertEqual(track.id,         id)
        XCTAssertEqual(track.url,        sampleURL)
        XCTAssertEqual(track.title,      "Full Song")
        XCTAssertEqual(track.artist,     "Full Artist")
        XCTAssertEqual(track.album,      "Full Album")
        XCTAssertEqual(track.duration,   duration)
        XCTAssertEqual(track.artworkURL, artwork)
    }

    func testTrack_InitWithAllFields_DefaultParameters() {
        // Given: Only required parameters (url + title)
        let track = Track(url: sampleURL, title: "Minimal")

        // Then: Defaults applied
        XCTAssertEqual(track.artist,  "",
                       "artist should default to empty string")
        XCTAssertEqual(track.album,   "",
                       "album should default to empty string")
        XCTAssertNil(track.duration,
                     "duration should default to nil")
        XCTAssertNil(track.artworkURL,
                     "artworkURL should default to nil")
    }

    // MARK: - Tests: Mutability

    func testTrack_MutableFields_CanBeUpdated() {
        // Given
        var track = Track(url: sampleURL, title: "Original")

        // When: Simulate metadata update (as Slice 3 will do)
        track.title    = "Updated Title"
        track.artist   = "Updated Artist"
        track.album    = "Updated Album"
        track.duration = 300.0

        // Then: Mutable fields accept new values
        XCTAssertEqual(track.title,    "Updated Title")
        XCTAssertEqual(track.artist,   "Updated Artist")
        XCTAssertEqual(track.album,    "Updated Album")
        XCTAssertEqual(track.duration, 300.0)
    }

    func testTrack_ImmutableFields_CannotChangeAfterInit() {
        // Given: This test documents design intent via the type system.
        // id and url are `let` constants — compile-time enforcement.
        // Verified by reading the struct definition; no runtime assertion needed.
        let track = Track(url: sampleURL, title: "Immutable Test")

        // Then: These properties exist and are readable
        XCTAssertNotNil(track.id,  "id must be accessible")
        XCTAssertEqual(track.url, sampleURL, "url must be accessible")
        // Attempting `track.id = UUID()` would be a compile error — enforced by `let`
    }
}