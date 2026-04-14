//
//  AppState+M3U8.swift
//  HarmoniaPlayer / Shared / Models
//
//  PURPOSE: M3U8 playlist import and export.
//

import Foundation

extension AppState {

    // MARK: - M3U8 Import / Export

    /// Generates M3U8 content for the active playlist and writes it to the given URL.
    ///
    /// Called by `HarmoniaPlayerCommands` after `NSSavePanel` resolves the destination.
    ///
    /// - Parameters:
    ///   - url: Destination file URL (provided by NSSavePanel).
    ///   - pathStyle: Whether to write absolute or relative paths.
    /// - Throws: If the file cannot be written.
    func writeExport(to url: URL, pathStyle: M3U8PathStyle) throws {
        let service = M3U8Service()
        let content = service.export(playlist: playlist, pathStyle: pathStyle)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads an M3U8 file, creates a new playlist tab named after the filename,
    /// and re-reads metadata via `TagReaderService` for each resolved URL.
    ///
    /// Files not found on disk are skipped and recorded in `skippedImportURLs`,
    /// which the view layer observes to present a warning alert.
    ///
    /// Called by `HarmoniaPlayerCommands` after `NSOpenPanel` resolves the source URL.
    ///
    /// - Parameter url: Source `.m3u8` file URL (provided by NSOpenPanel).
    func importPlaylist(from url: URL) async {
        isPerformingBlockingOperation = true
        defer { isPerformingBlockingOperation = false }
        skippedImportURLs = []

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            lastError = .failedToOpenFile
            return
        }

        let service = M3U8Service()
        let urls = service.parse(m3u8: content, baseURL: url)

        // Create new playlist tab named after the .m3u8 filename (without extension)
        let tabName = url.deletingPathExtension().lastPathComponent
        newPlaylist(name: tabName)

        var skipped: [URL] = []
        var addedCount = 0
        for fileURL in urls {
            guard isURLSupported(fileURL) else {
                skipped.append(fileURL)
                continue
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                skipped.append(fileURL)
                continue
            }
            do {
                let track = try await tagReaderService.readMetadata(for: fileURL)
                playlists[activePlaylistIndex].tracks.append(track)
                playlists[activePlaylistIndex].insertionOrder.append(track.id)
            } catch {
                let track = Track(url: fileURL)
                playlists[activePlaylistIndex].tracks.append(track)
                playlists[activePlaylistIndex].insertionOrder.append(track.id)
            }
            addedCount += 1
            if addedCount % Self.saveBatchSize == 0 {
                saveState()
            }
        }

        if !skipped.isEmpty {
            skippedImportURLs = skipped
        }
        saveState()
    }

    // MARK: - Private Helpers

    /// Returns `true` if the file extension is allowed in the current tier.
    private func isURLSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.allowedFormats.contains(ext)
    }
}
