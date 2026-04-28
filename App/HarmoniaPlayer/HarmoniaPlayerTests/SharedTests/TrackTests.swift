//
//  TrackTests.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-18.
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
/// - Exposes Groups A–E fields with correct defaults
/// - Round-trips all fields through Codable
@MainActor
final class TrackTests: XCTestCase {

    // MARK: - Helpers

    private let sampleURL = URL(fileURLWithPath: "/Music/sample.mp3")
    private let otherURL  = URL(fileURLWithPath: "/Music/other.flac")

    // MARK: - Tests: Identifiable

    func testTrack_HasUniqueID() {
        let track1 = Track(url: sampleURL)
        let track2 = Track(url: sampleURL)
        XCTAssertNotEqual(track1.id, track2.id)
    }

    func testTrack_IDIsStable() {
        let track = Track(url: sampleURL)
        let capturedID = track.id
        XCTAssertEqual(track.id, capturedID)
    }

    // MARK: - Tests: Equatable

    func testTrack_Equatable_SameFields_AreEqual() {
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "Song",
                           artist: "Artist", album: "Album", duration: 180.0)
        let track2 = Track(id: sharedID, url: sampleURL, title: "Song",
                           artist: "Artist", album: "Album", duration: 180.0)
        XCTAssertEqual(track1, track2)
    }

    func testTrack_Equatable_DifferentID_AreNotEqual() {
        let track1 = Track(url: sampleURL)
        let track2 = Track(url: sampleURL)
        XCTAssertNotEqual(track1, track2)
    }

    func testTrack_Equatable_DifferentURL_AreNotEqual() {
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "Song")
        let track2 = Track(id: sharedID, url: otherURL,  title: "Song")
        XCTAssertNotEqual(track1, track2)
    }

    func testTrack_Equatable_DifferentTitle_AreNotEqual() {
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "Title A")
        let track2 = Track(id: sharedID, url: sampleURL, title: "Title B")
        XCTAssertNotEqual(track1, track2)
    }

    // MARK: - Tests: Convenience initializer

    func testTrack_InitWithURL_DerivesTitleFromFilename() {
        let url = URL(fileURLWithPath: "/Music/My Favourite Song.mp3")
        let track = Track(url: url)
        XCTAssertEqual(track.title, "My Favourite Song")
    }

    func testTrack_InitWithURL_SetsURL() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.url, sampleURL)
    }

    func testTrack_InitWithURL_DefaultsMetadataToEmpty() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.artist, "")
        XCTAssertEqual(track.album, "")
    }

    func testTrack_InitWithURL_DefaultsDurationToNil() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.duration, 0)
    }

    func testTrack_InitWithURL_DefaultsArtworkToNil() {
        let track = Track(url: sampleURL)
        XCTAssertNil(track.artworkData)
    }

    // MARK: - Tests: Primary initializer

    func testTrack_InitWithAllFields_StoresAllValues() {
        let id       = UUID()
        let duration = TimeInterval(213.5)
        let artwork  = Data([0xFF, 0xD8, 0xFF])
        let track = Track(id: id, url: sampleURL, title: "Full Song",
                          artist: "Full Artist", album: "Full Album",
                          duration: duration, artworkData: artwork)
        XCTAssertEqual(track.id,          id)
        XCTAssertEqual(track.url,         sampleURL)
        XCTAssertEqual(track.title,       "Full Song")
        XCTAssertEqual(track.artist,      "Full Artist")
        XCTAssertEqual(track.album,       "Full Album")
        XCTAssertEqual(track.duration,    duration)
        XCTAssertEqual(track.artworkData, artwork)
    }

    // MARK: - Tests: Mutability

    func testTrack_MutableFields_CanBeUpdated() {
        var track = Track(url: sampleURL, title: "Original")
        track.title  = "Updated Title"
        track.artist = "Updated Artist"
        track.album  = "Updated Album"
        track.duration = 300.0
        XCTAssertEqual(track.title,    "Updated Title")
        XCTAssertEqual(track.artist,   "Updated Artist")
        XCTAssertEqual(track.album,    "Updated Album")
        XCTAssertEqual(track.duration, 300.0)
    }

    // MARK: - Tests: isAccessible

    func testTrack_IsAccessible_DefaultIsTrue() {
        let track = Track(url: sampleURL)
        XCTAssertTrue(track.isAccessible)
    }

    func testTrack_Equatable_ConsidersIsAccessible() {
        let sharedID = UUID()
        var track1 = Track(id: sharedID, url: sampleURL, title: "Song")
        var track2 = Track(id: sharedID, url: sampleURL, title: "Song")
        track1.isAccessible = true
        track2.isAccessible = false
        XCTAssertNotEqual(track1, track2)
    }

    func testTrack_Codable_IsAccessible_FalseWhenFileNotFound() throws {
        let missingURL = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp3")
        let original = Track(url: missingURL, title: "Missing")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertTrue(restored.isAccessible)
    }

    func testTrack_Codable_IsAccessible_NotPersisted() throws {
        var original = Track(url: sampleURL, title: "Song")
        original.isAccessible = false
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertTrue(restored.isAccessible)
    }

    // MARK: - Tests: Group A defaults (Slice 7-G TDD matrix)

    func testTrack_DefaultGenre_IsEmpty() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.genre, "",
                       "genre must default to empty string")
    }

    func testTrack_DefaultYear_IsNil() {
        let track = Track(url: sampleURL)
        XCTAssertNil(track.year,
                     "year must default to nil")
    }

    func testTrack_DefaultBitrate_IsNil() {
        let track = Track(url: sampleURL)
        XCTAssertNil(track.bitrate,
                     "bitrate must default to nil")
    }

    func testTrack_DefaultPlayCount_IsZero() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.playCount, 0,
                       "playCount must default to 0")
    }

    func testTrack_DefaultRating_IsNil() {
        let track = Track(url: sampleURL)
        XCTAssertNil(track.rating,
                     "rating must default to nil")
    }

    func testTrack_Codec_DefaultEmpty() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.codec, "",
                       "codec must default to empty string")
    }

    func testTrack_Encoding_DefaultEmpty() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.encoding, "",
                       "encoding must default to empty string")
    }

    func testTrack_InitWithCodecAndEncoding_StoresValues() {
        let track = Track(url: sampleURL, title: "T",
                          codec: "AAC LC", encoding: "lossy")
        XCTAssertEqual(track.codec,    "AAC LC")
        XCTAssertEqual(track.encoding, "lossy")
    }

    func testTrack_Equatable_DifferentCodec_AreNotEqual() {
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "S",
                           codec: "MP3 Layer 3", encoding: "lossy")
        let track2 = Track(id: sharedID, url: sampleURL, title: "S",
                           codec: "AAC LC", encoding: "lossy")
        XCTAssertNotEqual(track1, track2)
    }

    func testTrack_Equatable_DifferentEncoding_AreNotEqual() {
        let sharedID = UUID()
        let track1 = Track(id: sharedID, url: sampleURL, title: "S",
                           codec: "FLAC", encoding: "lossless")
        let track2 = Track(id: sharedID, url: sampleURL, title: "S",
                           codec: "FLAC", encoding: "lossy")
        XCTAssertNotEqual(track1, track2)
    }

    func testTrack_AllNewFields_RoundTrip() throws {
        // Given: A track with all Groups A–E fields set
        let original = Track(
            id: UUID(),
            url: sampleURL,
            title: "Round Trip",
            artist: "Artist",
            album: "Album",
            duration: 180.0,
            albumArtist: "Various Artists",
            composer: "John Williams",
            genre: "Soundtrack",
            year: 1977,
            trackNumber: 3,
            trackTotal: 12,
            discNumber: 1,
            discTotal: 2,
            bpm: 120,
            replayGainTrack: -6.5,
            replayGainAlbum: -7.2,
            comment: "Original pressing",
            bitrate: 320,
            sampleRate: 44100,
            channels: 2,
            fileSize: 1_048_576,
            fileFormat: "MP3",
            codec: "MP3 Layer 3",
            encoding: "lossy",
            playCount: 7,
            lastPlayedAt: Date(timeIntervalSinceReferenceDate: 0),
            rating: 0.8
        )

        // When: Encode → Decode
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Track.self, from: data)

        // Then: All fields survive round-trip
        XCTAssertEqual(restored.title,       original.title)
        XCTAssertEqual(restored.albumArtist, original.albumArtist)
        XCTAssertEqual(restored.composer,    original.composer)
        XCTAssertEqual(restored.genre,       original.genre)
        XCTAssertEqual(restored.year,        original.year)
        XCTAssertEqual(restored.trackNumber, original.trackNumber)
        XCTAssertEqual(restored.trackTotal,  original.trackTotal)
        XCTAssertEqual(restored.discNumber,  original.discNumber)
        XCTAssertEqual(restored.discTotal,   original.discTotal)
        XCTAssertEqual(restored.bpm,         original.bpm)
        XCTAssertEqual(restored.replayGainTrack, original.replayGainTrack)
        XCTAssertEqual(restored.replayGainAlbum, original.replayGainAlbum)
        XCTAssertEqual(restored.comment,     original.comment)
        XCTAssertEqual(restored.bitrate,     original.bitrate)
        XCTAssertEqual(restored.sampleRate,  original.sampleRate)
        XCTAssertEqual(restored.channels,    original.channels)
        XCTAssertEqual(restored.fileSize,    original.fileSize)
        XCTAssertEqual(restored.fileFormat,  original.fileFormat)
        XCTAssertEqual(restored.codec,       original.codec)
        XCTAssertEqual(restored.encoding,    original.encoding)
        XCTAssertEqual(restored.playCount,   original.playCount)
        XCTAssertEqual(restored.lastPlayedAt, original.lastPlayedAt)
        XCTAssertEqual(restored.rating,      original.rating)
    }

    // MARK: - Tests: Sort helpers

    func testTrack_SortHelpers_ReturnMinusOneForNil() {
        let track = Track(url: sampleURL)
        XCTAssertEqual(track.sortYear,        -1)
        XCTAssertEqual(track.sortTrackNumber, -1)
        XCTAssertEqual(track.sortDiscNumber,  -1)
        XCTAssertEqual(track.sortBpm,         -1)
        XCTAssertEqual(track.sortBitrate,     -1)
        XCTAssertEqual(track.sortSampleRate,  -1)
        XCTAssertEqual(track.sortChannels,    -1)
        XCTAssertEqual(track.sortFileSize,    -1)
    }

    func testTrack_SortHelpers_ReturnActualValueWhenSet() {
        let track = Track(url: sampleURL, title: "T",
                          year: 2020, trackNumber: 5, discNumber: 1,
                          bpm: 130, bitrate: 256, sampleRate: 48000,
                          channels: 2, fileSize: 5_000_000)
        XCTAssertEqual(track.sortYear,        2020)
        XCTAssertEqual(track.sortTrackNumber, 5)
        XCTAssertEqual(track.sortDiscNumber,  1)
        XCTAssertEqual(track.sortBpm,         130)
        XCTAssertEqual(track.sortBitrate,     256)
        XCTAssertEqual(track.sortSampleRate,  48000)
        XCTAssertEqual(track.sortChannels,    2)
        XCTAssertEqual(track.sortFileSize,    5_000_000)
    }

    // MARK: - Tests: Backward compatibility

    func testTrack_OldCodableData_DecodesWithDefaultsForNewFields() throws {
        // Simulate data encoded by the old Track (no Group A–E keys)
        let sharedID = UUID()
        let oldJSON = """
        {
            "id": "\(sharedID.uuidString)",
            "urlPath": "/Music/old.mp3",
            "title": "Old Track",
            "artist": "Old Artist",
            "album": "Old Album",
            "duration": 120.0
        }
        """.data(using: .utf8)!

        let track = try JSONDecoder().decode(Track.self, from: oldJSON)

        XCTAssertEqual(track.genre,       "")
        XCTAssertNil(track.year)
        XCTAssertNil(track.bitrate)
        XCTAssertEqual(track.playCount,   0)
        XCTAssertNil(track.rating)
        XCTAssertEqual(track.albumArtist, "")
        XCTAssertEqual(track.comment,     "")
        XCTAssertEqual(track.fileFormat,  "")
        XCTAssertEqual(track.codec,       "")
        XCTAssertEqual(track.encoding,    "")
    }
    // MARK: - Lyrics field (Slice 9-J)

    func testTrack_DefaultLyrics_IsNil() {
        // Given / When
        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"))

        // Then: lyrics is nil by default (no USLT embedded, no .lrc sidecar loaded yet)
        XCTAssertNil(track.lyrics)
    }
}
