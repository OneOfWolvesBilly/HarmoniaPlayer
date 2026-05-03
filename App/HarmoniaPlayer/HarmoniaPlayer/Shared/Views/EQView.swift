//
//  EQView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  10-band graphic equaliser UI for Slice 9-K. Driven entirely by the
//  injected `EQCoordinator`; this view holds no EQ state of its own
//  apart from transient sheet-presentation flags.
//
//  LAYOUT
//  ------
//  Top row:    [ Enable toggle ] [ Preset picker ▾ ] [ Save… ] [ Delete ]
//  Slider row: [ Preamp ] | [ 32 Hz ] [ 64 Hz ] ... [ 16 kHz ]
//
//  Sliders are vertical (rotation-based — SwiftUI for macOS has no
//  native vertical slider). Range ±12 dB, step 0.5 dB. The slider
//  binding routes through coordinator setters so clamping, persistence,
//  and EQService forward all happen on every drag.
//
//  DESIGN NOTES
//  ------------
//  - No HarmoniaCore import — pure UI layer.
//  - L() helper mirrors HarmoniaPlayerCommands convention so runtime
//    language switching works via `appState.languageBundle`.
//  - Save / Delete enabled state derives from coordinator state:
//    Save is always enabled (rejection handled on submit);
//    Delete is enabled only when the current preset name is non-nil
//    AND not a built-in name (i.e. it's a user-saved custom preset).
//  - Picker selection uses an Optional<String> binding. Built-in and
//    custom presets are tagged with their names; a "—" sentinel is
//    rendered ONLY when `currentPresetName == nil` so it appears in
//    the picker exactly when the live state is custom (edited away
//    from any saved preset).
//

import SwiftUI

struct EQView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject var coordinator: EQCoordinator

    // Save dialog and collision alert presentation flags
    @State private var showingSaveSheet = false
    @State private var saveDraftName = ""
    @State private var showingNameCollisionAlert = false

    // MARK: - Localisation

    private var bundle: Bundle { appState.languageBundle }

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    // MARK: - Band frequency labels (low → high)

    private static let bandLabelKeys: [String] = [
        "eq_band_label_32hz",  "eq_band_label_64hz",   "eq_band_label_125hz",
        "eq_band_label_250hz", "eq_band_label_500hz",  "eq_band_label_1khz",
        "eq_band_label_2khz",  "eq_band_label_4khz",   "eq_band_label_8khz",
        "eq_band_label_16khz",
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            controlsRow
            Divider()
            slidersRow
        }
        .padding()
        .sheet(isPresented: $showingSaveSheet) { saveSheet }
        .alert(L("eq_preset_name_collision_alert"),
               isPresented: $showingNameCollisionAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: 12) {
            Toggle(L("eq_enabled_toggle"), isOn: enabledBinding)
                .toggleStyle(.switch)

            Spacer()

            presetPicker

            Button(L("eq_preset_save_button")) {
                saveDraftName = ""
                showingSaveSheet = true
            }

            Button(L("eq_preset_delete_button")) {
                if let name = coordinator.currentPresetName {
                    coordinator.deleteCustomPreset(name)
                }
            }
            .disabled(!isCurrentPresetDeletable)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isEnabled },
            set: { coordinator.setEnabled($0) }
        )
    }

    private var presetPicker: some View {
        Picker(L("eq_preset_picker_label"), selection: presetPickerBinding) {
            // Built-in presets
            Section {
                ForEach(EQPresets.builtin) { preset in
                    Text(localisedBuiltinName(preset.name))
                        .tag(Optional(preset.name))
                }
            }
            // Custom presets (only render section if any exist)
            if !coordinator.customPresets.isEmpty {
                Section {
                    ForEach(coordinator.customPresets) { preset in
                        Text(preset.name).tag(Optional(preset.name))
                    }
                }
            }
            // Custom-state sentinel — only shown when state is unsaved
            if coordinator.currentPresetName == nil {
                Text("—").tag(Optional<String>.none)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 180)
    }

    /// Two-way binding that routes selection through `selectPreset`.
    /// Selecting `nil` (the "—" sentinel) is a no-op so user edits are
    /// preserved if the picker happens to commit a nil selection.
    private var presetPickerBinding: Binding<String?> {
        Binding(
            get: { coordinator.currentPresetName },
            set: { newValue in
                if let name = newValue {
                    coordinator.selectPreset(name)
                }
            }
        )
    }

    private var isCurrentPresetDeletable: Bool {
        guard let name = coordinator.currentPresetName else { return false }
        return !EQPresets.builtin.contains(where: { $0.name == name })
    }

    // MARK: - Sliders Row

    private var slidersRow: some View {
        HStack(alignment: .top, spacing: 12) {
            preampSlider
            Divider().frame(height: 220)
            ForEach(0..<10, id: \.self) { index in
                bandSlider(at: index)
            }
        }
    }

    private var preampSlider: some View {
        sliderColumn(
            label: L("eq_preamp_label"),
            value: Binding(
                get: { coordinator.preamp },
                set: { coordinator.setPreamp($0) }
            )
        )
    }

    private func bandSlider(at index: Int) -> some View {
        sliderColumn(
            label: L(Self.bandLabelKeys[index]),
            value: Binding(
                get: { coordinator.bandGains[index] },
                set: { coordinator.setBand(index: index, gain: $0) }
            )
        )
    }

    /// One slider column: vertical (rotated) Slider above a frequency
    /// or "Preamp" label, with a numeric dB readout below.
    private func sliderColumn(label: String,
                              value: Binding<Float>) -> some View {
        VStack(spacing: 4) {
            Slider(value: value, in: -12...12, step: 0.5)
                .rotationEffect(.degrees(-90))
                .frame(width: 200)
                .frame(width: 30, height: 200)
                .disabled(!coordinator.isEnabled)
            Text(label)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 48)
            Text(formatGain(value.wrappedValue))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 48)
        }
    }

    private func formatGain(_ db: Float) -> String {
        String(format: "%+.1f", db)
    }

    // MARK: - Save Sheet

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("eq_preset_save_dialog_title"))
                .font(.headline)
            TextField(L("eq_preset_save_dialog_placeholder"),
                      text: $saveDraftName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingSaveSheet = false
                }
                Button(L("eq_preset_save_button")) {
                    submitSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDraftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private func submitSave() {
        let name = saveDraftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try coordinator.saveAsCustomPreset(name: name)
            showingSaveSheet = false
        } catch {
            // Currently the only thrown case is .nameCollidesWithBuiltin.
            // Close save sheet, then show collision alert.
            showingSaveSheet = false
            showingNameCollisionAlert = true
        }
    }

    // MARK: - Built-in Preset Display Names

    /// Maps a built-in preset's English `name` to its localised
    /// display string. Custom presets are user-supplied and shown
    /// verbatim.
    private func localisedBuiltinName(_ englishName: String) -> String {
        switch englishName {
        case "Flat":         return L("eq_preset_flat")
        case "Rock":         return L("eq_preset_rock")
        case "Pop":          return L("eq_preset_pop")
        case "Jazz":         return L("eq_preset_jazz")
        case "Classical":    return L("eq_preset_classical")
        case "Vocal":        return L("eq_preset_vocal")
        case "Bass Boost":   return L("eq_preset_bass_boost")
        case "Treble Boost": return L("eq_preset_treble_boost")
        default:             return englishName
        }
    }
}
