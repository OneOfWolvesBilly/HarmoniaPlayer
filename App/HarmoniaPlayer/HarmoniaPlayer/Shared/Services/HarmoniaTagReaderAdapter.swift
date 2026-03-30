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
//  - All metadata reading (including albumArtist, genre, year, trackNumber,
//    discNumber) is performed inside HarmoniaCore's AVMetadataTagReaderAdapter.
//    This file does pure TagBundle → Track mapping only. No AVFoundation calls.
//  - Duration is not part of TagBundle; it is read via AVURLAsset.load(.duration).
//  - Technical info (bitrate, sampleRate, channels, fileSize, fileFormat) is
//    not part of TagBundle either; it is read via AVURLAsset here because
//    HarmoniaCore's TagReaderPort contract is limited to tag metadata only.
//  - metadataVersion is set to currentMetadataVersion on every new read so
//    AppState.refreshMetadataIfNeeded() can skip already-up-to-date tracks.
//
//  FIELD MAPPING
//  ─────────────────────────────────────────────────────────────────────────────
//  TagBundle field      → Track field       Fallback
//  ─────────────────────────────────────────────────────────────────────────────
//  title                → title             URL stem
//  artist               → artist            ""
//  album                → album             ""
//  albumArtist          → albumArtist       ""
//  genre                → genre             ""
//  year                 → year              nil
//  trackNumber          → trackNumber       nil
//  discNumber           → discNumber        nil
//  artworkData          → artworkData       nil
//  AVURLAsset.duration  → duration          0
//  AVURLAsset tracks    → bitrate           kbps; nil if unavailable
//  CMFormatDescription  → sampleRate        nil if unavailable
//  CMFormatDescription  → channels          nil if unavailable
//  FileManager          → fileSize          nil if unavailable
//  url.pathExtension    → fileFormat        uppercased()
//  constant (1)         → metadataVersion
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation
import AVFoundation
import HarmoniaCore

/// Bridges the synchronous `TagReaderPort` to the async `TagReaderService` protocol.
///
/// Maps `TagBundle` fields to `Track`. All tag metadata is read by HarmoniaCore.
/// Only duration and technical audio info (not part of TagBundle) are read here
/// via AVFoundation.
final class HarmoniaTagReaderAdapter: TagReaderService {

    // MARK: - Dependencies

    private let port: TagReaderPort

    // MARK: - Metadata version

    /// Must match `AppState.currentMetadataVersion`.
    /// Increment both together whenever new fields are added to Track.
    static let metadataVersion = 1

    // MARK: - Initialization

    init(port: TagReaderPort) {
        self.port = port
    }

    // MARK: - TagReaderService

    func readMetadata(for url: URL) async throws -> Track {
        // All tag metadata comes from HarmoniaCore
        let bundle = try port.read(url: url)

        let asset = AVURLAsset(url: url)

        // ── Duration (not in TagBundle) ────────────────────────────────────
        let cmDuration = try? await asset.load(.duration)
        let duration: TimeInterval = cmDuration.map { $0.seconds > 0 ? $0.seconds : 0 } ?? 0

        // ── Technical info (not in TagBundle) ─────────────────────────────
        let assetTracks = try? await asset.load(.tracks)
        let firstAudio  = assetTracks?.first { $0.mediaType == .audio }

        let estimatedDataRate = try? await firstAudio?.load(.estimatedDataRate)
        let bitrate: Int? = estimatedDataRate.flatMap { rate in
            let kbps = Int(rate / 1000)
            return kbps > 0 ? kbps : nil
        }

        var sampleRate: Double? = nil
        var channels: Int? = nil
        if let audioTrack = firstAudio,
           let formatDescriptions = try? await audioTrack.load(.formatDescriptions),
           let firstDesc = formatDescriptions.first {
            let desc = firstDesc as CMFormatDescription
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                let rate = basic.pointee.mSampleRate
                sampleRate = rate > 0 ? rate : nil
                let ch = Int(basic.pointee.mChannelsPerFrame)
                channels = ch > 0 ? ch : nil
            }
        }

        let fileSize: Int? = {
            guard url.isFileURL else { return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return attrs?[.size] as? Int
        }()

        let fileFormat = url.pathExtension.uppercased()

        // ── Assemble Track (TagBundle → Track) ────────────────────────────
        return Track(
            url:             url,
            title:           bundle.title       ?? url.deletingPathExtension().lastPathComponent,
            artist:          bundle.artist      ?? "",
            album:           bundle.album       ?? "",
            duration:        duration,
            artworkData:     bundle.artworkData,
            albumArtist:     bundle.albumArtist ?? "",
            genre:           bundle.genre       ?? "",
            year:            bundle.year,
            trackNumber:     bundle.trackNumber,
            discNumber:      bundle.discNumber,
            bitrate:         bitrate,
            sampleRate:      sampleRate,
            channels:        channels,
            fileSize:        fileSize,
            fileFormat:      fileFormat,
            metadataVersion: Self.metadataVersion
        )
    }
}
