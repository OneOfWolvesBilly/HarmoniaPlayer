//
//  HarmoniaTagReaderAdapter.swift
//  HarmoniaPlayer / Shared / Services
//
//  Created on 2026-03-12.
//
//  PURPOSE
//  -------
//  Bridges HarmoniaCore.TagReaderPort (synchronous, returns TagBundle) to the
//  async HarmoniaPlayer.TagReaderService protocol that AppState depends on.
//
//  DESIGN NOTES
//  ------------
//  - Like HarmoniaPlaybackServiceAdapter, this is one of only three production
//    files in HarmoniaPlayer allowed to import HarmoniaCore.
//  - TagBundle does NOT carry a duration field. Duration is available through
//    StreamInfo (a separate decode pass), which is out of scope for this adapter.
//    Track.duration is therefore left as nil.
//
//  FIELD FALLBACK STRATEGY
//  -----------------------
//  | TagBundle field | Track field | Fallback                              |
//  |-----------------|-------------|---------------------------------------|
//  | title           | title       | URL stem (deletingPathExtension last)  |
//  | artist          | artist      | "" (empty string)                     |
//  | album           | album       | "" (empty string)                     |
//  | (none)          | duration    | nil (no duration in TagBundle)        |
//

import Foundation
import HarmoniaCore

/// Bridges the synchronous `TagReaderPort` to the async `TagReaderService` protocol.
///
/// Maps `TagBundle` fields to `Track` with URL-derived fallbacks for nil fields.
/// See the module header for the full fallback strategy table.
final class HarmoniaTagReaderAdapter: TagReaderService {

    // MARK: - Dependencies

    /// The underlying synchronous tag-reading port.
    /// Stored as the port protocol, not the concrete adapter, to keep this class
    /// open to other TagReaderPort implementations in tests or future adapters.
    private let port: TagReaderPort

    // MARK: - Initialization

    /// Creates an adapter wrapping the given synchronous tag reader port.
    /// - Parameter port: Any `TagReaderPort` implementation (e.g. `AVMetadataTagReaderAdapter`).
    init(port: TagReaderPort) {
        self.port = port
    }

    // MARK: - TagReaderService

    /// Reads metadata from the audio file at the given URL and returns a populated `Track`.
    ///
    /// Calls the synchronous `port.read(url:)` from this async context (allowed by
    /// Swift's structured concurrency) and maps the resulting `TagBundle` to a `Track`.
    ///
    /// - Parameter url: URL of the audio file to read.
    /// - Returns: A `Track` populated with whatever metadata is available.
    /// - Throws: Forwards any `CoreError` thrown by the port (e.g. `.notFound`, `.ioError`).
    func readMetadata(for url: URL) async throws -> Track {
        // Call synchronous port from async context — allowed by Swift structured concurrency.
        let bundle = try port.read(url: url)

        return Track(
            url:         url,
            // title: use TagBundle value if present; fall back to the filename without extension.
            title:       bundle.title  ?? url.deletingPathExtension().lastPathComponent,
            // artist / album: use TagBundle value if present; fall back to empty string.
            artist:      bundle.artist ?? "",
            album:       bundle.album  ?? "",
            // artworkData: pass raw image data from TagBundle if available.
            artworkData: bundle.artworkData
            // duration: intentionally omitted (nil) — TagBundle has no duration field.
        )
    }
}
