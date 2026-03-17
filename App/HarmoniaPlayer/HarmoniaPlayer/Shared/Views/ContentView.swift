//
//  ContentView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Root view of the HarmoniaPlayer window. Combines `PlaylistView` (left)
//  and `PlayerView` (right) in a resizable split layout.
//
//  DESIGN NOTES
//  ------------
//  - `HSplitView` provides a user-resizable divider between the playlist
//    and the player panel. Minimum widths prevent either panel from
//    collapsing completely.
//  - `AppState` is provided via `@EnvironmentObject` injected by
//    `HarmoniaPlayerApp`; this view does not create or own it.
//  - No `import HarmoniaCore` — all state access goes through `AppState`.
//

import SwiftUI

/// Root view combining `PlaylistView` and `PlayerView`.
///
/// Renders a horizontally split layout:
/// - Left: `PlaylistView` (min 260pt, ideal 300pt, max 400pt)
/// - Right: `PlayerView` (min 320pt, ideal 380pt)
struct ContentView: View {

    var body: some View {
        HSplitView {
            PlaylistView()
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)

            PlayerView()
                .frame(minWidth: 320, idealWidth: 380)
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}