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
//  - `failedToOpenFile` alert auto-dismisses after 3 seconds.
//    Other playback errors require manual dismissal.
//  - No `import HarmoniaCore` — all state access goes through `AppState`.
//

import SwiftUI

/// Root view combining `PlaylistView` and `PlayerView`.
///
/// Renders a horizontally split layout:
/// - Left: `PlaylistView` (min 260pt, ideal 300pt, max 400pt)
/// - Right: `PlayerView` (min 320pt, ideal 380pt)
///
/// Hosts the duplicate-URL alert at the top level so it is guaranteed
/// to appear on macOS regardless of which subview triggered the load.
struct ContentView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        HSplitView {
            PlaylistView()
                .frame(minWidth: 260, idealWidth: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlayerView()
                .frame(minWidth: 320, idealWidth: 380)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Auto-dismiss alert for failedToOpenFile (3 seconds)
        .onChange(of: appState.showFileNotFoundAlert) {
            guard appState.showFileNotFoundAlert else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                appState.clearLastError()
            }
        }
        .alert("File Not Found", isPresented: $appState.showFileNotFoundAlert) {
            Button("OK") {
                appState.clearLastError()
            }
        } message: {
            if !appState.skippedInaccessibleNames.isEmpty {
                let names = appState.skippedInaccessibleNames.map { "• \($0)" }.joined(separator: "\n")
                Text("The following files could not be opened and were skipped:\n\(names)")
            } else if let name = appState.failedTrackName {
                Text("\"\(name)\" could not be opened. It may have been moved or deleted.")
            } else {
                Text("The file could not be opened. It may have been moved or deleted.")
            }
        }
        .alert("Already in Playlist", isPresented: Binding(
            get: { !appState.skippedDuplicateURLs.isEmpty },
            set: { if !$0 { appState.skippedDuplicateURLs = [] } }
        )) {
            Button("OK") { appState.skippedDuplicateURLs = [] }
        } message: {
            let names = appState.skippedDuplicateURLs
                .map { $0.lastPathComponent }
                .joined(separator: "\n")
            Text("The following files are already in the playlist and were not added:\n\(names)")
        }
        .alert("Playback Error", isPresented: Binding(
            get: {
                switch appState.lastError {
                case .failedToOpenFile, nil: return false
                default: return true
                }
            },
            set: { if !$0 { appState.clearLastError() } }
        )) {
            Button("OK") { appState.clearLastError() }
        } message: {
            switch appState.lastError {
            case .unsupportedFormat:
                Text("This format is not supported in the Free version.")
            case .failedToDecode:
                Text("The file could not be decoded.")
            case .outputError:
                Text("A playback output error occurred.")
            case .coreError(let msg):
                Text(msg)
            default:
                Text("")
            }
        }
    }
}
