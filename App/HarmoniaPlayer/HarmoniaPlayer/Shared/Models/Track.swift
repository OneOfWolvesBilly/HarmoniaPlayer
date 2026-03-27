//
//  Track.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Audio track model
///
/// Represents a single audio file in the playlist with full tag field support.
///
/// Fields are grouped as follows:
/// - **Core**: id, url, title, artist, album, duration, artworkData
/// - **Group A** – Extended tag fields: albumArtist, composer, genre, year,
///   trackNumber, trackTotal, discNumber, discTotal, bpm
/// - **Group B** – Replay Gain: replayGainTrack, replayGainAlbum
/// - **Group C** – Comment: comment
/// - **Group D** – Technical info: bitrate, sampleRate, channels, fileSize, fileFormat
/// - **Group E** – Playback statistics (reserved, no UI until Slice 8):
///   playCount, lastPlayedAt, rating
struct Track: Identifiable, Equatable, Sendable, Codable {

    // MARK: - Core fields

    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkData: Data?

    // MARK: - Group A: Extended tag fields

    var albumArtist: String = ""
    var composer: String = ""
    var genre: String = ""
    var year: Int? = nil
    var trackNumber: Int? = nil
    var trackTotal: Int? = nil
    var discNumber: Int? = nil
    var discTotal: Int? = nil
    var bpm: Int? = nil

    // MARK: - Group B: Replay Gain

    var replayGainTrack: Double? = nil
    var replayGainAlbum: Double? = nil

    // MARK: - Group C: Comment

    var comment: String = ""

    // MARK: - Group D: Technical info

    var bitrate: Int? = nil
    var sampleRate: Double? = nil
    var channels: Int? = nil
    var fileSize: Int? = nil
    var fileFormat: String = ""

    // MARK: - Group E: Playback statistics (reserved — no UI in Slice 7)

    var playCount: Int = 0
    var lastPlayedAt: Date? = nil
    var rating: Double? = nil

    // MARK: - Runtime-only fields (not persisted)

    var isAccessible: Bool = true
    var originalPath: String = ""

    // MARK: - Sort helpers for optional fields
    //
    // SwiftUI Table requires a Comparable keyPath for sortable columns.
    // These computed properties map nil → -1 so nil entries sort before any real value.

