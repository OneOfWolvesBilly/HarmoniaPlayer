//
//  LyricsService.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Resolves lyrics for a given Track from embedded USLT frames or a
//  sidecar .lrc file. Handles encoding detection and LRC timestamp stripping.
//
//  DESIGN NOTES
//  ------------
//  - No HarmoniaCore import — pure Application Layer.
//  - DefaultLyricsService takes `preferredLanguageCode: String` for testability;
//    production default: `Locale.current.languageCode ?? ""`.
//  - Sidecar search and FileManager access are encapsulated here; no FM calls
//    in AppState or Views.
//  - Extension point (v0.15): sidecar candidate URLs are listed inline
//    inside findSidecarURL(for:); v0.15 appends entries without touching
//    other callers.
//  - GB18030 / Big5 are not public Swift.Encoding constants; they are
//    constructed once as static helpers via CFStringConvertEncodingToNSStringEncoding.
//

import CoreFoundation
import Foundation

// MARK: - Protocol

/// Resolves lyrics availability and content for a given track.
protocol LyricsService: AnyObject {
    /// Fast synchronous check: which sources are available and what is the default.
    /// Does NOT read file content (only checks existence).
    func resolveAvailability(for track: Track) -> LyricsResolution

    /// Slow path: read actual content for the given source/language/encoding.
    /// - Parameters:
    ///   - track: The track to resolve content for.
    ///   - source: `.embedded` or `.lrc`.
    ///   - languageCode: ISO 639-2 code; `nil` uses first variant.
    ///   - encodingName: IANA charset name; `nil` or `"auto"` triggers auto-detection.
    func resolveContent(
        for track: Track,
        source: LyricsSource,
        languageCode: String?,
        encodingName: String?
    ) throws -> String

    /// Strips LRC-style timestamps and metadata headers from raw text.
    func stripLRCTimestamps(_ raw: String) -> String

    /// Auto-detects the encoding of raw bytes using a fallback chain.
    func detectEncoding(of data: Data) -> String.Encoding
}

// MARK: - Errors

enum LyricsServiceError: Error {
    case noEmbeddedLyrics
    case sidecarNotFound
    case decodingFailed
}

// MARK: - DefaultLyricsService

/// Production implementation of `LyricsService`.
final class DefaultLyricsService: LyricsService {

    // MARK: - Encoding constants

