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

    /// Posted by AppState when a Pro-only format is played on the Free tier.
    /// `MiniPlayerView` listens and calls `closeMiniPlayer()` so the Paywall
    /// sheet can appear on the main window instead of the MiniPlayer.
    static let bringMainWindowToFront = Notification.Name("harmoniaPlayer.bringMainWindowToFront")
}

// MARK: - Commands

/// macOS menu bar commands for HarmoniaPlayer.
///
/// Exposes a File "Add Files…" item, Undo/Redo, and a full Playback menu.
/// Requires `.focusedSceneObject(appState)` on the window's root view.
/// All UI strings use `String(localized:bundle:)` via `bundle` helper
/// for runtime language switching support.
///
/// `@FocusedObject` provides playlist/track state for `.disabled()` conditions.
/// `@FocusedValue(\.playbackState)` carries live PlaybackState as a scalar value,
/// which re-evaluates Commands reliably on every change — unlike `@FocusedObject`
/// property observation, which can miss updates inside Commands.
struct HarmoniaPlayerCommands: Commands {

    @FocusedObject private var appState: AppState?

    /// Live playback state propagated from ContentView via FocusedValues.
    /// Used for the Play/Pause label and Playback menu disabled conditions.
    @FocusedValue(\.playbackState) private var focusedPlaybackState: PlaybackState?

    @Environment(\.openWindow) private var openWindow

    // MARK: - Localization helper

    private var bundle: Bundle { appState?.languageBundle ?? .main }

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    var body: some Commands {
        // Remove default "New" item — not applicable for a music player.
        CommandGroup(replacing: .newItem) {}

        // v0.1 frozen: Pro UI hidden. Re-enable in v0.2.
        // CommandGroup(after: .appInfo) {
        //     if appState?.isProUnlocked == false {
        //         Button(L("menu_upgrade_to_pro")) {
        //             appState?.showPaywallIfNeeded()
        //         }
        //         Divider()
        //     }
        // }

        // Replace default Undo/Redo with versions wired to AppState.undoManager.
        // Disabled when the manager has nothing to undo/redo.
        CommandGroup(replacing: .undoRedo) {
            Button(L("menu_undo")) {
                appState?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(appState?.canUndo != true || isBlocking)

            Button(L("menu_redo")) {
                appState?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(appState?.canRedo != true || isBlocking)
        }

        // Remove unused default menu groups.
        Group {
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .systemServices) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .help) {}
        }

        // Window menu — Mini Player toggle (⌘M).
        CommandGroup(replacing: .windowArrangement) {
            Button(L("menu_mini_player")) {
                openWindow(id: "mini-player")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NSApp.windows
                        .filter { $0.title == "HarmoniaPlayer" }
                        .first?
                        .orderOut(nil)
                }
            }
            .keyboardShortcut("m", modifiers: .command)
        }

        // Add "Add Files…" and playlist management to the File menu.
        CommandGroup(after: .newItem) {
            Button(L("menu_add_files")) {
                NotificationCenter.default.post(name: .openFilePicker, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(isBlocking)

            Divider()

            Button(L("menu_get_info")) {
                guard let state = appState,
                      let trackID = state.selectedTrackIDs.first else { return }
                state.showFileInfo(trackID: trackID)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(appState?.selectedTrackIDs.isEmpty != false)

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
            .disabled(isBlocking)
        }

        // Playback menu
        CommandMenu(L("menu_playback")) {

            // Play / Pause
            // Disabled when playlist is empty (nothing to play).
            Button(playPauseLabel) {
                Task {
                    if focusedPlaybackState == .playing {
                        await appState?.pause()
                    } else {
                        await appState?.play()
                    }
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(playlistIsEmpty)

            // Stop / Seek — disabled when playlist is empty OR no track is loaded.
            // Requires an active track because these operations act on the current position.
            Button(L("menu_stop")) {
                Task { await appState?.stop() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(needsActiveTrack)

            Divider()

            // Next / Previous — disabled when playlist is empty only.
            // Matches PlayerView button logic: playNextTrack() / playPreviousTrack()
            // start from the first track when currentTrack is nil, so no active
            // track is required.
            Button(L("menu_next_track")) {
                Task { await appState?.playNextTrack() }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(playlistIsEmpty)

            Button(L("menu_previous_track")) {
                Task { await appState?.playPreviousTrack() }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(playlistIsEmpty)

            Divider()

            Button(L("menu_seek_forward")) {
                Task {
                    guard let state = appState else { return }
                    await state.seek(to: min(state.duration, state.currentTime + 5))
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(needsActiveTrack)

            Button(L("menu_seek_backward")) {
                Task {
                    guard let state = appState else { return }
                    await state.seek(to: max(0, state.currentTime - 5))
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(needsActiveTrack)

            Divider()

            Button(repeatModeLabel) {
                appState?.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(playlistIsEmpty)

            Button(shuffleLabel) {
                appState?.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(playlistIsEmpty)
        }
    }

    // MARK: - Dynamic Labels

    /// Play/Pause label — driven by focusedPlaybackState (scalar FocusedValue)
    /// rather than appState?.playbackState so Commands re-evaluates reliably
    /// on every state change.
    private var playPauseLabel: String {
        focusedPlaybackState == .playing ? L("menu_pause") : L("menu_play")
    }

    /// True when the playlist has no tracks.
    /// Used for: Play/Pause, Next Track, Previous Track.
    private var playlistIsEmpty: Bool {
        appState?.playlist.tracks.isEmpty != false
    }

    /// True when there is no currently loaded track.
    /// Used for: Stop, Seek Forward, Seek Backward.
    /// These operations require an active playback position to be meaningful.
    private var needsActiveTrack: Bool {
        playlistIsEmpty || appState?.currentTrack == nil
    }

    /// True when a batch playlist operation (load / import) is in progress.
    /// Used for: Add Files, Import M3U8, Undo, Redo.
    private var isBlocking: Bool {
        appState?.isPerformingBlockingOperation == true
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
        // UTType(filenameExtension:) can return nil for custom extensions;
        // fall back to setting allowedFileTypes via the deprecated API or
        // leave unfiltered and rely on the file extension in nameFieldStringValue.
        if let m3u8Type = UTType(filenameExtension: "m3u8") {
            panel.allowedContentTypes = [m3u8Type]
        }
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
        if let m3u8Type = UTType(filenameExtension: "m3u8") {
            panel.allowedContentTypes = [m3u8Type]
        }
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
