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

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

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

        // Close any MiniPlayer window restored by State Restoration.
        // MiniPlayer must only be opened explicitly by the user (⌘M or menu),
        // never auto-restored on launch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            NSApp.windows
                .first { windowMatchesScene($0, id: "mini-player") }?
                .close()
        }

        // Window-menu hygiene and exclusivity, enforced at the window level.
        //
        // 1. The app's own Window-menu items are the canonical controls for
        //    the main window, the Mini Player, and the Equalizer, so those
        //    windows are excluded from the system-populated windows list —
        //    otherwise the menu shows duplicate entries for the same window.
        // 2. The main window and the Mini Player are two modes of one player
        //    surface: whenever the main window becomes key — via the menu
        //    item, a Dock reopen, or window cycling — the Mini Player closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }

            if ["main", "mini-player", "equalizer-window"]
                .contains(where: { windowMatchesScene(window, id: $0) }) {
                window.isExcludedFromWindowsMenu = true
            }

            guard windowMatchesScene(window, id: "main") else { return }
            NSApp.windows
                .filter { windowMatchesScene($0, id: "mini-player") }
                .forEach { $0.close() }
        }
    }

    @StateObject private var appState = AppState(
        iapManager: FreeTierIAPManager(),
        provider: HarmoniaCoreProvider()
    )

    var body: some Scene {
        Window("Harmonia Player", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 620, minHeight: 480)
                .focusedSceneObject(appState)
                .ignoresSafeArea()
                // Hand the open-window action to the app delegate so a Dock
                // click can recreate the main window after it has been
                // closed. Captured here because SwiftUI does not populate
                // @Environment values during App.init.
                .onAppear {
                    appDelegate.openWindow = openWindow
                }
                // v0.1 frozen: Pro UI hidden. Re-enable in v0.2.
                // .task {
                //     await appState.refreshEntitlements()
                // }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    appState.saveState()
                }
        }
        .commandsRemoved()
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
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        // Equalizer — single-instance floating utility window
        // (Slice 9-K). Opened via Window → Equalizer (⌘⌥E).
        // Singleton: same `id` reused on each open call.
        // `.defaultLaunchBehavior(.suppressed)` mirrors Mini Player
        // and File Info so the window is never auto-restored at
        // launch — only opens in response to an explicit user action.
        Window("Equalizer", id: "equalizer-window") {
            EQWindow()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        // File Info — independent, non-modal window identified by Track.ID.
        // Opened via ContentView's .onChange(of: appState.fileInfoTrack).
        // Multiple File Info windows can coexist; each is keyed by its track's ID.
        // `.defaultLaunchBehavior(.suppressed)` mirrors Mini Player: File Info
        // windows are never auto-restored on launch; they only open in response
        // to an explicit user action (⌘I or right-click → Get Info).
        WindowGroup(for: Track.ID.self) { $trackID in
            if let trackID {
                FileInfoView(trackID: trackID)
                    .environmentObject(appState)
            } else {
                EmptyView()
            }
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
    }
}

/// SwiftUI derives the AppKit window identifier from the scene id as
/// "{id}-AppWindow-{n}", so scene-window matching must accept both the bare
/// id and the derived form.
private func windowMatchesScene(_ window: NSWindow, id: String) -> Bool {
    guard let raw = window.identifier?.rawValue else { return false }
    return raw == id || raw.hasPrefix(id + "-")
}