    /// GB18030 (Simplified Chinese). Not a public Swift.Encoding constant.
    static let gb18030 = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// Big5 (Traditional Chinese). Not a public Swift.Encoding constant.
    static let big5 = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)))

    // MARK: - Dependencies

    /// BCP47 language code used for preferred-language matching.
    /// Injected as a plain String for testability — avoids Locale API in tests.
    /// Production default: `Locale.current.language.languageCode?.identifier ?? ""`
    private let preferredLanguageCode: String

    // MARK: - Initialization

    /// - Parameter preferredLanguageCode: BCP47 code for language preference
    ///   matching (e.g. `"en"`, `"zh"`, `"ja"`). Defaults to system locale.
    init(preferredLanguageCode: String = Locale.current.language.languageCode?.identifier ?? "") {
        self.preferredLanguageCode = preferredLanguageCode
    }

    // MARK: - LyricsService

    func resolveAvailability(for track: Track) -> LyricsResolution {
        let hasUSLT = !(track.lyrics?.isEmpty ?? true)
        let sidecarURL = findSidecarURL(for: track)
        let hasLRC = sidecarURL != nil

        guard hasUSLT || hasLRC else {
            return .none
        }

        var availableSources: Set<LyricsSource> = []
        if hasUSLT { availableSources.insert(.embedded) }
        if hasLRC  { availableSources.insert(.lrc) }

        // Default source priority: .lrc > .embedded
        let defaultSource: LyricsSource = hasLRC ? .lrc : .embedded

        // Language variants only applicable for .embedded source
        let availableLanguages: [String?]
        let currentLanguage: String?

        if defaultSource == .embedded, let variants = track.lyrics, !variants.isEmpty {
            availableLanguages = variants.map { $0.languageCode }
            currentLanguage = resolvePreferredLanguageCode(from: variants)
        } else {
            availableLanguages = []
            currentLanguage = nil
        }

        return LyricsResolution(
            hasAny: true,
            currentSource: defaultSource,
            availableSources: availableSources,
            availableLanguages: availableLanguages,
            currentLanguage: currentLanguage,
            content: nil
        )
    }

    func resolveContent(
        for track: Track,
        source: LyricsSource,
        languageCode: String?,
        encodingName: String?
    ) throws -> String {
        switch source {
        case .embedded:
            guard let variants = track.lyrics, !variants.isEmpty else {
                throw LyricsServiceError.noEmbeddedLyrics
            }
            let variant: LyricsLanguageVariant
            if let code = languageCode,
               let match = variants.first(where: { $0.languageCode == code }) {
                variant = match
            } else {
                variant = variants[0]
            }
            return variant.text

        case .lrc:
            guard let lrcURL = findSidecarURL(for: track) else {
                throw LyricsServiceError.sidecarNotFound
            }

            // Slice 9-M Layer 1: sibling read via Related Items.
            //
            // Plain `Data(contentsOf: lrcURL)` fails under the App Sandbox
            // with NSCocoaErrorDomain Code=257 because the security-scoped
            // bookmark on `track.url` does not extend to the sibling file.
            // Apple's Related Items mechanism: declare `.lrc` as
            // NSIsRelatedItemType=YES + CFBundleTypeRole=Editor in
            // CFBundleDocumentTypes (see Info.plist), register an
            // NSFilePresenter whose primaryPresentedItemURL is the user-
            // selected primary file, then issue an NSFileCoordinator
            // coordinated read. The sandbox issues a related-item extension
            // for the duration of the coordinated block.
            //
            // add/remove pairing is enforced by manual code review:
            // NSFileCoordinator does not expose a public API to enumerate
            // registered presenters, so unit testing the symmetry is not
            // possible (see spec v1.2 §Layer 1).
            let presenter = SiblingFilePresenter(
                primaryItemURL: track.url,
                presentedItemURL: lrcURL
            )
            NSFileCoordinator.addFilePresenter(presenter)
            defer { NSFileCoordinator.removeFilePresenter(presenter) }

            let coordinator = NSFileCoordinator(filePresenter: presenter)
            var coordError: NSError?
            var readData: Data?
            var readError: Error?
            coordinator.coordinate(
                readingItemAt: lrcURL,
                options: [],
                error: &coordError
            ) { effectiveURL in
                do {
                    readData = try Data(contentsOf: effectiveURL)
                } catch {
                    readError = error
                }
            }
            if let coordError {
                throw coordError
            }
            if let readError {
                throw readError
            }
            guard let data = readData else {
                throw LyricsServiceError.decodingFailed
            }
            let enc: String.Encoding
            if let name = encodingName,
               name != "auto",
               !name.isEmpty {
                enc = encoding(fromIANAName: name)
            } else {
                enc = detectEncoding(of: data)
            }
            guard let text = String(data: data, encoding: enc) else {
                throw LyricsServiceError.decodingFailed
            }
            return stripLRCTimestamps(text)
        }
    }

    func stripLRCTimestamps(_ raw: String) -> String {
        // Regex: timestamp prefix [mm:ss] or [mm:ss.xx]
        // NSRegularExpression for macOS 13+ compat (no Swift Regex needed)
        let lines = raw.components(separatedBy: "\n")
        var output: [String] = []

        for line in lines {
            // Blank line — preserve
            if line.isEmpty {
                output.append("")
                continue
            }

            // Metadata tag line: entire line is [letters:anything]
            // e.g. [ti:title], [ar:artist], [al:album], [by:lyricist], [offset:200]
            if isMetadataTagLine(line) {
                // Remove entirely (do not append to output)
                continue
            }

            // Timed lyric line: [mm:ss[.xx]]text
            // Strip all leading timestamp blocks; keep remainder
            let stripped = stripLeadingTimestamps(from: line)
            output.append(stripped)
        }

        return output.joined(separator: "\n")
    }

    func detectEncoding(of data: Data) -> String.Encoding {
        // 1. UTF-8
        if String(data: data, encoding: .utf8) != nil { return .utf8 }

        // 2. UTF-16 with BOM
        if data.count >= 2 {
            let bom = data.prefix(2)
            if (bom == Data([0xFF, 0xFE]) || bom == Data([0xFE, 0xFF])),
               String(data: data, encoding: .utf16) != nil {
                return .utf16
            }
        }

        // 3. GB18030 (Simplified Chinese)
        if String(data: data, encoding: DefaultLyricsService.gb18030) != nil {
            return DefaultLyricsService.gb18030
        }

        // 4. Big5 (Traditional Chinese)
        if String(data: data, encoding: DefaultLyricsService.big5) != nil {
            return DefaultLyricsService.big5
        }

        // 5. Shift-JIS (Japanese)
        if String(data: data, encoding: .shiftJIS) != nil { return .shiftJIS }

        // 6. Fallback: ISO-8859-1 (always succeeds)
        return .isoLatin1
    }

    // MARK: - Private helpers

    /// Finds the first existing sidecar .lrc file in priority order.
    ///
    /// Search order (priority high → low):
    ///   1. `<dir>/<name>.lrc`           (e.g. `song.lrc` for `song.mp3`)
    ///   2. `<dir>/<filename-with-ext>.lrc`  (e.g. `song.mp3.lrc`)
    ///   3. `<dir>/Lyrics/<name>.lrc`
    ///   4. `<dir>/lyrics/<name>.lrc`
    ///
    /// **v0.15 extension point**: append additional candidate URLs here
    /// (e.g. `<artist> - <title>.lrc`, `.txt` extension) without changing
    /// callers.
    private func findSidecarURL(for track: Track) -> URL? {
        let url = track.url
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext  = url.lastPathComponent

        let candidates: [URL] = [
            dir.appendingPathComponent("\(name).lrc"),
            dir.appendingPathComponent("\(ext).lrc"),
            dir.appendingPathComponent("Lyrics/\(name).lrc"),
            dir.appendingPathComponent("lyrics/\(name).lrc"),
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Maps IANA charset name to Swift.Encoding.
    private func encoding(fromIANAName name: String) -> String.Encoding {
        switch name.lowercased() {
        case "utf-8",  "utf8":                         return .utf8
        case "utf-16", "utf16":                        return .utf16
        case "gb18030", "gb-18030", "gb_18030-2000":   return DefaultLyricsService.gb18030
        case "big5":                                   return DefaultLyricsService.big5
        case "shift-jis", "shift_jis", "shiftjis":    return .shiftJIS
        case "iso-8859-1", "latin1", "iso_8859-1":    return .isoLatin1
        default:                                       return .utf8
        }
    }

    /// Picks the preferred language code from USLT variants using system locale.
    ///
    /// Match order:
    /// 1. Direct ISO 639-2 match with locale language code
    /// 2. ISO 639-2 → BCP47 approximate mapping
    /// 3. Fallback to first variant's code
    private func resolvePreferredLanguageCode(
        from variants: [LyricsLanguageVariant]
    ) -> String? {
        let bcp47 = preferredLanguageCode

        // Direct match (rare but possible if file uses BCP47 codes)
        if let direct = variants.first(where: { $0.languageCode == bcp47 }) {
            return direct.languageCode
        }

        // ISO 639-2 bibliographic → BCP47 mapping (common languages)
        let iso2ToBCP47: [String: String] = [
            "eng": "en", "chi": "zh", "zho": "zh", "cmn": "zh",
            "jpn": "ja", "fra": "fr", "deu": "de", "kor": "ko",
            "spa": "es", "por": "pt", "ita": "it", "rus": "ru",
            "ara": "ar", "hin": "hi", "tha": "th", "vie": "vi",
        ]
        if let match = variants.first(where: {
            guard let code = $0.languageCode else { return false }
            return iso2ToBCP47[code] == bcp47
        }) {
            return match.languageCode
        }

        // Fallback: first variant (may be nil if undeclared)
        return variants.first?.languageCode
    }

    /// Returns true if the line is purely an LRC metadata tag
    /// (e.g. `[ti:title]`, `[ar:artist]`, `[offset:200]`).
    private func isMetadataTagLine(_ line: String) -> Bool {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return false }
        // Extract tag name (before the colon)
        let inner = String(line.dropFirst().dropLast())
        guard let colonIdx = inner.firstIndex(of: ":") else { return false }
        let tagName = String(inner[inner.startIndex ..< colonIdx])
        // Tag name must be letters only (not digits — that would be a timestamp)
        return !tagName.isEmpty && tagName.allSatisfy({ $0.isLetter })
    }

    /// Strips all leading `[mm:ss[.xx]]` timestamp blocks from a lyric line.
    private func stripLeadingTimestamps(from line: String) -> String {
        var result = line
        // Pattern: [digits:digits[.digits]] at start
        let pattern = #"^\[\d{1,2}:\d{2}(?:\.\d+)?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }
        // Repeatedly strip leading timestamp until none remain
        while true {
            let range = NSRange(result.startIndex..., in: result)
            if let match = regex.firstMatch(in: result, range: range),
               let swiftRange = Range(match.range, in: result) {
                result = String(result[swiftRange.upperBound...])
            } else {
                break
            }
        }
        return result
    }
}

