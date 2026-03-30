//
//  FileInfoView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Sheet-style "Get Info" panel for a single track.
//  Displays four sections:
//    • Location   — fileName, folder, path, fileSize, modified, created (read-only)
//    • Tags       — title, artist, album, albumArtist, composer, genre, year,
//                   trackNumber/trackTotal, discNumber/discTotal, bpm, comment,
//                   replayGainTrack, replayGainAlbum (read-only)
//    • Technical  — format, duration, bitrate, sampleRate, channels (read-only)
//    • Source     — kMDItemWhereFroms URLs; supports Edit and Clear (editable)
//
//  DESIGN NOTES
//  ------------
//  - Presented as a sheet from ContentView via $appState.fileInfoTrack.
//  - ExtendedAttributeService is called directly inside this view because
//    it is a pure Darwin utility, not a HarmoniaCore service.
//    (Architecture rule: "import HarmoniaCore" is restricted to the three
//    Integration Layer adapters. ExtendedAttributeService has no HarmoniaCore
//    dependency, so calling it from a view is within bounds.)
//  - All disk I/O runs synchronously on the calling thread (xattr calls are
//    cheap; no background queue needed for these payloads).
//  - No import HarmoniaCore.
//

import SwiftUI

struct FileInfoView: View {

    // MARK: - Input

    let track: Track

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    private let xattrService = ExtendedAttributeService()

