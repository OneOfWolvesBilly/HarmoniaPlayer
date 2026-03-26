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

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
