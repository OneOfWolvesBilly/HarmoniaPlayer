//
//  HarmoniaPlayerCommands.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//

import SwiftUI

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user selects "Add Files…" from the menu bar.
    /// `PlaylistView` listens and calls `openFilePicker()`.
    static let openFilePicker = Notification.Name("harmoniaPlayer.openFilePicker")
}

// MARK: - Commands

/// macOS menu bar commands for HarmoniaPlayer.
///
/// Exposes a File "Add Files…" item and a full Playback menu.
/// Requires `.focusedSceneObject(appState)` on the window's root view.
struct HarmoniaPlayerCommands: Commands {

    @FocusedObject private var appState: AppState?

    var body: some Commands {
        // Remove default "New" item — not applicable for a music player.
        CommandGroup(replacing: .newItem) {}

        // Add "Add Files…" to the File menu.
        CommandGroup(after: .newItem) {
            Button("Add Files…") {
                NotificationCenter.default.post(name: .openFilePicker, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        // Playback menu
        CommandMenu("Playback") {

            Button(playPauseLabel) {
                Task {
                    if appState?.playbackState == .playing {
                        await appState?.pause()
                    } else {
                        await appState?.play()
                    }
                }
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Stop") {
                Task { await appState?.stop() }
            }
            .keyboardShortcut(".", modifiers: .command)

            Divider()

            Button("Next Track") {
                Task { await appState?.playNextTrack() }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") {
                Task { await appState?.playPreviousTrack() }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Seek Forward 5 Seconds") {
                Task {
                    guard let state = appState else { return }
                    await state.seek(to: min(state.duration, state.currentTime + 5))
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Seek Backward 5 Seconds") {
                Task {
                    guard let state = appState else { return }
                    await state.seek(to: max(0, state.currentTime - 5))
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Divider()

            Button(repeatModeLabel) {
                appState?.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button(shuffleLabel) {
                appState?.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    // MARK: - Helpers

    private var playPauseLabel: String {
        appState?.playbackState == .playing ? "Pause" : "Play"
    }

    private var repeatModeLabel: String {
        switch appState?.repeatMode {
        case .off:  return "Repeat: Off"
        case .all:  return "Repeat: All"
        case .one:  return "Repeat: One"
        case .none: return "Repeat Mode"
        }
    }

    private var shuffleLabel: String {
        appState?.isShuffled == true ? "Shuffle: On" : "Shuffle: Off"
    }
}
