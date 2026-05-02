//
//  EQPresets.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE
//  -------
//  Built-in EQ presets. Defined statically as Swift constants
//  (per spec §9-K Built-in Presets). 8 presets in 9-K:
//  Flat, Rock, Pop, Jazz, Classical, Vocal, Bass Boost, Treble Boost.
//
//  All band gains are within ±12 dB. Preamp is 0 dB for every
//  built-in preset (users adjust preamp manually). Each band uses the
//  fixed Q = 0.7071 from spec §9-K.
//
//  Band order (low → high):
//    [0] 32 Hz   [1] 64 Hz   [2] 125 Hz  [3] 250 Hz  [4] 500 Hz
//    [5] 1 kHz   [6] 2 kHz   [7] 4 kHz   [8] 8 kHz   [9] 16 kHz
//

import Foundation

enum EQPresets {

    /// Fixed Q factor across all bands in 9-K (Butterworth).
    private static let q: Float = 0.7071

    /// Builds an EQBandState array from a 10-element gain array.
    private static func bands(_ gains: [Float]) -> [EQBandState] {
        precondition(gains.count == 10, "EQ presets must have 10 bands")
        return gains.map { EQBandState(gain: $0, q: q) }
    }

    /// Built-in presets in display order.
    static let builtin: [EQPreset] = [
        EQPreset(
            name: "Flat",
            bands: bands([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Rock",
            // Boost low + high, scoop mid.
            bands: bands([5, 4, 3, 0, -2, -3, -2, 0, 3, 4]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Pop",
            // Bright vocals: boost upper-mid + presence, gentle bass lift.
            bands: bands([2, 2, 0, -1, -1, 1, 3, 3, 2, 1]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Jazz",
            // Warm low/low-mid, soft scoop in upper-mid.
            bands: bands([3, 3, 2, 1, 0, 0, -1, -1, 1, 2]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Classical",
            // Smooth, gentle high lift to enhance air without harshness.
            bands: bands([3, 3, 2, 1, 0, 0, 0, 1, 2, 3]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Vocal",
            // Cut bass, lift presence band to bring vocals forward.
            bands: bands([-2, -1, 0, 2, 4, 4, 3, 2, 0, -1]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Bass Boost",
            // Lift the bottom three bands, taper to 0 by the mids.
            bands: bands([6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
            preamp: 0,
            isBuiltin: true
        ),
        EQPreset(
            name: "Treble Boost",
            // Mirror image of Bass Boost: lift top three bands.
            bands: bands([0, 0, 0, 0, 0, 0, 2, 4, 5, 6]),
            preamp: 0,
            isBuiltin: true
        ),
    ]
}
