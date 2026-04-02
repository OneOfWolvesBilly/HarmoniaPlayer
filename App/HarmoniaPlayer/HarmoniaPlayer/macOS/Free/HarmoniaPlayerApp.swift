//
//  HarmoniaPlayerApp.swift
//  HarmoniaPlayer / macOS Free
//
//  SPDX-License-Identifier: MIT
//
//  Application entry point for macOS Free version.
//


import SwiftUI

@main
struct HarmoniaPlayerApp: App {

    init() {
        let savedLang = UserDefaults.standard.string(forKey: "hp.selectedLanguage")

        if let lang = savedLang, lang != "system" {
            // User has explicitly chosen a language — apply it.
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        } else if savedLang == nil {
            // First launch — default to English so menus are consistent.
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            UserDefaults.standard.set("en", forKey: "hp.selectedLanguage")
        }
        // "system" → remove override, let OS decide.
        if savedLang == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    @StateObject private var appState = AppState(
        iapManager: FreeTierIAPManager(),
        provider: HarmoniaCoreProvider()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 620, minHeight: 480)
                .focusedSceneObject(appState)
                .ignoresSafeArea()
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    appState.saveState()
                }
        }
        .commands {
            HarmoniaPlayerCommands()
        }

        // Mini Player — compact floating window (always on top).
        // Opened via Window → Mini Player (⌘M).
        Window("Mini Player", id: "mini-player") {
            MiniPlayerView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .windowStyle(.plain)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
    }
}
