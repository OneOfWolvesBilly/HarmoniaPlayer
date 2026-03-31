//
//  SettingsView.swift
//  HarmoniaPlayer / macOS / Free / Views
//
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import AppKit

/// Settings window content view (⌘,).
///
/// Binds directly to `AppState` published state.
/// No `import HarmoniaCore`.
/// All UI strings use `String(localized:bundle:appState.languageBundle)`
/// for runtime language switching support.
struct SettingsView: View {
    
    @EnvironmentObject private var appState: AppState
    
    // MARK: - Localization helper
    
    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: appState.languageBundle, comment: "")
    }
    
    // MARK: - Available languages (implemented language packs)
    
    /// Language options available in the picker.
    /// Each entry is (BCP-47 tag or "system", display name in its own script).
    private let languageOptions: [(id: String, name: String)] = [
        ("en",       "English"),
        ("zh-Hant",  "繁體中文"),
        ("ja",       "日本語"),
    ]
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appState.allowDuplicateTracks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings_allow_duplicates"))
                        Text(L("settings_allow_duplicates_desc"))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .accessibilityIdentifier("allow-duplicates-toggle")
                .accessibilityElement(children: .contain)
            } header: {
                Text(L("settings_section_playlist"))
            }
            
            Section {
                Picker(L("settings_section_language"), selection: $appState.selectedLanguage) {
                    ForEach(languageOptions, id: \.id) { option in
                        // "System Default" label is intentionally not localized —
                        // it always shows in English so the user can find it after
                        // accidentally switching to an unfamiliar language.
                        if option.id == "system" {
                            Text(L("settings_language_system")).tag(option.id)
                        } else {
                            Text(option.name).tag(option.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("language-picker")
                .onChange(of: appState.selectedLanguage) {
                    appState.saveState()
                    applyLanguageAndRestart(appState.selectedLanguage)
                }
            } header: {
                Text(L("settings_section_language"))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 320)
        .navigationTitle(L("nav_title_settings"))
    }
    
    // MARK: - Private
    
    private func applyLanguageAndRestart(_ lang: String) {
        // Write AppleLanguages so the system menus also switch language.
        if lang == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        
        // Prompt user to restart so the new language takes full effect.
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "HarmoniaPlayer needs to restart to apply the language change."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let url = Bundle.main.bundleURL
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [url.path]
            task.launch()
            NSApplication.shared.terminate(nil)
        }
    }
}
