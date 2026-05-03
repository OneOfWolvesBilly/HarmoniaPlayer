//
//  EQCoordinator.swift
//  HarmoniaPlayer / Shared / Models
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  @MainActor ObservableObject that owns all EQ-related observable
//  state for the UI layer. Coordinates between two boundaries:
//
//    - EQService           — the Application Layer's view of the
//                            HarmoniaCore EQ control surface
//                            (setEnabled / setPreamp / setBandGains)
//    - EQPersistenceStore  — UserDefaults persistence for the live
//                            EQ state and user-saved custom presets
//
//  Lives in `Shared/Models/` (not `Services/`) for the same reason
//  AppState lives there — it is a state-bearing observable object,
//  not a stateless service.
//
//  SCOPE
//  -----
//  AppState holds a single `let eqCoordinator: EQCoordinator`
//  reference; views use `appState.eqCoordinator.…`. AppState itself
//  has no EQ-specific @Published properties or methods (spec §9-K
//  commit 6).
//
//  CUSTOM-STATE SEMANTICS
//  ----------------------
//  `currentPresetName` is `nil` whenever the live state does not
//  match any saved preset. The spec TDD matrix only asserts band
//  modification clears it (`testEQCoordinator_ModifyBand_MarksAsCustomState`),
//  but a preset is defined by `bands + preamp` together (`EQPreset`),
//  so any preamp change also clears the name. Documented here as a
//  conservative, consistent reading of the EQPreset model.
//
//  SWIFT 6 / XCODE 26 NOTES
//  ------------------------
//  - `@MainActor` annotation is implicit via the main module's
//    SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; explicit annotation
//    kept for documentation parity with AppState.
//  - Explicit `nonisolated deinit { }`: the synthesised deinit on an
//    inferred-MainActor class routes deallocation through
//    `swift_task_deinitOnExecutorImpl`, which crashes in Xcode 26 beta
//    (TaskLocal::StopLookupScope teardown double-free). This is the same
//    workaround applied to HarmoniaEQAdapter and FakeEQService. Methods
//    stay on MainActor; only deinit drops down to the synchronous ARC
//    path. Earlier comments in this file (and in HarmoniaEQAdapter)
//    claimed "no explicit deinit body avoids the bug" — that was wrong:
//    the compiler-synthesised deinit on a MainActor class still fires.
//  - This is a stateful @MainActor ObservableObject (NOT a stateless
//    utility class / enum / static let), so the
//    "stateless → nonisolated" rule from
//    EQPersistenceStore / EQSchemaMigrator does NOT apply to the whole
//    class — only to the deinit.
//

import Foundation
import Combine

// MARK: - Errors

enum EQCoordinatorError: Error {
    /// Attempted to save a custom preset with a name that collides
    /// with a built-in preset (e.g. "Rock", "Flat").
    case nameCollidesWithBuiltin
}

// MARK: - Coordinator

@MainActor
final class EQCoordinator: ObservableObject {

    // MARK: Published state

    /// Whether the EQ node is active. When `false` the audio chain
    /// bypasses the EQ entirely regardless of band gains or preamp.
    @Published private(set) var isEnabled: Bool

    /// 10 per-band gains in dB, ordered low → high
    /// (32 / 64 / 125 / 250 / 500 / 1k / 2k / 4k / 8k / 16k Hz).
    /// Range ±12 dB; values outside are clamped on assignment.
    @Published private(set) var bandGains: [Float]

    /// EQ preamp gain in dB. Range ±12 dB; values outside are
    /// clamped on assignment.
    @Published private(set) var preamp: Float

    /// Name of the saved preset whose bands+preamp the live state
    /// currently matches; `nil` when the state has been edited away
    /// from any saved preset.
    @Published private(set) var currentPresetName: String?

    /// User-saved custom presets. Built-in presets live separately
    /// in `EQPresets.builtin`.
    @Published private(set) var customPresets: [EQPreset]

    // MARK: Dependencies

    private let service: EQService
    private let store: EQPersistenceStore

    /// Per-band gain clamp limit (dB). Mirrors AVAudioUnitEQAdapter's
    /// downstream clamp, applied here so coordinator state and
    /// service state agree on what was stored.
    private static let clampLimit: Float = 12

