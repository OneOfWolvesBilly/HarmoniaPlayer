//
//  AppDelegate.swift
//  HarmoniaPlayer / macOS Free
//
//  SPDX-License-Identifier: MIT
//
//  Application delegate for window-mode coordination with the Dock and the
//  window lifecycle.
//
//  The main window and the Mini Player are two modes of one player surface:
//  opening the Mini Player hides the main window, and closing the Mini
//  Player returns to the main window. Clicking the Dock icon shows the main
//  window even when the Mini Player is still visible.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Captured from the SwiftUI environment by the App (see
    /// HarmoniaPlayerApp). Used only to recreate the main window after the
    /// user has closed it; a still-existing (hidden or miniaturized) main
    /// window is brought forward directly without this action.
    var openWindow: OpenWindowAction?

    /// Assigned by HarmoniaPlayerApp (same injection pattern as
    /// `openWindow`). Receives the system sleep/wake notifications
    /// forwarded below. Weak: the delegate must not extend the lifetime
    /// of the app's state container.
    weak var appState: AppState?

    /// Set as soon as the user quits, so windows closing during termination
    /// do not trigger the "return to the main window" behaviour below.
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Closing the Mini Player returns to the main window: bring the
        // hidden window forward, or recreate it when the user had closed it.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                !self.isTerminating,
                let window = notification.object as? NSWindow,
                windowMatchesScene(window, id: "mini-player")
            else { return }

            // The window is still tearing down inside willClose; defer the
            // switch back to the main window to the next runloop pass.
            DispatchQueue.main.async {
                guard !self.isTerminating else { return }
                self.showMainWindow()
            }
        }

        // Sleep/wake observation: record the pre-sleep playback state and
        // resume after wake. Registered on NSWorkspace's own notification
        // center — system power notifications are not delivered through
        // NotificationCenter.default.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.appState?.handleSystemWillSleep()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.appState?.handleSystemDidWake()
            }
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // A player surface that already exists — main window or Mini Player —
        // is left alone; the Dock click then behaves like a plain app
        // activation. Only when neither exists does the Dock click bring the
        // main window back.
        let hasPlayerSurface = sender.windows.contains {
            windowMatchesScene($0, id: "main") || windowMatchesScene($0, id: "mini-player")
        }
        guard !hasPlayerSurface else { return true }

        showMainWindow()
        return false
    }

    /// Brings the main window forward, recreating it when no instance exists.
    private func showMainWindow() {
        if let main = NSApp.windows.first(where: { windowMatchesScene($0, id: "main") }) {
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
    }
}

/// SwiftUI derives the AppKit window identifier from the scene id as
/// "{id}-AppWindow-{n}", so scene-window matching must accept both the bare
/// id and the derived form.
private func windowMatchesScene(_ window: NSWindow, id: String) -> Bool {
    guard let raw = window.identifier?.rawValue else { return false }
    return raw == id || raw.hasPrefix(id + "-")
}
