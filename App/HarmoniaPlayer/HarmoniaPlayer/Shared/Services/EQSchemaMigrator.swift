//
//  EQSchemaMigrator.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Forward migration of EQ persistence between schema versions.
//  Schema version 1 is the only version that exists; the migrator
//  therefore contains only the version-1 identity case. New schema
//  versions bump the version and add migration steps here.
//

import Foundation

nonisolated enum EQSchemaMigrator {

    /// Migrate persisted EQ state from `fromVersion` to `toVersion`.
    /// Only `1 → 1` (identity) is supported; new versions add
    /// branches that lift the state forward step by step.
    static func migrate(
        from fromVersion: Int,
        to toVersion: Int,
        state: EQPersistedState
    ) -> EQPersistedState {
        if fromVersion == toVersion {
            // No-op: state is already at the target version.
            return state
        }

        // No other version branches exist.
        // Falling through means the persisted state is from an
        // unsupported version; surface a safe default rather than
        // silently corrupt the caller's state.
        return .defaults
    }
}
