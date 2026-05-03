//
//  HarmoniaEQAdapter.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Bridges the HarmoniaCore PlaybackService EQ control surface
//  (setEQEnabled / setEQPreamp / setEQBandGains) to the Application Layer
//  EQService protocol via closure binding.
//
//  DESIGN NOTES
//  ------------
//  - This file lives in Shared/Services alongside HarmoniaPlaybackServiceAdapter
//    and HarmoniaTagReaderAdapter, but unlike those two it does NOT
//    `import HarmoniaCore`. The closure-binding mechanism keeps the Core type
//    surface confined to HarmoniaCoreProvider where binding actually happens.
//  - Two consequences:
//    (a) The total HarmoniaCore import surface in HarmoniaPlayer stays at
//        three production files (HarmoniaCoreProvider /
//        HarmoniaPlaybackServiceAdapter / HarmoniaTagReaderAdapter), matching
//        module_boundary.md Section 3.2 rule 2.
//    (b) EQServiceTests verify forward semantics without importing
//        HarmoniaCore — IntegrationTests.swift line 28 forbids HarmoniaCore
//        in tests; this adapter side-steps that constraint by design.
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - No actor annotation: relies on the main module's MainActor inference,
//    matching HarmoniaPlaybackServiceAdapter / HarmoniaTagReaderAdapter
//    (also unannotated final classes in the Integration Layer).
//  - No `deinit` body: avoids the Xcode 26 beta
//    `swift_task_deinitOnExecutorImpl` TaskLocal teardown crash that bites
//    @MainActor classes with explicit deinit. Compiler-synthesised deinit
//    walks the fast path.
//  - Stored closure types are plain `(Bool) -> Void` / `(Float) -> Void` /
//    `([Float]) -> Void`. NOT @Sendable. They inherit MainActor isolation
//    from their construction site (HarmoniaCoreProvider.makeEQService) and
//    capture the non-Sendable HarmoniaCore.PlaybackService without crossing
//    an isolation boundary, so no Sendable warning is emitted.
//

import Foundation

/// Bridges the synchronous HarmoniaCore PlaybackService EQ control surface
/// to the `EQService` Application Layer protocol via three closure hooks.
///
/// The hooks are bound at construction time by `HarmoniaCoreProvider`. This
/// adapter therefore has no knowledge of HarmoniaCore types and can be unit
/// tested without crossing the module boundary.
final class HarmoniaEQAdapter: EQService {

    // MARK: - Stored Closures

    private let setEnabledHook:   (Bool)    -> Void
    private let setPreampHook:    (Float)   -> Void
    private let setBandGainsHook: ([Float]) -> Void

    // MARK: - Initialization

    /// Creates an adapter bound to three closure hooks.
    ///
    /// In production these closures are supplied by `HarmoniaCoreProvider`
    /// and forward to `HarmoniaCore.PlaybackService.setEQEnabled` /
    /// `setEQPreamp` / `setEQBandGains` respectively. In tests they capture
    /// observation variables so forward semantics can be verified without
    /// importing HarmoniaCore.
    init(
        setEnabled:   @escaping (Bool)    -> Void,
        setPreamp:    @escaping (Float)   -> Void,
        setBandGains: @escaping ([Float]) -> Void
    ) {
        self.setEnabledHook   = setEnabled
        self.setPreampHook    = setPreamp
        self.setBandGainsHook = setBandGains
    }

    // MARK: - EQService

    func setEnabled(_ enabled: Bool)    { setEnabledHook(enabled) }

    func setPreamp(_ db: Float)         { setPreampHook(db) }

    func setBandGains(_ gains: [Float]) { setBandGainsHook(gains) }
}