    @State private var whereSources: [String] = []
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @State private var fileAttributes: FileAttributeInfo = .empty

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("file-info-close-button")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    locationSection
                    Divider().padding(.horizontal, 16)
                    tagsSection
                    Divider().padding(.horizontal, 16)
                    technicalSection
                    Divider().padding(.horizontal, 16)
                    sourceSection
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 500, height: 640)
        .onAppear {
            loadAttributes()
            loadWhereSources()
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        InfoSection(title: "LOCATION") {
            InfoRow(label: "File Name",
                    value: track.url.lastPathComponent)
            InfoRow(label: "Folder",
                    value: track.url.deletingLastPathComponent().path)
            InfoRow(label: "Path",
                    value: track.url.path)
            InfoRow(label: "File Size",
                    value: fileSizeString)
            InfoRow(label: "Modified",
                    value: fileAttributes.modificationDate.map(dateString) ?? "\u{2014}")
            InfoRow(label: "Created",
                    value: fileAttributes.creationDate.map(dateString) ?? "\u{2014}")
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        InfoSection(title: "TAGS") {
            InfoRow(label: "Title",
                    value: track.title.isEmpty ? "\u{2014}" : track.title)
            InfoRow(label: "Artist",
                    value: track.artist.isEmpty ? "\u{2014}" : track.artist)
            InfoRow(label: "Album",
                    value: track.album.isEmpty ? "\u{2014}" : track.album)
            InfoRow(label: "Album Artist",
                    value: track.albumArtist.isEmpty ? "\u{2014}" : track.albumArtist)
            InfoRow(label: "Composer",
                    value: track.composer.isEmpty ? "\u{2014}" : track.composer)
            InfoRow(label: "Genre",
                    value: track.genre.isEmpty ? "\u{2014}" : track.genre)
            InfoRow(label: "Year",
                    value: track.year.map(String.init) ?? "\u{2014}")
            InfoRow(label: "Track",
                    value: trackNumberString)
            InfoRow(label: "Disc",
                    value: discNumberString)
            InfoRow(label: "BPM",
                    value: track.bpm.map(String.init) ?? "\u{2014}")
            InfoRow(label: "Comment",
                    value: track.comment.isEmpty ? "\u{2014}" : track.comment)
            InfoRow(label: "ReplayGain Track",
                    value: track.replayGainTrack.map { String(format: "%.2f dB", $0) } ?? "\u{2014}")
            InfoRow(label: "ReplayGain Album",
                    value: track.replayGainAlbum.map { String(format: "%.2f dB", $0) } ?? "\u{2014}")
        }
    }

    // MARK: - Technical Section

    private var technicalSection: some View {
        InfoSection(title: "TECHNICAL") {
            InfoRow(label: "Format",
                    value: track.fileFormat.isEmpty ? "\u{2014}" : track.fileFormat.uppercased())
            InfoRow(label: "Duration",
                    value: durationString(track.duration))
            InfoRow(label: "Bit Rate",
                    value: track.bitrate.map { "\($0) kbps" } ?? "\u{2014}")
            InfoRow(label: "Sample Rate",
                    value: track.sampleRate.map { String(format: "%.0f Hz", $0) } ?? "\u{2014}")
            InfoRow(label: "Channels",
                    value: channelsString(track.channels))
        }
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        InfoSection(title: "SOURCE") {
            if isEditing {
                sourceEditingContent
            } else {
                sourceReadOnlyContent
            }
        }
    }

    private var sourceReadOnlyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if whereSources.isEmpty {
                Text("(none)")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            } else {
                ForEach(whereSources, id: \.self) { source in
                    Text(source)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 8) {
                Button("Edit") {
                    editText = whereSources.joined(separator: "\n")
                    isEditing = true
                }
                .accessibilityIdentifier("source-edit-button")

                if !whereSources.isEmpty {
                    Button("Clear", role: .destructive) {
                        clearSources()
                    }
                    .accessibilityIdentifier("source-clear-button")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var sourceEditingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter one URL per line:")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 16)

            TextEditor(text: $editText)
                .font(.body)
                .frame(height: 80)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .accessibilityIdentifier("source-edit-texteditor")

            HStack(spacing: 8) {
                Button("Save") {
                    saveSources()
                }
                .accessibilityIdentifier("source-save-button")

                Button("Cancel") {
                    isEditing = false
                }
                .accessibilityIdentifier("source-cancel-button")
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Data Loading

    private func loadWhereSources() {
        whereSources = xattrService.readWhereFroms(url: track.url)
    }

    private func loadAttributes() {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: track.url.path)) ?? [:]
        fileAttributes = FileAttributeInfo(
            modificationDate: attrs[.modificationDate] as? Date,
            creationDate: attrs[.creationDate] as? Date
        )
    }

    private func clearSources() {
        try? xattrService.clearWhereFroms(url: track.url)
        loadWhereSources()
    }

    private func saveSources() {
        let lines = editText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try? xattrService.writeWhereFroms(lines, url: track.url)
        isEditing = false
        loadWhereSources()
    }

    // MARK: - Formatting Helpers

    private var fileSizeString: String {
        if let size = track.fileSize {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: track.url.path)) ?? [:]
        if let size = attrs[.size] as? Int {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        return "\u{2014}"
    }

    private var trackNumberString: String {
        switch (track.trackNumber, track.trackTotal) {
        case (nil, _):          return "\u{2014}"
        case (let n?, nil):     return "\(n)"
        case (let n?, let t?):  return "\(n) / \(t)"
        }
    }

    private var discNumberString: String {
        switch (track.discNumber, track.discTotal) {
        case (nil, _):          return "\u{2014}"
        case (let n?, nil):     return "\(n)"
        case (let n?, let t?):  return "\(n) / \(t)"
        }
    }

    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "\u{2014}" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func channelsString(_ channels: Int?) -> String {
        switch channels {
        case 1:        return "1 (Mono)"
        case 2:        return "2 (Stereo)"
        case let n?:   return "\(n)"
        case nil:      return "\u{2014}"
        }
    }

    // MARK: - Supporting Types

    private struct FileAttributeInfo {
        let modificationDate: Date?
        let creationDate: Date?
        static let empty = FileAttributeInfo(modificationDate: nil, creationDate: nil)
    }
}

// MARK: - InfoSection

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            content()
        }
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .frame(width: 128, alignment: .trailing)
                .padding(.trailing, 12)
            Text(value)
                .font(.callout)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }
}
