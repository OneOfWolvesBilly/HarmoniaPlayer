//
//  HarmoniaTagReaderAdapter.swift
//  HarmoniaPlayer / Shared / Services
//
//  Created on 2026-03-12.
//
//  PURPOSE
//  -------
//  Bridges HarmoniaCore.TagReaderPort (synchronous, returns TagBundle) to the
//  async HarmoniaPlayer.TagReaderService protocol that AppState depends on.
//
//  DESIGN NOTES
//  ------------
//  - One of only three production files in HarmoniaPlayer allowed to import HarmoniaCore.
//  - All metadata reading (tags AND technical info) is performed inside
//    HarmoniaCore's AVMetadataTagReaderAdapter. This file does pure
//    TagBundle → Track mapping only. No AVFoundation calls.
//  - fileFormat is derived from url.pathExtension — it is not part of TagBundle
//    because it is a URL property, not an audio stream property.
//  - currentSchemaVersion is forwarded from TagBundle.currentSchemaVersion so
//    that AppState can detect stale tracks without importing HarmoniaCore.
//
//  FIELD MAPPING
//  ─────────────────────────────────────────────────────────────────────────────
//  TagBundle field      → Track field       Fallback
//  ─────────────────────────────────────────────────────────────────────────────
//  title                → title             URL stem
//  artist               → artist            ""
//  album                → album             ""
//  albumArtist          → albumArtist       ""
//  composer             → composer          ""
//  genre                → genre             ""
//  year                 → year              nil
//  trackNumber          → trackNumber       nil
//  trackTotal           → trackTotal        nil
//  discNumber           → discNumber        nil
//  discTotal            → discTotal         nil
//  bpm                  → bpm               nil
//  comment              → comment           ""
//  replayGainTrack      → replayGainTrack   nil
//  replayGainAlbum      → replayGainAlbum   nil
//  artworkData          → artworkData       nil
//  duration             → duration          0
//  bitrate              → bitrate           nil
//  sampleRate           → sampleRate        nil
//  channels             → channels          nil
//  fileSize             → fileSize          nil
//  url.pathExtension    → fileFormat        uppercased()
//  TagBundle.currentSchemaVersion → metadataVersion
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation
import HarmoniaCore

/// Bridges the synchronous `TagReaderPort` to the async `TagReaderService` protocol.
///
/// Maps `TagBundle` fields to `Track`. All metadata (tags + technical info) is
/// read by HarmoniaCore. This adapter performs pure data mapping only.
final class HarmoniaTagReaderAdapter: TagReaderService {

    // MARK: - Dependencies

    private let port: TagReaderPort

    // MARK: - Initialization

    init(port: TagReaderPort) {
        self.port = port
    }

    // MARK: - TagReaderService

    var currentSchemaVersion: Int {
        TagBundle.currentSchemaVersion
    }

    func readMetadata(for url: URL) async throws -> Track {
        // All metadata (tags + technical info) comes from HarmoniaCore
        let bundle = try port.read(url: url)

        let fileFormat = url.pathExtension.uppercased()

        // ── Assemble Track (TagBundle → Track) ────────────────────────────
        return Track(
            url:              url,
            title:            bundle.title       ?? url.deletingPathExtension().lastPathComponent,
            artist:           bundle.artist      ?? "",
            album:            bundle.album       ?? "",
            duration:         bundle.duration    ?? 0,
            artworkData:      bundle.artworkData,
            albumArtist:      bundle.albumArtist ?? "",
            composer:         bundle.composer    ?? "",
            genre:            bundle.genre       ?? "",
            year:             bundle.year,
            trackNumber:      bundle.trackNumber,
            trackTotal:       bundle.trackTotal,
            discNumber:       bundle.discNumber,
            discTotal:        bundle.discTotal,
            bpm:              bundle.bpm,
            replayGainTrack:  bundle.replayGainTrack,
            replayGainAlbum:  bundle.replayGainAlbum,
            comment:          bundle.comment     ?? "",
            bitrate:          bundle.bitrate,
            sampleRate:       bundle.sampleRate,
            channels:         bundle.channels,
            fileSize:         bundle.fileSize,
            fileFormat:       fileFormat,
            metadataVersion:  TagBundle.currentSchemaVersion
        )
    }
}
