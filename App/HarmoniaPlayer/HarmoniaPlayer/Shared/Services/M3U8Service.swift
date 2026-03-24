//
//  M3U8Service.swift
//  HarmoniaPlayer / Shared / Services
//

import Foundation

// MARK: - Path Style

/// Controls how file paths are written in the exported M3U8 string.
enum M3U8PathStyle {
    /// Write absolute POSIX paths (e.g. `/Users/chen/Music/track.mp3`).
    case absolute

    /// Write paths relative to the given `.m3u8` file URL.
    /// Used when the playlist will be opened from a USB drive or shared folder.
    case relative(to: URL)
}

// MARK: - Service

/// Pure value type responsible for M3U8 serialisation and parsing.
///
/// Has no I/O or platform dependencies — all file access is handled
/// by the caller (AppState or HarmoniaPlayerCommands).
struct M3U8Service {

    // MARK: - Export

    /// Generates an M3U8 string from a playlist.
    ///
    /// - Parameters:
    ///   - playlist: The playlist to export.
    ///   - pathStyle: Whether to write absolute or relative paths.
    /// - Returns: M3U8-formatted string ready to be written to disk.
    func export(playlist: Playlist, pathStyle: M3U8PathStyle) -> String {
        var lines: [String] = ["#EXTM3U"]

        for track in playlist.tracks {
            let duration = track.duration > 0 ? Int(track.duration) : -1
            let display = track.artist.isEmpty
                ? track.title
                : "\(track.artist) - \(track.title)"
            lines.append("#EXTINF:\(duration),\(display)")

            let pathString: String
            switch pathStyle {
            case .absolute:
                pathString = track.url.path
            case .relative(let m3u8URL):
                pathString = relativePath(from: m3u8URL, to: track.url)
            }
            lines.append(pathString)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Parse

    /// Parses an M3U8 string and returns absolute file URLs.
    ///
    /// Comment lines (`#EXTM3U`, `#EXTINF`, blank lines) are ignored.
    /// Relative paths are resolved against `baseURL` (the directory containing
    /// the `.m3u8` file). If `baseURL` is `nil`, relative paths are returned
    /// as-is resolved against the current directory.
    ///
    /// - Parameters:
    ///   - m3u8: Raw M3U8 string.
    ///   - baseURL: URL of the `.m3u8` file itself (used to resolve relative paths).
    /// - Returns: Array of absolute `file://` URLs.
    func parse(m3u8: String, baseURL: URL?) -> [URL] {
        let baseDirectory = baseURL.map { $0.deletingLastPathComponent() }

        return m3u8
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line -> URL? in
                if line.hasPrefix("/") {
                    // Absolute POSIX path
                    return URL(fileURLWithPath: line)
                } else if line.hasPrefix("file://") {
                    // Already a file URL
                    return URL(string: line)
                } else {
                    // Relative path — resolve against base directory
                    let base = baseDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    return base.appendingPathComponent(line)
                }
            }
    }

    // MARK: - Private Helpers

    /// Computes a relative path from `m3u8URL` to `targetURL`.
    ///
    /// Both URLs must be absolute `file://` paths.
    /// Returns a POSIX relative path string (e.g. `rock/track.mp3` or `../other/track.mp3`).
    private func relativePath(from m3u8URL: URL, to targetURL: URL) -> String {
        let baseDir = m3u8URL.deletingLastPathComponent()
        let baseComponents = baseDir.pathComponents
        let targetComponents = targetURL.pathComponents

        // Find common prefix length
        var commonLength = 0
        let minLength = min(baseComponents.count, targetComponents.count)
        while commonLength < minLength &&
              baseComponents[commonLength] == targetComponents[commonLength] {
            commonLength += 1
        }

        // Steps up from base to common ancestor
        let stepsUp = baseComponents.count - commonLength
        let upParts = Array(repeating: "..", count: stepsUp)

        // Steps down from common ancestor to target
        let downParts = Array(targetComponents[commonLength...])

        let parts = upParts + downParts
        return parts.joined(separator: "/")
    }
}
