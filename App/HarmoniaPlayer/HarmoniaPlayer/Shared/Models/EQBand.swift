//
//  EQBand.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE
//  -------
//  Application Layer representation of one EQ band's static
//  configuration: its centre frequency and the default gain used when
//  the EQ is reset to flat. Bands are immutable; user-editable state
//  lives in `EQBandState`.
//

import Foundation

/// One band of the 10-band graphic EQ.
struct EQBand: Codable, Equatable, Sendable {

    /// Centre frequency in Hz.
    let frequency: Float

    /// Default gain in dB applied when the EQ is reset to flat (0).
    let defaultGain: Float
}
