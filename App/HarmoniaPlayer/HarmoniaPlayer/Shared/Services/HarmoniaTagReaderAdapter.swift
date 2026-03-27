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
//  - TagBundle does NOT carry a duration field. Duration is read via
//    AVURLAsset.load(.duration). Defaults to 0 if unavailable.
//
//  FIELD MAPPING STRATEGY
//  ----------------------
//  Source               Track field        Fallback / note
//  ─────────────────────────────────────────────────────────────────────────────
//  TagBundle.title      title              URL stem (deletingPathExtension)
//  TagBundle.artist     artist             ""
//  TagBundle.album      album              ""
//  TagBundle.albumArtist albumArtist       ""
//  TagBundle.genre      genre              ""
//  TagBundle.year       year               nil
//  TagBundle.trackNumber trackNumber       nil
//  TagBundle.discNumber discNumber         nil
//  TagBundle.artworkData artworkData       nil
//  AVURLAsset.duration  duration           0
//  AVURLAsset tracks    bitrate            Int(estimatedDataRate / 1000) kbps
//  CMFormatDescription  sampleRate         first audio track's nominal rate
//  CMFormatDescription  channels           channel layout channel count
//  FileManager          fileSize           attributesOfItem[.size]
//  url.pathExtension    fileFormat         uppercased()
//
//  Fields with no mapping source (composer, bpm, trackTotal, discTotal,
//  replayGainTrack/Album, comment): remain at default (nil / "")

import Foundation
import AVFoundation
import HarmoniaCore

/// Bridges the synchronous `TagReaderPort` to the async `TagReaderService` protocol.
///
/// Maps `TagBundle` fields and AVFoundation technical info to a `Track` value.
/// See the module header for the full field mapping table.
final class HarmoniaTagReaderAdapter: TagReaderService {

    // MARK: - Dependencies

    private let port: TagReaderPort

    // MARK: - Initialization

    init(port: TagReaderPort) {
        self.port = port
    }

    // MARK: - TagReaderService

    func readMetadata(for url: URL) async throws -> Track {
        let bundle = try port.read(url: url)

        let asset = AVURLAsset(url: url)

        // Duration
        let cmDuration = try? await asset.load(.duration)
        let duration: TimeInterval = cmDuration.map { $0.seconds > 0 ? $0.seconds : 0 } ?? 0

        // Technical info from first audio track
        let assetTracks = try? await asset.load(.tracks)
        let audioTracks = assetTracks?.filter { $0.mediaType == .audio } ?? []
        let firstAudio  = audioTracks.first

        let estimatedDataRate = try? await firstAudio?.load(.estimatedDataRate)
        let bitrate: Int? = estimatedDataRate.map { rate in
            let kbps = Int(rate / 1000)
            return kbps > 0 ? kbps : nil
        } ?? nil

        var sampleRate: Double? = nil
        var channels: Int? = nil

        if let audioTrack = firstAudio,
           let formatDescriptions = try? await audioTrack.load(.formatDescriptions),
           let firstDesc = formatDescriptions.first {
            let desc = firstDesc as CMFormatDescription
            if let streamBasicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                let rate = streamBasicDesc.pointee.mSampleRate
                sampleRate = rate > 0 ? rate : nil
                let ch = Int(streamBasicDesc.pointee.mChannelsPerFrame)
                channels = ch > 0 ? ch : nil
            }
        }

        // File size
        let fileSize: Int? = {
            guard url.isFileURL else { return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return attrs?[.size] as? Int
        }()

        // File format
        let fileFormat = url.pathExtension.uppercased()

        return Track(
            url:         url,
            title:       bundle.title       ?? url.deletingPathExtension().lastPathComponent,
            artist:      bundle.artist      ?? "",
            album:       bundle.album       ?? "",
            duration:    duration,
            artworkData: bundle.artworkData,
            albumArtist: bundle.albumArtist ?? "",
            genre:       bundle.genre       ?? "",
            year:        bundle.year,
            trackNumber: bundle.trackNumber,
            discNumber:  bundle.discNumber,
            bitrate:     bitrate,
            sampleRate:  sampleRate,
            channels:    channels,
            fileSize:    fileSize,
            fileFormat:  fileFormat
        )
    }
}
