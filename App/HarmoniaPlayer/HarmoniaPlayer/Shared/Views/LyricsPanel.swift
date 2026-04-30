//
//  LyricsPanel.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  Lyrics display column (Slice 9-J).
//
//  Rendered as a third column inside `ContentView`'s `HSplitView`,
//  pushed in from the right when `appState.showLyrics` is true.
//
//  - Loads content lazily on appear via `LyricsService.resolveContent`
//  - Source picker (Embedded / .lrc) shown when both available
//  - Language picker shown when source is .embedded with multiple variants
//  - Encoding picker shown when source is .lrc
//  - Decoding failures show a localised inline message
//  - No-lyrics state shows a "Recheck" button so users can drop in a
//    sidecar .lrc and refresh without re-loading the track
//  - Read-only (no edit) per Slice 9-J non-goals
//

import SwiftUI

struct LyricsPanel: View {
    @EnvironmentObject private var appState: AppState

    /// Resolved display content. `nil` until first load attempt.
    @State private var content: String?

    /// Localised error message when decode fails. `nil` when content loaded OK.
    @State private var errorMessage: String?

    /// L10n helper using AppState's selected-language bundle.
    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: appState.languageBundle, comment: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { reload() }
        .onChange(of: appState.currentTrack?.id) { _, _ in reload() }
        .onChange(of: appState.lyricsResolution?.currentSource) { _, _ in reload() }
        .onChange(of: appState.lyricsResolution?.currentLanguage) { _, _ in reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(L("lyrics_title"))
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Controls (source / language / encoding pickers)

    private var controls: some View {
        HStack(spacing: 12) {
            sourcePicker
            languagePicker
            encodingPicker
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sourcePicker: some View {
        if let resolution = appState.lyricsResolution,
           resolution.availableSources.count > 1,
           let current = resolution.currentSource {
            Picker(L("lyrics_source"), selection: Binding<LyricsSource>(
                get: { current },
                set: { appState.setLyricsSource($0) }
            )) {
                if resolution.availableSources.contains(.lrc) {
                    Text(L("lyrics_source_lrc")).tag(LyricsSource.lrc)
                }
                if resolution.availableSources.contains(.embedded) {
                    Text(L("lyrics_source_embedded")).tag(LyricsSource.embedded)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        if let resolution = appState.lyricsResolution,
           resolution.currentSource == .embedded,
           resolution.availableLanguages.count > 1 {
            Picker(L("lyrics_language"), selection: Binding<String?>(
                get: { resolution.currentLanguage },
                set: { appState.setLyricsLanguage($0) }
            )) {
                ForEach(resolution.availableLanguages, id: \.self) { code in
                    Text(displayName(forLanguageCode: code))
                        .tag(code as String?)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var encodingPicker: some View {
        if appState.lyricsResolution?.currentSource == .lrc {
            Menu {
                Button(L("lyrics_encoding_auto"))   { appState.setLyricsEncoding("auto") }
                Button(L("lyrics_encoding_utf8"))   { appState.setLyricsEncoding("utf-8") }
                Button(L("lyrics_encoding_gb18030")) { appState.setLyricsEncoding("gb18030") }
                Button(L("lyrics_encoding_big5"))   { appState.setLyricsEncoding("big5") }
                Button(L("lyrics_encoding_shift_jis")) { appState.setLyricsEncoding("shift-jis") }
            } label: {
                Label(L("lyrics_encoding"), systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let content, !content.isEmpty {
            ScrollView {
                Text(content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        } else if appState.lyricsResolution?.hasAny == false
                  || appState.lyricsResolution == nil {
            VStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(L("lyrics_none_available"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                Button {
                    appState.recheckLyrics()
                    reload()
                } label: {
                    Label(L("lyrics_recheck"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Loading

    private func reload() {
        guard let track = appState.currentTrack,
              let resolution = appState.lyricsResolution,
              let source = resolution.currentSource else {
            content = nil
            errorMessage = nil
            return
        }

        let pref = appState.lyricsPreferenceStore.load(for: track)
        let encodingName = pref?.encoding

        do {
            let text = try appState.lyricsService.resolveContent(
                for: track,
                source: source,
                languageCode: resolution.currentLanguage,
                encodingName: encodingName
            )
            content = text
            errorMessage = nil
        } catch {
            content = nil
            errorMessage = L("lyrics_decode_failed")
        }
    }

    /// Maps an ISO 639-2 language code to a localised display name.
    /// Falls back to the raw code if Locale cannot resolve it; uses
    /// `lyrics_language_undefined` for `nil`.
    private func displayName(forLanguageCode code: String?) -> String {
        guard let code else {
            return L("lyrics_language_undefined")
        }
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code
    }
}
