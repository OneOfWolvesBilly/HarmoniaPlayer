//
//  EQSchemaMigrator.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Forward migration of EQ persistence between schema versions.
//  9-K ships only schema version 1; the migrator therefore contains
//  only the version-1 identity case. Future slices (e.g. v0.15
//  per-track EQ, v0.15/v0.2 user-adjustable Q) bump the version
//  and add migration steps here.
//

import Foundation

nonisolated enum EQSchemaMigrator {

    /// Migrate persisted EQ state from `fromVersion` to `toVersion`.
    /// 9-K only supports `1 → 1` (identity); future versions add
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

        // No other version branches exist in 9-K.
        // Falling through means the persisted state is from an
        // unsupported version; surface a safe default rather than
        // silently corrupt the caller's state.
        return .defaults
    }
}
