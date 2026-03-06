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
/// **Cases:**
/// - `unsupportedFormat`: File format is not supported by the current
///   product variant (e.g. FLAC on Free). May trigger a paywall flow.
/// - `failedToOpenFile`: File could not be opened (missing, permission
///   denied, network unreachable, etc.).
/// - `failedToDecode`: Decoding failed after the file was opened
///   (corrupt data, partial download, etc.).
/// - `outputError`: Audio output device or engine error (device
///   disconnected, exclusive mode conflict, etc.).
/// - `coreError(String)`: Propagated error message from HarmoniaCore.
///   Carries a human-readable description for logging and display.
///
/// **Usage:**
/// ```swift
/// switch error {
/// case .unsupportedFormat:
///     showPaywallOrAlert()
/// case .coreError(let message):
///     logger.error("Core error: \(message)")
/// default:
///     showGenericErrorAlert()
/// }
/// ```
enum PlaybackError: Error, Equatable, Sendable {
    case unsupportedFormat
    case failedToOpenFile
    case failedToDecode
    case outputError
    case coreError(String)
}
