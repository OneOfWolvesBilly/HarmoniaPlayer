//
//  TagReaderService.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation

/// Tag reader service interface
///
/// Abstracts metadata extraction from audio files.
/// Implementations may use HarmoniaCore-Swift tag ports or OS-level APIs.
///
/// **Slice 1 Note:**
/// In Foundation slice, this interface is defined but full metadata
/// extraction is implemented in later slices.
protocol TagReaderService: AnyObject {
    
    /// Read metadata from audio file
    ///
    /// - Parameter url: URL of the audio file
    /// - Returns: Track populated with available metadata
    /// - Throws: Error if file cannot be read
    ///
    /// **Metadata extracted:**
    /// - Title (from tags or filename)
    /// - Artist
    /// - Album
    /// - Duration
    /// - Technical info (bitrate, sampleRate, channels, fileSize)
    func readMetadata(for url: URL) async throws -> Track

    /// Current schema version of the metadata reading logic.
    ///
    /// Matches `TagBundle.currentSchemaVersion` in HarmoniaCore.
    /// Used by `AppState.refreshMetadataIfNeeded()` to detect tracks
    /// persisted by an older schema and trigger background re-reads.
    var currentSchemaVersion: Int { get }
}
