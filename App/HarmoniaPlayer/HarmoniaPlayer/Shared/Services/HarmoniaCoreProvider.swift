//
//  HarmoniaCoreProvider.swift
//  HarmoniaPlayer / Shared / Services
//
//  Created on 2026-02-15.
//
//  PURPOSE
//  -------
//  Constructs real HarmoniaCore-Swift service graphs for production use.
//
//  DESIGN NOTES
//  ------------
//  - This is the Integration Layer entry point and the ONLY class that may
//    import HarmoniaCore together with the two adapter files.
//  - All platform-specific adapter construction is contained here.
//    Every other layer depends only on the HarmoniaPlayer service protocols.
//  - Free vs Pro decoder selection is reserved for future Pro-tier work.
//    The isProUser flag is forwarded to support that future extension point,
//    but the current implementation uses the same AVFoundation adapter for both.
//

import Foundation
import HarmoniaCore

/// Constructs real HarmoniaCore-Swift service graphs for production use.
///
/// `HarmoniaCoreProvider` is the sole Integration Layer class that knows how
/// to assemble platform adapters into fully functional services. The rest of
/// the application depends only on the `PlaybackService` and `TagReaderService`
/// protocol abstractions, never on HarmoniaCore types directly.
final class HarmoniaCoreProvider: CoreServiceProviding {

    // MARK: - CoreServiceProviding

    /// Creates a fully wired `PlaybackService` backed by real HarmoniaCore adapters.
    ///
    /// The service graph assembled here:
    /// ```
    /// OSLogAdapter          → LoggerPort
    /// MonotonicClockAdapter → ClockPort
    /// AVAssetReaderDecoderAdapter (logger:) → DecoderPort
    /// AVAudioEngineOutputAdapter  (logger:) → AudioOutputPort
    ///         ↓
    /// DefaultPlaybackService(decoder:audio:clock:logger:)
    ///         ↓
    /// HarmoniaPlaybackServiceAdapter     ← returned as PlaybackService
    /// ```
    ///
    /// - Parameter isProUser: Reserved for future Pro-tier decoder selection.
    ///   Currently the same adapter is used for both Free and Pro tiers.
    /// - Returns: A `PlaybackService` backed by real Apple AVFoundation adapters.
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        let logger  = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "Playback")
        let clock   = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let audio   = AVAudioEngineOutputAdapter(logger: logger)
        let core    = DefaultPlaybackService(
            decoder: decoder,
            audio:   audio,
            clock:   clock,
            logger:  logger
        )
        return HarmoniaPlaybackServiceAdapter(core: core)
    }

    /// Creates a `TagReaderService` backed by the real AVFoundation metadata adapter.
    ///
    /// The service graph assembled here:
    /// ```
    /// AVMetadataTagReaderAdapter → TagReaderPort
    ///         ↓
    /// HarmoniaTagReaderAdapter   ← returned as TagReaderService
    /// ```
    ///
    /// - Returns: A `TagReaderService` that reads ID3/MP4/common metadata via AVFoundation.
    func makeTagReaderService() -> TagReaderService {
        HarmoniaTagReaderAdapter(port: AVMetadataTagReaderAdapter())
    }

    /// Creates a `LyricsService` (Application Layer) for USLT + sidecar `.lrc`
    /// resolution.
    ///
    /// `LyricsService` is a pure Application Layer service that does not
    /// depend on HarmoniaCore — but its construction belongs here so that
    /// `CoreFactory` remains the single composition root for all services.
    ///
    /// - Returns: A `DefaultLyricsService` with system locale defaults.
    func makeLyricsService() -> LyricsService {
        DefaultLyricsService()
    }
}