    // MARK: - Init

    init(service: EQService, store: EQPersistenceStore) {
        self.service = service
        self.store = store

        let state = store.load()
        self.isEnabled = state.isEnabled
        self.bandGains = state.bandGains
        self.preamp = state.preamp
        self.currentPresetName = state.currentPresetName
        self.customPresets = state.customPresets

        // Push the loaded state to the service so the audio chain
        // matches the coordinator's published state from t=0.
        service.setEnabled(state.isEnabled)
        service.setPreamp(state.preamp)
        service.setBandGains(state.bandGains)
    }

    // MARK: - Mutators

    /// Enables or disables the EQ. When disabled the audio chain
    /// bypasses the EQ node — band and preamp values are retained
    /// but not audible.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        service.setEnabled(enabled)
        persist()
    }

    /// Updates a single band's gain. Clears `currentPresetName`
    /// because the live state is now custom.
    func setBand(index: Int, gain: Float) {
        guard bandGains.indices.contains(index) else { return }
        bandGains[index] = clamp(gain)
        currentPresetName = nil
        service.setBandGains(bandGains)
        persist()
    }

    /// Updates the preamp gain. Clears `currentPresetName` because
    /// `EQPreset` defines a preset as bands + preamp together — any
    /// preamp change makes the live state diverge from the saved
    /// preset (see CUSTOM-STATE SEMANTICS in the file header).
    func setPreamp(_ db: Float) {
        preamp = clamp(db)
        currentPresetName = nil
        service.setPreamp(preamp)
        persist()
    }

    /// Loads the named preset (built-in or custom) into the live
    /// state. Sets `currentPresetName` to the preset's name so the
    /// UI picker reflects the selection. No-op if no preset matches.
    func selectPreset(_ name: String) {
        guard let preset = preset(named: name) else { return }
        bandGains = preset.bands.map { clamp($0.gain) }
        preamp = clamp(preset.preamp)
        currentPresetName = name
        service.setBandGains(bandGains)
        service.setPreamp(preamp)
        persist()
    }

    /// Saves the current live state as a new custom preset.
    /// Throws `.nameCollidesWithBuiltin` if `name` matches a
    /// built-in preset name.
    func saveAsCustomPreset(name: String) throws {
        guard !EQPresets.builtin.contains(where: { $0.name == name }) else {
            throw EQCoordinatorError.nameCollidesWithBuiltin
        }
        let bands = bandGains.map { EQBandState(gain: $0, q: 0.7071) }
        let preset = EQPreset(name: name, bands: bands, preamp: preamp, isBuiltin: false)

        // Replace if a custom preset with the same name already exists.
        customPresets.removeAll { $0.name == name }
        customPresets.append(preset)
        currentPresetName = name
        persist()
    }

    /// Removes the named custom preset. Built-in names are silently
    /// rejected — the built-in list is immutable from the user's
    /// perspective.
    func deleteCustomPreset(_ name: String) {
        guard !EQPresets.builtin.contains(where: { $0.name == name }) else { return }
        customPresets.removeAll { $0.name == name }
        if currentPresetName == name {
            currentPresetName = nil
        }
        persist()
    }

    // MARK: - Helpers

    private func clamp(_ value: Float) -> Float {
        min(Self.clampLimit, max(-Self.clampLimit, value))
    }

    private func preset(named name: String) -> EQPreset? {
        if let builtin = EQPresets.builtin.first(where: { $0.name == name }) {
            return builtin
        }
        return customPresets.first(where: { $0.name == name })
    }

    private func persist() {
        store.save(EQPersistedState(
            isEnabled: isEnabled,
            preamp: preamp,
            bandGains: bandGains,
            currentPresetName: currentPresetName,
            customPresets: customPresets
        ))
    }

    // MARK: - Deinit (Xcode 26 beta workaround)

    /// Forces deallocation through the synchronous ARC path, bypassing
    /// `swift_task_deinitOnExecutorImpl`. See file header SWIFT 6 /
    /// XCODE 26 NOTES for full rationale.
    nonisolated deinit { }
}
