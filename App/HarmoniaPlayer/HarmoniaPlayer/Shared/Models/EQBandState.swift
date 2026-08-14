//
//  EQBandState.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE
//  -------
//  Mutable per-band state stored in presets and in EQCoordinator's
//  live `bandGains`. The `q` field is included for forward
//  compatibility with variable-Q designs; all bands currently
//  share a single Q (0.7071) and `q` is informational only.
//

import Foundation

/// Editable state of one EQ band.
struct EQBandState: Codable, nonisolated Equatable, Sendable {

    /// Band gain in dB. Range enforced by EQCoordinator: ±12 dB.
    var gain: Float

    /// Band Q factor. A fixed Q is used across all bands (0.7071);
    /// stored here for forward compatibility.
    var q: Float
}
