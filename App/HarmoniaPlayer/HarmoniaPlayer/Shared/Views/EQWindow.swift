//
//  EQWindow.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Window-shell wrapper for `EQView`. Reads the EQ coordinator from
//  the `AppState` environment object, applies window-specific framing
//  (minimum size), and forwards rendering to EQView.
//
//  WHY A SEPARATE FILE
//  -------------------
//  EQView is the pure controls UI (suitable for previewing in
//  isolation or embedding into a future Pro Settings tab). EQWindow
//  is the window-specific composition site that routes
//  `appState.eqCoordinator` into the view.
//
//  WINDOW REGISTRATION
//  -------------------
//  Registered in `HarmoniaPlayerApp` as a single-instance
//  `Window("Equalizer", id: "equalizer-window")` opened by the
//  Equalizer menu item (⌘⌥E) in `HarmoniaPlayerCommands`.
//

import SwiftUI

struct EQWindow: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        EQView(coordinator: appState.eqCoordinator)
            .environmentObject(appState)
            .frame(minWidth: 720, minHeight: 360)
    }
}
