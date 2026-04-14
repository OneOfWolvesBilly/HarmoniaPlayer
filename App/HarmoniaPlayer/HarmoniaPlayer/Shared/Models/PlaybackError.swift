//
//  PlaybackError.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-23.
//

import Foundation

/// Playback error enumeration
///
/// Represents error conditions that can occur during audio playback.
/// Used as the associated value of `PlaybackState.error(_:)` and stored
/// in `AppState.lastError`.
///
/// All cases are typed codes with no `String` payload. The View layer
/// maps each case to a localized user-facing message. Technical details
/// from HarmoniaCore are logged at the Integration Layer and never
/// propagated to the UI.
///
/// **Cases:**
/// - `unsupportedFormat`: File format is not supported by the current
///   product variant (e.g. FLAC on Free). May trigger a paywall flow.
/// - `failedToOpenFile`: File could not be opened (missing, permission
///   denied, network unreachable, etc.).
/// - `failedToDecode`: Decoding failed after the file was opened
///   (corrupt data, partial download, etc.).
/// - `outputError`: Audio output device or engine error (device
///   disconnected, exclusive mode conflict, etc.).
/// - `invalidState`: Operation attempted in an invalid state (e.g.
///   play without load). UI should normally prevent this; indicates
///   a logic error if reached.
/// - `invalidArgument`: Invalid parameter passed to a service (e.g.
///   seek to negative position). UI should normally prevent this;
///   indicates a logic error if reached.
///
/// **Usage:**
/// ```swift
/// switch error {
/// case .unsupportedFormat:
///     showPaywallOrAlert()
/// case .invalidState, .invalidArgument:
///     // Same user-facing message; distinct codes for logging/diagnostics.
///     showInternalErrorAlert()
/// default:
///     showGenericErrorAlert()
/// }
/// ```
enum PlaybackError: Error, Equatable, Sendable {
    case unsupportedFormat
    case failedToOpenFile
    case failedToDecode
    case outputError
    case invalidState
    case invalidArgument
}
