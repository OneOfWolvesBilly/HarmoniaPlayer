//
//  SettingsView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//

import SwiftUI

/// Settings window content view (⌘,).
///
/// Binds directly to `AppState` published state.
/// No `import HarmoniaCore`.
struct SettingsView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appState.allowDuplicateTracks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow duplicate tracks")
                        Text("When enabled, the same file can be added to the playlist more than once.")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .accessibilityIdentifier("allow-duplicates-toggle")
            } header: {
                Text("Playlist")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 140)
    }
}
