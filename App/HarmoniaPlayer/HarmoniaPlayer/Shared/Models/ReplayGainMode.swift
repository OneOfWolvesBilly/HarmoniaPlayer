//
//  ReplayGainMode.swift
//  HarmoniaPlayer / Shared / Models
//
//  Created on 2026-04-02.
//

/// ReplayGain application mode.
///
/// Controls how ReplayGain tags are used to adjust playback volume in `play(trackID:)`.
///
/// - `off`:   No gain adjustment. Volume is unchanged.
/// - `track`: Apply per-track gain (`replayGainTrack`); falls back to album gain if absent.
/// - `album`: Apply album-level gain (`replayGainAlbum`); falls back to track gain if absent.
enum ReplayGainMode: String, CaseIterable, Codable {
    case off
    case track
    case album
}
