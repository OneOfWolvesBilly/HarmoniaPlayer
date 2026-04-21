//
//  ErrorReportService.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Builds a mailto URL for the "Report Issue" button on the playback-error
//  alert. Phase 1 error reporting: no network, no PII beyond file path, no
//  telemetry — user composes the mail in Mail.app and sends it manually.
//
//  DESIGN NOTES
//  ------------
//  - Pure value type with no side effects.
//  - Does not invoke NSWorkspace.shared.open(_:) — that is the caller's job
//    (ContentView). This split keeps the service unit-testable in isolation.
//  - Does not read Bundle / ProcessInfo — caller passes versions in.
//  - No import HarmoniaCore.
//

import Foundation

struct ErrorReportService {

    static let reportEmail = "harmonia.audio.project+harmonia_player@gmail.com"
    static let subjectLine = "[HarmoniaPlayer] Error Report"

    /// Builds a mailto URL with the given detail and runtime versions.
    /// Returns nil only if URLComponents fails to produce a URL (should not
    /// happen with valid inputs).
    static func buildMailtoURL(
        detail: String,
        appVersion: String,
        osVersion: String
    ) -> URL? {
        // Body layout: one blank line between the detail and the runtime
        // metadata block, so the reader can quickly separate "what went wrong"
        // from "which build / OS it happened on".
        let body = """
        \(detail)

        App version: \(appVersion)
        macOS: \(osVersion)
        """

        // Use URLComponents + URLQueryItem so Foundation percent-encodes subject
        // and body against the RFC 3986 query-allowed character set. The `+` in
        // the Gmail alias address stays in the path (no percent-encoding), which
        // is what Mail.app expects.
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subjectLine),
            URLQueryItem(name: "body", value: body),
        ]

        return components.url
    }
}
