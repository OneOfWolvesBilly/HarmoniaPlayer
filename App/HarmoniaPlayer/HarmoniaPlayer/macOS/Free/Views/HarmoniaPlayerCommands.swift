//
//  HarmoniaPlayerCommands.swift
//  HarmoniaPlayer / macOS / Free / Views
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
/// All UI strings use `String(localized:bundle:)` via `bundle` helper
/// for runtime language switching support.
struct HarmoniaPlayerCommands: Commands {

    @FocusedObject private var appState: AppState?

    // MARK: - Localization helper

    private var bundle: Bundle { appState?.languageBundle ?? .main }

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    var body: some Commands {
        // Remove default "New" item — not applicable for a music player.
        CommandGroup(replacing: .newItem) {}

        // Add "Add Files…" and playlist management to the File menu.
        CommandGroup(after: .newItem) {
            Button(L("menu_add_files")) {
                NotificationCenter.default.post(name: .openFilePicker, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(L("menu_new_playlist")) {
                appState?.newPlaylist(name: "")
                NotificationCenter.default.post(name: .renameActivePlaylist, object: nil)
            }

            Button(L("menu_rename_playlist")) {
                NotificationCenter.default.post(name: .renameActivePlaylist, object: nil)
            }

            Button(L("menu_delete_playlist")) {
                guard let state = appState else { return }
                state.deletePlaylist(at: state.activePlaylistIndex)
            }

            Divider()

            Button(L("menu_export_playlist")) {
                guard let state = appState else { return }
                exportPlaylist(appState: state)
            }

            Button(L("menu_import_playlist")) {
                guard let state = appState else { return }
                importPlaylist(appState: state)
            }
        }

        // Playback menu
        CommandMenu(L("menu_playback")) {

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

            Button(L("menu_stop")) {
                Task { await appState?.stop() }
            }
            .keyboardShortcut(".", modifiers: .command)

            Divider()

            Button(L("menu_next_track")) {
                Task { await appState?.playNextTrack() }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button(L("menu_previous_track")) {
                Task { await appState?.playPreviousTrack() }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button(L("menu_seek_forward")) {
                Task {
                    guard let state = appState else { return }
                    await state.seek(to: min(state.duration, state.currentTime + 5))
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button(L("menu_seek_backward")) {
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

    // MARK: - Dynamic Labels

    private var playPauseLabel: String {
        appState?.playbackState == .playing ? L("menu_pause") : L("menu_play")
    }

    private var repeatModeLabel: String {
        switch appState?.repeatMode {
        case .off:  return L("repeat_off")
        case .all:  return L("repeat_all")
        case .one:  return L("repeat_one")
        case .none: return L("menu_repeat_mode")
        }
    }

    private var shuffleLabel: String {
        appState?.isShuffled == true ? L("shuffle_on") : L("shuffle_off")
    }

    // MARK: - Export / Import Helpers

    private func exportPlaylist(appState: AppState) {
        let panel = NSSavePanel()
        panel.title = L("panel_export_title")
        panel.allowedContentTypes = [.init(filenameExtension: "m3u8")!]
        panel.nameFieldStringValue = "\(appState.playlist.name).m3u8"
        panel.canCreateDirectories = true

        // Path style picker as accessory view
        let useRelative = NSButton(
            checkboxWithTitle: L("panel_export_relative"),
            target: nil,
            action: nil
        )
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
                    alert.messageText = L("alert_export_failed")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func importPlaylist(appState: AppState) {
        let panel = NSOpenPanel()
        panel.title = L("panel_import_title")
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
                    alert.messageText = L("alert_import_missing_title")
                    alert.informativeText = String(
                        format: L("alert_import_missing_body"),
                        skipped.map { $0.path }.joined(separator: "\n")
                    )
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}
