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
//  - All UI strings use `String(localized:bundle:appState.languageBundle)`
//    for runtime language switching support.
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

    // MARK: - Localization helper

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: appState.languageBundle, comment: "")
    }

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
        // Propagate live playbackState into the focus system so
        // HarmoniaPlayerCommands can observe it via @FocusedValue.
        // @FocusedObject does not reliably re-evaluate Commands body on
        // property changes; @FocusedValue with a scalar value does.
        .focusedValue(\.playbackState, appState.playbackState)
        // File Info panel — presented when appState.fileInfoTrack is set
        .sheet(item: $appState.fileInfoTrack) { track in
            FileInfoView(track: track, languageBundle: appState.languageBundle)
        }
        // Paywall sheet — presented when a Free user triggers a Pro-only action
        .sheet(isPresented: $appState.showPaywall) {
            PaywallView()
                .environmentObject(appState)
        }
        // Unsupported format alert — shown when dropped files use an unrecognised format
        .alert(
            Text(L("alert_unsupported_format_title")),
            isPresented: Binding(
                get: { !appState.skippedUnsupportedURLs.isEmpty },
                set: { if !$0 { appState.skippedUnsupportedURLs = [] } }
            )
        ) {
            Button("OK") { appState.skippedUnsupportedURLs = [] }
        } message: {
            let names = appState.skippedUnsupportedURLs
                .map { $0.lastPathComponent }
                .joined(separator: "\n")
            Text(String(format: L("alert_unsupported_format_body"), names))
        }
        // Auto-dismiss alert for failedToOpenFile (3 seconds)
        .onChange(of: appState.showFileNotFoundAlert) {
            guard appState.showFileNotFoundAlert else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                appState.clearLastError()
            }
        }
        .alert(
            Text(L("alert_file_not_found_title")),
            isPresented: $appState.showFileNotFoundAlert
        ) {
            Button("OK") {
                appState.clearLastError()
            }
        } message: {
            if !appState.skippedInaccessibleNames.isEmpty {
                let names = appState.skippedInaccessibleNames.map { "• \($0)" }.joined(separator: "\n")
                Text(String(format: L("alert_file_not_found_multi"), names))
            } else if let name = appState.failedTrackName {
                Text(String(format: L("alert_file_not_found_single"), name))
            } else {
                Text(L("alert_file_not_found_generic"))
            }
        }
        .alert(
            Text(L("alert_already_in_playlist_title")),
            isPresented: Binding(
                get: { !appState.skippedDuplicateURLs.isEmpty },
                set: { if !$0 { appState.skippedDuplicateURLs = [] } }
            )
        ) {
            Button("OK") { appState.skippedDuplicateURLs = [] }
        } message: {
            let names = appState.skippedDuplicateURLs
                .map { $0.lastPathComponent }
                .joined(separator: "\n")
            Text(String(format: L("alert_already_in_playlist_body"), names))
        }
        .alert(
            Text(L("alert_playback_error_title")),
            isPresented: Binding(
                get: {
                    switch appState.lastError {
                    case .failedToOpenFile, nil: return false
                    default: return true
                    }
                },
                set: { if !$0 { appState.clearLastError() } }
            )
        ) {
            Button("OK") { appState.clearLastError() }
        } message: {
            switch appState.lastError {
            case .unsupportedFormat:
                Text(L("error_unsupported_format"))
            case .failedToDecode:
                Text(L("error_failed_to_decode"))
            case .outputError:
                Text(L("error_output_error"))
            case .invalidState, .invalidArgument:
                Text(L("error_internal"))
            default:
                Text(verbatim: "")
            }
        }
    }
}
