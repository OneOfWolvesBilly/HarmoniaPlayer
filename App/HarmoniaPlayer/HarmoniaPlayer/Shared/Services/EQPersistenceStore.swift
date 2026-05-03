//
//  EQPersistenceStore.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  UserDefaults-backed persistence for EQ state (enabled / preamp /
//  band gains / current preset name / custom presets) with explicit
//  schema versioning so future slices can migrate forward without
//  losing user data.
//
//  KEY LAYOUT
//  ----------
//  - hp.eq.schemaVersion:     Int    (9-K = 1)
//  - hp.eq.enabled:           Bool
//  - hp.eq.preamp:            Float (dB)
//  - hp.eq.bands:             Data  (JSON [Float], 10 elements)
//  - hp.eq.currentPresetName: String?  (nil = unsaved/custom)
//  - hp.eq.customPresets:     Data  (JSON [EQPreset])
//
//  Save semantics: writes all keys atomically (UserDefaults batches
//  internally) and stamps the current schema version. Load semantics:
//  if no schema version is present, the store is a fresh install →
//  initialise version to 1 and return defaults; if a version is
//  present, decode and run migration via `EQSchemaMigrator` to lift
//  to the current version.
//

import Foundation

/// Snapshot of all EQ state persisted to UserDefaults.
struct EQPersistedState: Codable, nonisolated Equatable, Sendable {
    var isEnabled: Bool
    var preamp: Float
    var bandGains: [Float]
    var currentPresetName: String?
    var customPresets: [EQPreset]

    /// Default state used on fresh install or when nothing has been
    /// persisted yet.
    nonisolated static let defaults = EQPersistedState(
        isEnabled: false,
        preamp: 0,
        bandGains: Array(repeating: 0, count: 10),
        currentPresetName: nil,
        customPresets: []
    )
}

/// Current schema version this build of HarmoniaPlayer writes.
nonisolated let eqCurrentSchemaVersion = 1

private nonisolated enum EQDefaultsKey {
    static let schemaVersion     = "hp.eq.schemaVersion"
    static let isEnabled         = "hp.eq.enabled"
    static let preamp            = "hp.eq.preamp"
    static let bands             = "hp.eq.bands"
    static let currentPresetName = "hp.eq.currentPresetName"
    static let customPresets     = "hp.eq.customPresets"
}

nonisolated final class EQPersistenceStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Persist the given state. Writes the current schema version
    /// alongside.
    func save(_ state: EQPersistedState) {
        defaults.set(eqCurrentSchemaVersion, forKey: EQDefaultsKey.schemaVersion)
        defaults.set(state.isEnabled,        forKey: EQDefaultsKey.isEnabled)
        defaults.set(state.preamp,           forKey: EQDefaultsKey.preamp)

        let encoder = JSONEncoder()
        if let bandsData = try? encoder.encode(state.bandGains) {
            defaults.set(bandsData, forKey: EQDefaultsKey.bands)
        }
        if let customData = try? encoder.encode(state.customPresets) {
            defaults.set(customData, forKey: EQDefaultsKey.customPresets)
        }

        if let name = state.currentPresetName {
            defaults.set(name, forKey: EQDefaultsKey.currentPresetName)
        } else {
            defaults.removeObject(forKey: EQDefaultsKey.currentPresetName)
        }
    }

    /// Load persisted state. On fresh install, stamps the current
    /// schema version and returns `EQPersistedState.defaults`.
    /// Otherwise decodes the persisted state and migrates it via
    /// `EQSchemaMigrator` to the current version.
    func load() -> EQPersistedState {
        guard let storedVersion = readSchemaVersion() else {
            // Fresh install: initialise schema version, return defaults.
            defaults.set(eqCurrentSchemaVersion, forKey: EQDefaultsKey.schemaVersion)
            return .defaults
        }

        let decoded = readState()
        return EQSchemaMigrator.migrate(
            from: storedVersion,
            to: eqCurrentSchemaVersion,
            state: decoded
        )
    }

    /// Returns the schema version currently written to UserDefaults,
    /// or `nil` if none has been written yet (fresh install).
    func currentSchemaVersion() -> Int? {
        return readSchemaVersion()
    }

    // MARK: - Private helpers

    private func readSchemaVersion() -> Int? {
        // UserDefaults.integer returns 0 for missing keys; distinguish
        // "missing" from "explicitly 0" via object(forKey:).
        guard defaults.object(forKey: EQDefaultsKey.schemaVersion) != nil else {
            return nil
        }
        return defaults.integer(forKey: EQDefaultsKey.schemaVersion)
    }

    private func readState() -> EQPersistedState {
        var state = EQPersistedState.defaults

        if defaults.object(forKey: EQDefaultsKey.isEnabled) != nil {
            state.isEnabled = defaults.bool(forKey: EQDefaultsKey.isEnabled)
        }
        if defaults.object(forKey: EQDefaultsKey.preamp) != nil {
            state.preamp = defaults.float(forKey: EQDefaultsKey.preamp)
        }
        if let bandsData = defaults.data(forKey: EQDefaultsKey.bands),
           let bands = try? JSONDecoder().decode([Float].self, from: bandsData) {
            state.bandGains = bands
        }
        state.currentPresetName = defaults.string(forKey: EQDefaultsKey.currentPresetName)

        if let customData = defaults.data(forKey: EQDefaultsKey.customPresets),
           let customs = try? JSONDecoder().decode([EQPreset].self, from: customData) {
            state.customPresets = customs
        }

        return state
    }
}
