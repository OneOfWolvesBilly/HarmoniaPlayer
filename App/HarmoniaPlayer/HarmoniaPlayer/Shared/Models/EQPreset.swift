//
//  EQPreset.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE
//  -------
//  A named EQ configuration. Built-in presets are defined statically
//  in `EQPresets.builtin` and have `isBuiltin = true`; user-saved
//  presets are persisted via `EQPersistenceStore` with
//  `isBuiltin = false`.
//

import Foundation

/// A named EQ configuration: 10 band states + preamp.
struct EQPreset: Codable, nonisolated Equatable, Sendable, Identifiable {

    /// Display name. Used as identity; built-in names are reserved
    /// (custom presets cannot reuse them).
    let name: String

    /// Per-band state, exactly 10 entries ordered low → high.
    let bands: [EQBandState]

    /// Preamp gain in dB. Range ±12 dB.
    let preamp: Float

    /// `true` for built-in presets, `false` for user-saved.
    let isBuiltin: Bool

    var id: String { name }
}
