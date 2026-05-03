//
//  EQService.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Application Layer abstraction over the HarmoniaCore EQ control surface.
//  AppState (and EQCoordinator in Slice 9-K commit 6) depend solely on this
//  protocol so they never need to know about HarmoniaCore types.
//
//  DESIGN NOTES
//  ------------
//  - No HarmoniaCore import — pure Application Layer.
//  - All three methods are synchronous and non-throwing, mirroring the
//    HarmoniaCore PlaybackService EQ control surface (setEQEnabled /
//    setEQPreamp / setEQBandGains) which the closure-binding
//    HarmoniaEQAdapter forwards to.
//  - Clamping (±12 dB band, ±12 dB preamp) is performed downstream by the
//    AVAudioUnitEQAdapter; this protocol promises no clamping itself.
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - No actor annotation: relies on the main module's
//    SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor inference, matching every
//    other service protocol in this folder (PlaybackService, TagReaderService,
//    LyricsService, FileOriginService, IAPManager, LyricsPreferenceStore,
//    CoreServiceProviding).
//

import Foundation

/// Application Layer interface for controlling the equaliser.
///
/// Implementations bridge to the underlying HarmoniaCore PlaybackService EQ
/// control surface. The Application Layer never sees HarmoniaCore types
/// directly — all bridging happens in the Integration Layer
/// (`HarmoniaEQAdapter`).
protocol EQService: AnyObject {

    /// Enables or disables the equaliser.
    /// When disabled the audio chain bypasses the EQ node entirely.
    func setEnabled(_ enabled: Bool)

    /// Sets the EQ preamp gain in dB.
    /// Out-of-range values are clamped (±12 dB) downstream.
    func setPreamp(_ db: Float)

    /// Sets per-band EQ gains in dB.
    /// Length must match the implementation's band count (Slice 9-K: 10).
    /// Out-of-range values are clamped (±12 dB per band) downstream.
    func setBandGains(_ gains: [Float])
}
