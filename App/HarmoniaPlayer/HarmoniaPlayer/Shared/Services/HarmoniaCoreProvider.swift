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
//    import HarmoniaCore together with HarmoniaPlaybackServiceAdapter and
//    HarmoniaTagReaderAdapter.
//  - All platform-specific adapter construction is contained here.
//    Every other layer depends only on the HarmoniaPlayer service protocols.
//  - Free vs Pro decoder selection is reserved for future Pro-tier work.
//    The isProUser flag is forwarded to support that future extension point,
//    but the current implementation uses the same AVFoundation adapter for both.
//
//  SLICE 9-K (commit 5) — sharedCore cache rationale
//  -------------------------------------------------
//  `makePlaybackService(isProUser:)` and `makeEQService()` must operate on
//  the SAME underlying HarmoniaCore.PlaybackService instance: the EQ node
//  that DefaultPlaybackService inserts into the audio chain at construction
//  time is the node that the EQ control surface
//  (setEQEnabled / setEQPreamp / setEQBandGains) mutates. If the two factory
//  methods returned services backed by different cores, EQ slider movements
//  would have no audible effect.
//
//  The `sharedCore` optional caches the first core built by either factory
//  method and lets the other reuse it. `makeEQService` binds three closures
//  capturing this shared core and returns a `HarmoniaEQAdapter` — keeping
//  HarmoniaCore types out of the EQ adapter itself (closure-binding pattern,
//  see HarmoniaEQAdapter.swift for the rationale and module-boundary
//  consequences).
//

import Foundation
import HarmoniaCore

/// Constructs real HarmoniaCore-Swift service graphs for production use.
///
/// `HarmoniaCoreProvider` is the sole Integration Layer class that knows how
/// to assemble platform adapters into fully functional services. The rest of
/// the application depends only on the `PlaybackService`, `TagReaderService`,
/// `LyricsService`, and `EQService` protocol abstractions, never on
/// HarmoniaCore types directly.
final class HarmoniaCoreProvider: CoreServiceProviding {

    // MARK: - Private State

    /// Cached HarmoniaCore.PlaybackService instance shared by
    /// `makePlaybackService(isProUser:)` and `makeEQService()`. Set on the
    /// first call to either factory method, reused thereafter so EQ control
    /// acts on the same audio chain that playback runs through.
    private var sharedCore: HarmoniaCore.PlaybackService?

    // MARK: - CoreServiceProviding

    /// Creates a fully wired `PlaybackService` backed by real HarmoniaCore adapters.
    ///
    /// The service graph assembled here:
    /// ```
    /// OSLogAdapter          → LoggerPort
    /// MonotonicTimeAdapter → MonotonicTimePort
    /// AVAssetReaderDecoderAdapter (logger:) → DecoderPort
    /// AVAudioEngineOutputAdapter  (logger:) → AudioOutputPort
    /// AVAudioUnitEQAdapter                  → EQPort
    ///         ↓
    /// DefaultPlaybackService(decoder:audio:time:logger:eq:)   ← cached as sharedCore
    ///         ↓
    /// HarmoniaPlaybackServiceAdapter     ← returned as PlaybackService
    /// ```
    ///
    /// - Parameter isProUser: Reserved for future Pro-tier decoder selection.
    ///   Currently the same adapter is used for both Free and Pro tiers.
    /// - Returns: A `PlaybackService` backed by real Apple AVFoundation adapters.
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        let core = buildCore()
        self.sharedCore = core
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

    /// Creates an `EQService` bound to the shared HarmoniaCore.PlaybackService
    /// EQ control surface via closure binding.
    ///
    /// If `makePlaybackService(isProUser:)` has not yet been called the core
    /// is lazily built so call ordering is not part of the factory contract.
    /// In normal AppState wiring `makePlaybackService` runs first, then
    /// `makeEQService` reuses the cached core.
    ///
    /// The three closures capture `core` strongly. There is no retain cycle
    /// because `core` is a HarmoniaCore type that has no knowledge of
    /// HarmoniaEQAdapter; the adapter retains the closures, the closures
    /// retain the core, and the core retains nothing back. The closures
    /// inherit MainActor isolation from this enclosing function and only
    /// run on the MainActor, so capturing the non-Sendable core does not
    /// raise a Sendable warning.
    ///
    /// - Returns: A `HarmoniaEQAdapter` forwarding setEnabled / setPreamp /
    ///   setBandGains to the cached core's EQ control surface.
    func makeEQService() -> EQService {
        let core = sharedCore ?? buildCore()
        self.sharedCore = core
        return HarmoniaEQAdapter(
            setEnabled:   { core.setEQEnabled($0)   },
            setPreamp:    { core.setEQPreamp($0)    },
            setBandGains: { core.setEQBandGains($0) }
        )
    }

    /// Construct the production `NowPlayingService`.
    ///
    /// `MPNowPlayingAdapter` owns interactions with
    /// `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. It is
    /// the single point in HarmoniaPlayer that imports
    /// `MediaPlayer.framework`.
    ///
    /// Tests do not hit this branch — they construct AppState with
    /// `FakeCoreProvider`, which returns the injected
    /// `nowPlayingServiceStub`.
    func makeNowPlayingService() -> NowPlayingService {
        return MPNowPlayingAdapter()
    }

    // MARK: - Helpers

    /// Builds a fresh HarmoniaCore.PlaybackService graph with all adapters wired.
    ///
    /// Extracted as a helper so `makePlaybackService` and `makeEQService` can
    /// share construction logic; either call site falls through here on the
    /// first invocation, then `sharedCore` short-circuits subsequent calls.
    private func buildCore() -> HarmoniaCore.PlaybackService {
        let logger  = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "Playback")
        let time    = MonotonicTimeAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let eq      = AVAudioUnitEQAdapter()
        // The same EQ instance is handed to BOTH the audio output
        // adapter (which splices its node into the real signal chain
        // during configure) AND DefaultPlaybackService (which forwards
        // the EQ control surface). Sharing a single instance is what
        // makes setEQEnabled/Preamp/BandGains audible.
        let audio   = AVAudioEngineOutputAdapter(logger: logger, eq: eq)
        return DefaultPlaybackService(
            decoder: decoder,
            audio:   audio,
            time:    time,
            logger:  logger,
            eq:      eq
        )
    }
}
