//
//  FileOriginService.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Application-layer abstraction for reading, writing, and clearing the
//  "source" metadata of an audio file (where the file came from).
//
//  DESIGN NOTES
//  ------------
//  - Defined in the Application Layer so AppState and views can depend on
//    it without importing HarmoniaCore or Darwin xattr APIs directly.
//  - The concrete `DarwinFileOriginAdapter` bridges this protocol to the
//    existing `ExtendedAttributeService` utility which performs the raw
//    xattr I/O against `com.apple.metadata:kMDItemWhereFroms`.
//  - `read(url:)` is non-throwing — callers treat absence as an empty list.
//  - `write(_:url:)` and `clear(url:)` surface errors via `FileOriginError`
//    so the UI can show a user-facing alert when the kernel call fails.
//

import Foundation

/// Errors surfaced from write / clear operations on file origin metadata.
///
/// Payload strings are intended for display in an alert; they describe
/// the underlying failure in a human-readable form without leaking errno
/// values or Darwin-specific concepts to the UI layer.
enum FileOriginError: Error, LocalizedError {
    case writeFailed(String)
    case clearFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let detail):
            return "Failed to write file source: \(detail)"
        case .clearFailed(let detail):
            return "Failed to clear file source: \(detail)"
        }
    }
}

/// Application-layer service for managing the "where-from" sources of a file.
///
/// Usage:
/// ```swift
/// let service: FileOriginService = DarwinFileOriginAdapter()
/// let sources = service.read(url: fileURL)
/// try service.write(["https://example.com"], url: fileURL)
/// try service.clear(url: fileURL)
/// ```
protocol FileOriginService: AnyObject {

    /// Returns the list of source URL strings attached to the file,
    /// or an empty array if none are present or the attribute cannot be read.
    ///
    /// Does not throw — absence is represented by an empty array.
    func read(url: URL) -> [String]

    /// Persists the given sources against the file.
    ///
    /// - Throws: `FileOriginError.writeFailed` if the write cannot be completed.
    func write(_ sources: [String], url: URL) throws

    /// Removes all source metadata from the file.
    ///
    /// Treats absence of the attribute as a no-op — does not throw when
    /// there is nothing to clear.
    ///
    /// - Throws: `FileOriginError.clearFailed` if a kernel-level error
    ///   other than "attribute not present" occurs.
    func clear(url: URL) throws
}
