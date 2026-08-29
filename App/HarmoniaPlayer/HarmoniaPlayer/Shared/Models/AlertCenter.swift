//
//  AlertCenter.swift
//  HarmoniaPlayer / Shared / Models
//

import Foundation

/// Store owning the alert, paywall, and File Info request presentation state.
///
/// Extracted from `AppState`, which re-exposes every property below as a
/// same-named facade forwarder (get + set) so internal call sites keep
/// writing through `AppState`. Views whose body reads alert state observe
/// this store directly via `@Environment(AlertCenter.self)` (with
/// `@Bindable` where sheet/alert bindings are needed), so alert-state
/// changes no longer re-render views observing unrelated `AppState`
/// properties.
@MainActor @Observable
final class AlertCenter {

    // MARK: - Playback-error surface

    /// Most recent playback error. `nil` when no error is pending.
    /// Views observe this to present error banners or alerts.
    var lastError: PlaybackError?

    /// One-line diagnostic summary accompanying `lastError`.
    ///
    /// Format: `"<errorCode>: <track.url.path>"` or
    /// `"<errorCode>: (no active track)"` for error sites without a known
    /// track. Used by the "Report Issue" button to prefill the mailto body.
    var lastErrorDetail: String?

    /// Display name of the track that triggered the most recent
    /// `failedToOpenFile` error.
    ///
    /// "Title - Artist" when artist is available, otherwise the URL filename.
    var failedTrackName: String?

    /// Controls the file-not-found alert presentation.
    ///
    /// `ContentView` binds directly to this flag so the alert is not
    /// dependent on `onChange(of: lastError)` timing.
    var showFileNotFoundAlert = false

    /// Names of tracks skipped during auto-play due to inaccessibility.
    ///
    /// The file-not-found alert lists all skipped tracks; the list clears
    /// together with the rest of the playback-error surface.
    var skippedInaccessibleNames: [String] = []

    // MARK: - Batch-operation surfaces

    /// URLs that were skipped during the last load because they already
    /// exist in the playlist. Non-empty triggers a duplicate alert.
    var skippedDuplicateURLs: [URL] = []

    /// URLs that were skipped during the last playlist import because the
    /// files were not found on disk. Non-empty triggers a warning alert.
    var skippedImportURLs: [URL] = []

    /// URLs skipped during load because their format is not supported by
    /// HarmoniaPlayer at any tier. Non-empty triggers an unsupported-format
    /// alert.
    var skippedUnsupportedURLs: [URL] = []

    // MARK: - File Info window request

    /// One-shot signal requesting the File Info window to open for a track.
    ///
    /// `ContentView` observes this property and opens the independent
    /// `WindowGroup(for:)` scene, then clears the request so the same track
    /// can request the window again on a subsequent call.
    var fileInfoTrack: Track?

    // MARK: - Paywall

    /// Whether the Pro paywall sheet is currently presented.
    var showPaywall = false

    /// Whether the user has chosen to silently skip Pro-only format tracks
    /// during auto-play for this session.
    ///
    /// Session-only; resets on every app launch and is never persisted.
    var paywallDismissedThisSession = false

    // MARK: - Presentation methods

    /// Clears the playback-error surface (error, detail, failed name,
    /// file-not-found flag, inaccessible-skip list). Batch-operation
    /// lists are cleared by their own alerts' dismiss buttons, not here.
    func clearLastError() {
    }

    /// Presents the File Info window request for the given track.
    func presentFileInfo(_ track: Track) {
    }

    /// Clears the one-shot File Info request after the window opens.
    func clearFileInfoRequest() {
    }

    /// Presents the Pro paywall sheet.
    func presentPaywall() {
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}
}
