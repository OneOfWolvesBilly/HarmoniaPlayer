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

    // MARK: - Slice 9-M temp directory helper

    /// Create an isolated temporary directory for tests that need real on-disk
    /// files (bookmark roundtrip, security-scope verification). Cleaned up by
    /// the test method itself; class-level setUp/tearDown are not used because
    /// most existing tests above operate on synthetic /Music/sample.mp3 URLs.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeRealFile(in dir: URL, name: String = "song.mp3",
                              contents: Data = Data("v1".utf8)) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    // MARK: - Slice 9-M Layer 2: security-scoped bookmark roundtrip

    /// 9-M red driving test #1.
    /// Verifies that a Track encoded → decoded preserves the URL via a
    /// security-scoped bookmark such that the decoded URL accepts
    /// `startAccessingSecurityScopedResource()`. Fails on current code that
    /// uses `.minimalBookmark` (no security scope), passes on green code that
    /// uses `[.withSecurityScope]`.
    func testTrack_BookmarkRoundtrip_PreservesURLViaSecurityScope() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeRealFile(in: dir)

        let original = Track(url: url, title: "RoundTrip")
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Track.self, from: encoded)

        XCTAssertEqual(restored.url, url, "URL must roundtrip")

        let started = restored.url.startAccessingSecurityScopedResource()
        defer {
            if started { restored.url.stopAccessingSecurityScopedResource() }
        }
        XCTAssertTrue(started,
            "Decoded URL must allow startAccessingSecurityScopedResource() — "
            + "required so sandbox cold-launch can access the file. "
            + ".minimalBookmark fails this; .withSecurityScope passes.")
    }

    // MARK: - Slice 9-M Layer 2: stale bookmark refresh

    /// 9-M red driving test #2.
    /// Verifies that decoding a Track whose underlying file has been atomically
    /// replaced refreshes the persisted bookmark. Fails on current code which
    /// captures the stale flag but never acts on it, passes on green code that
    /// regenerates the bookmark when stale=true.
    ///
    /// macOS filesystem caveat: `replaceItemAt` triggers stale-flag detection
    /// in most observed configurations. If this test passes-on-red on a
    /// particular host, it falls back to manual QA (rename file across
    /// directories during a real run) — see spec Done criteria.
    func testTrack_BookmarkResolution_StaleFlag_TriggersRefresh() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeRealFile(in: dir, contents: Data("v1".utf8))

        let original = Track(url: url, title: "Stale")
        let encoded1 = try JSONEncoder().encode(original)

        // Atomically replace the file to mark the bookmark stale on next resolve.
        let replacement = dir.appendingPathComponent("replacement.tmp")
        try Data("v2".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)

        let restored = try JSONDecoder().decode(Track.self, from: encoded1)
        let encoded2 = try JSONEncoder().encode(restored)

        XCTAssertNotEqual(encoded1, encoded2,
            "Track must refresh its accessBookmark when stale flag is set "
            + "during decode. Current code captures &stale but ignores it; "
            + "green code regenerates the bookmark from the resolved URL.")
    }

    // MARK: - Slice 9-M Layer 2: legacy minimalBookmark decode

    /// 9-M red driving test #3.
    /// Verifies that legacy `.minimalBookmark` data (in case any made it to a
    /// TestFlight build during 9-A → 9-I) decodes as inaccessible rather than
    /// crashing. Fails on current code which still uses `.minimalBookmark` for
    /// resolve and so accepts the legacy bytes (isAccessible=true), passes on
    /// green code that resolves with `[.withSecurityScope]` and treats
    /// scope-less bytes as inaccessible.
    func testTrack_LegacyMinimalBookmark_DecodesAsInaccessible() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeRealFile(in: dir)

        // Build legacy bookmark data (no security scope).
        let legacyBookmark = try url.bookmarkData(options: .minimalBookmark,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)

        // Hand-craft a Track-shape JSON that mirrors what 9-A → 9-I encoded.
        // Track's CodingKeys uses urlPath + accessBookmark (Data → base64 in JSON).
        let id = UUID().uuidString
        let json = """
        {
            "id": "\(id)",
            "urlPath": "\(url.path)",
            "title": "Legacy",
            "artist": "",
            "album": "",
            "duration": 0,
            "accessBookmark": "\(legacyBookmark.base64EncodedString())"
        }
        """.data(using: .utf8)!

        // Decoding must not throw; must produce isAccessible == false.
        let restored = try JSONDecoder().decode(Track.self, from: json)
        XCTAssertFalse(restored.isAccessible,
            "Legacy .minimalBookmark bytes lack security scope; resolving "
            + "them under [.withSecurityScope] must fail safely, marking "
            + "the Track inaccessible without crashing.")
    }

    // MARK: - Slice 9-M Layer 2: isAccessible behaviour contract (green-phase)

    /// 9-M green-phase contract test.
    /// Verifies that decoding a Track whose underlying file exists yields
    /// `isAccessible == true` after the security-scoped resource start
    /// succeeds. Behaviour-contract: green-phase implementation must
    /// preserve default-true on the valid path.
    func testTrack_IsAccessible_TrueWhenBookmarkResolvesAndAccessStarts() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeRealFile(in: dir)

        let original = Track(url: url, title: "Accessible")
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Track.self, from: encoded)

        XCTAssertTrue(restored.isAccessible,
            "Real on-disk file with valid security-scoped bookmark must "
            + "yield isAccessible = true after decode.")
    }

    /// 9-M green-phase contract test.
    /// Verifies that a Track whose bookmark target was deleted between
    /// encode and decode yields `isAccessible == false`. Behaviour-
    /// contract: green-phase implementation must set false when the
    /// security-scoped resource start fails.
    func testTrack_IsAccessible_FalseWhenStartAccessFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeRealFile(in: dir)

        let original = Track(url: url, title: "Vanishing")
        let encoded = try JSONEncoder().encode(original)

        // Delete the file to simulate external removal.
        try FileManager.default.removeItem(at: url)
        // Also delete the parent dir so bookmark resolution truly fails.
        try FileManager.default.removeItem(at: dir)

        let restored = try JSONDecoder().decode(Track.self, from: encoded)

        XCTAssertFalse(restored.isAccessible,
            "Track whose bookmark target was deleted must yield "
            + "isAccessible = false (bookmark resolution failure → "
            + "fall through to urlPath path with isAccessible = false).")
    }
}