    var sortYear: Int          { year        ?? -1 }
    var sortTrackNumber: Int   { trackNumber ?? -1 }
    var sortDiscNumber: Int    { discNumber  ?? -1 }
    var sortBpm: Int           { bpm         ?? -1 }
    var sortBitrate: Int       { bitrate     ?? -1 }
    var sortSampleRate: Double { sampleRate  ?? -1 }
    var sortChannels: Int      { channels    ?? -1 }
    var sortFileSize: Int      { fileSize    ?? -1 }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        artworkData: Data? = nil,
        albumArtist: String = "",
        composer: String = "",
        genre: String = "",
        year: Int? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        bpm: Int? = nil,
        replayGainTrack: Double? = nil,
        replayGainAlbum: Double? = nil,
        comment: String = "",
        bitrate: Int? = nil,
        sampleRate: Double? = nil,
        channels: Int? = nil,
        fileSize: Int? = nil,
        fileFormat: String = "",
        playCount: Int = 0,
        lastPlayedAt: Date? = nil,
        rating: Double? = nil
    ) {
        self.id              = id
        self.url             = url
        self.title           = title
        self.artist          = artist
        self.album           = album
        self.duration        = duration
        self.artworkData     = artworkData
        self.albumArtist     = albumArtist
        self.composer        = composer
        self.genre           = genre
        self.year            = year
        self.trackNumber     = trackNumber
        self.trackTotal      = trackTotal
        self.discNumber      = discNumber
        self.discTotal       = discTotal
        self.bpm             = bpm
        self.replayGainTrack = replayGainTrack
        self.replayGainAlbum = replayGainAlbum
        self.comment         = comment
        self.bitrate         = bitrate
        self.sampleRate      = sampleRate
        self.channels        = channels
        self.fileSize        = fileSize
        self.fileFormat      = fileFormat
        self.playCount       = playCount
        self.lastPlayedAt    = lastPlayedAt
        self.rating          = rating
    }

    /// Convenience initializer that derives title from URL filename.
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
        case legacyURL = "url"
        case albumArtist, composer, genre, year
        case trackNumber, trackTotal, discNumber, discTotal, bpm
        case replayGainTrack, replayGainAlbum
        case comment
        case bitrate, sampleRate, channels, fileSize, fileFormat
        case playCount, lastPlayedAt, rating
    }

    // MARK: - Encodable

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(url.path, forKey: .urlPath)
        if url.isFileURL,
           let bookmark = try? url.bookmarkData(
               options: .minimalBookmark,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            try c.encode(bookmark, forKey: .accessBookmark)
        }
        try c.encode(title,    forKey: .title)
        try c.encode(artist,   forKey: .artist)
        try c.encode(album,    forKey: .album)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(artworkData,    forKey: .artworkData)
        try c.encode(albumArtist,             forKey: .albumArtist)
        try c.encode(composer,                forKey: .composer)
        try c.encode(genre,                   forKey: .genre)
        try c.encodeIfPresent(year,           forKey: .year)
        try c.encodeIfPresent(trackNumber,    forKey: .trackNumber)
        try c.encodeIfPresent(trackTotal,     forKey: .trackTotal)
        try c.encodeIfPresent(discNumber,     forKey: .discNumber)
        try c.encodeIfPresent(discTotal,      forKey: .discTotal)
        try c.encodeIfPresent(bpm,            forKey: .bpm)
        try c.encodeIfPresent(replayGainTrack, forKey: .replayGainTrack)
        try c.encodeIfPresent(replayGainAlbum, forKey: .replayGainAlbum)
        try c.encode(comment,                 forKey: .comment)
        try c.encodeIfPresent(bitrate,        forKey: .bitrate)
        try c.encodeIfPresent(sampleRate,     forKey: .sampleRate)
        try c.encodeIfPresent(channels,       forKey: .channels)
        try c.encodeIfPresent(fileSize,       forKey: .fileSize)
        try c.encode(fileFormat,              forKey: .fileFormat)
        try c.encode(playCount,               forKey: .playCount)
        try c.encodeIfPresent(lastPlayedAt,   forKey: .lastPlayedAt)
        try c.encodeIfPresent(rating,         forKey: .rating)
    }

    // MARK: - Decodable

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)

        // Resolve URL: bookmark → urlPath → legacy url key
        if let bookmark = try c.decodeIfPresent(Data.self, forKey: .accessBookmark) {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                url = resolved
                isAccessible = true
            } else if let path = try c.decodeIfPresent(String.self, forKey: .urlPath) {
                url = URL(fileURLWithPath: path)
                isAccessible = false
            } else {
                let legacy = try c.decode(URL.self, forKey: .legacyURL)
                url = URL(fileURLWithPath: legacy.path)
                isAccessible = false
            }
        } else if let path = try c.decodeIfPresent(String.self, forKey: .urlPath) {
            url = URL(fileURLWithPath: path)
            isAccessible = true
        } else {
            let legacy = try c.decode(URL.self, forKey: .legacyURL)
            url = URL(fileURLWithPath: legacy.path)
            isAccessible = true
        }

        if let path = try c.decodeIfPresent(String.self, forKey: .urlPath) {
            originalPath = path
        } else if let legacy = try? c.decode(URL.self, forKey: .legacyURL) {
            originalPath = legacy.path
        } else {
            originalPath = url.path
        }

        title       = try c.decode(String.self,       forKey: .title)
        artist      = try c.decode(String.self,       forKey: .artist)
        album       = try c.decode(String.self,       forKey: .album)
        duration    = try c.decode(TimeInterval.self, forKey: .duration)
        artworkData = try c.decodeIfPresent(Data.self, forKey: .artworkData)

        // Group A — decodeIfPresent for backward compat with older saves
        albumArtist = try c.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
        composer    = try c.decodeIfPresent(String.self, forKey: .composer)    ?? ""
        genre       = try c.decodeIfPresent(String.self, forKey: .genre)       ?? ""
        year        = try c.decodeIfPresent(Int.self,    forKey: .year)
        trackNumber = try c.decodeIfPresent(Int.self,    forKey: .trackNumber)
        trackTotal  = try c.decodeIfPresent(Int.self,    forKey: .trackTotal)
        discNumber  = try c.decodeIfPresent(Int.self,    forKey: .discNumber)
        discTotal   = try c.decodeIfPresent(Int.self,    forKey: .discTotal)
        bpm         = try c.decodeIfPresent(Int.self,    forKey: .bpm)

        // Group B
        replayGainTrack = try c.decodeIfPresent(Double.self, forKey: .replayGainTrack)
        replayGainAlbum = try c.decodeIfPresent(Double.self, forKey: .replayGainAlbum)

        // Group C
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""

        // Group D
        bitrate    = try c.decodeIfPresent(Int.self,    forKey: .bitrate)
        sampleRate = try c.decodeIfPresent(Double.self, forKey: .sampleRate)
        channels   = try c.decodeIfPresent(Int.self,    forKey: .channels)
        fileSize   = try c.decodeIfPresent(Int.self,    forKey: .fileSize)
        fileFormat = try c.decodeIfPresent(String.self, forKey: .fileFormat) ?? ""

        // Group E
        playCount    = try c.decodeIfPresent(Int.self,    forKey: .playCount)    ?? 0
        lastPlayedAt = try c.decodeIfPresent(Date.self,   forKey: .lastPlayedAt)
        rating       = try c.decodeIfPresent(Double.self, forKey: .rating)
    }

    // MARK: - Equatable

    nonisolated static func == (lhs: Track, rhs: Track) -> Bool {
        guard lhs.id          == rhs.id,
              lhs.url         == rhs.url,
              lhs.title       == rhs.title,
              lhs.artist      == rhs.artist,
              lhs.album       == rhs.album,
              lhs.duration    == rhs.duration,
              lhs.artworkData == rhs.artworkData,
              lhs.isAccessible == rhs.isAccessible
        else { return false }
        guard lhs.albumArtist == rhs.albumArtist,
              lhs.composer    == rhs.composer,
              lhs.genre       == rhs.genre,
              lhs.year        == rhs.year,
              lhs.trackNumber == rhs.trackNumber,
              lhs.trackTotal  == rhs.trackTotal,
              lhs.discNumber  == rhs.discNumber,
              lhs.discTotal   == rhs.discTotal,
              lhs.bpm         == rhs.bpm
        else { return false }
        guard lhs.replayGainTrack == rhs.replayGainTrack,
              lhs.replayGainAlbum == rhs.replayGainAlbum,
              lhs.comment         == rhs.comment
        else { return false }
        guard lhs.bitrate    == rhs.bitrate,
              lhs.sampleRate == rhs.sampleRate,
              lhs.channels   == rhs.channels,
              lhs.fileSize   == rhs.fileSize,
              lhs.fileFormat == rhs.fileFormat
        else { return false }
        return lhs.playCount    == rhs.playCount &&
               lhs.lastPlayedAt == rhs.lastPlayedAt &&
               lhs.rating       == rhs.rating
    }
}