// MARK: - Slice 9-M Layer 3 helper

/// View-layer-facing helper that maps any error from `LyricsService` to a
/// `Localizable.strings` key for `LyricsPanel` to display.
///
/// Categories (green-phase impl per spec §Layer 3):
///
/// 1. `NSError` with `domain == NSCocoaErrorDomain && code == 257`
///    (sandbox permission denied — sibling reads without a related-item
///    extension hit this) → `"lyrics_file_inaccessible"`.
/// 2. `LyricsServiceError.decodingFailed` and any other unrecognised error
///    → `"lyrics_decode_failed"` (catch-all fallback; the genuine "encoding
///    is wrong" reason for that string now that permission errors no
///    longer leak into this branch).
///
/// `LyricsServiceError.noEmbeddedLyrics` and `.sidecarNotFound` are not
/// categorised here because the surrounding `LyricsPanel.reload()` flow
/// short-circuits via `LyricsResolution.hasAny == false` before any
/// `resolveContent` call can throw them — they never reach
/// `LyricsPanel.errorMessage` in practice.
///
/// - Parameter error: Any error thrown by `LyricsService.resolveContent`.
/// - Returns: `Localizable.strings` key for the user-facing error message.
func lyricsErrorMessageKey(for error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == 257 {
        return "lyrics_file_inaccessible"
    }
    return "lyrics_decode_failed"
}
