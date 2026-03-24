//
//  HarmoniaPlayerCommands.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user selects "Add Files…" from the menu bar.
    /// `PlaylistView` listens and calls `openFilePicker()`.
    static let openFilePicker = Notification.Name("harmoniaPlayer.openFilePicker")

    /// Posted when the user selects "Rename Playlist" from the menu bar.
    /// `PlaylistView` listens and activates inline tab rename.
    static let renameActivePlaylist = Notification.Name("harmoniaPlayer.renameActivePlaylist")
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

        // Add "Add Files…" and playlist management to the File menu.
        CommandGroup(after: .newItem) {
            Button("Add Files…") {
                NotificationCenter.default.post(name: .openFilePicker, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("New Playlist") {
                appState?.newPlaylist(name: "")
                NotificationCenter.default.post(name: .renameActivePlaylist, object: nil)
            }

            Button("Rename Playlist") {
                NotificationCenter.default.post(name: .renameActivePlaylist, object: nil)
            }

            Button("Delete Playlist") {
                guard let state = appState else { return }
                state.deletePlaylist(at: state.activePlaylistIndex)
            }

            Divider()

            Button("Export Playlist…") {
                guard let state = appState else { return }
                exportPlaylist(appState: state)
            }

            Button("Import Playlist…") {
                guard let state = appState else { return }
                importPlaylist(appState: state)
            }
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

    // MARK: - Export / Import Helpers

    private func exportPlaylist(appState: AppState) {
        let panel = NSSavePanel()
        panel.title = "Export Playlist"
        panel.allowedContentTypes = [.init(filenameExtension: "m3u8")!]
        panel.nameFieldStringValue = "\(appState.playlist.name).m3u8"
        panel.canCreateDirectories = true

        // Path style picker as accessory view
        let useRelative = NSButton(checkboxWithTitle: "Use relative paths (for USB drives / sharing)", target: nil, action: nil)
        useRelative.state = .off
        panel.accessoryView = useRelative

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let pathStyle: M3U8PathStyle = useRelative.state == .on
            ? .relative(to: url)
            : .absolute

        Task {
            do {
                try appState.writeExport(to: url, pathStyle: pathStyle)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func importPlaylist(appState: AppState) {
        let panel = NSOpenPanel()
        panel.title = "Import Playlist"
        panel.allowedContentTypes = [.init(filenameExtension: "m3u8")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await appState.importPlaylist(from: url)
            // Show warning alert if any files were missing
            let skipped = appState.skippedImportURLs
            if !skipped.isEmpty {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Some Files Were Not Found"
                    alert.informativeText = "The following files were skipped:\n\n"
                        + skipped.map { $0.path }.joined(separator: "\n")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}
