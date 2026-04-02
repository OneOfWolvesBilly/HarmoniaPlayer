//
//  MarqueeText.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  A scrolling text view for displaying long strings in constrained widths.
//  Used by MiniPlayerView to display track title and artist.
//
//  DESIGN NOTES
//  ------------
//  - If text fits within available width, displays statically with no animation.
//  - If text overflows, animates a continuous left-scroll loop:
//      1. Pause (hp.marqueePause seconds) at the start.
//      2. Scroll left until the text end is visible.
//      3. Instant reset to start position.
//      4. Repeat.
//  - Scroll speed and pause duration read from @AppStorage so SettingsView
//    and the right-click popover changes take effect immediately.
//  - No import HarmoniaCore.
//

import SwiftUI

/// A text view that scrolls horizontally when its content exceeds available width.
///
/// Reads scroll speed (`hp.marqueeSpeed` pt/s, default 40) and pause duration
/// (`hp.marqueePause` seconds, default 1.0) from `@AppStorage` so settings
/// changes take effect immediately without restart.
struct MarqueeText: View {

    let text: String
    let font: Font

    @AppStorage("hp.marqueeSpeed") private var speed: Double = 40.0
    @AppStorage("hp.marqueePause") private var pause: Double = 1.0

    @State private var offset: CGFloat = 0
    @State private var needsScrolling = false
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeo.size.width
                                    containerWidth = geo.size.width
                                    needsScrolling = textWidth > containerWidth
                                    restartAnimation()
                                }
                                .onChange(of: text) { _, _ in
                                    offset = 0
                                    textWidth = textGeo.size.width
                                    needsScrolling = textWidth > containerWidth
                                    restartAnimation()
                                }
                                .onChange(of: speed) { _, _ in restartAnimation() }
                                .onChange(of: pause) { _, _ in restartAnimation() }
                        }
                    )

                Text(text)
                    .font(font)
                    .fixedSize()
                    .offset(x: offset)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
                needsScrolling = textWidth > newWidth
                restartAnimation()
            }
        }
    }

    private func restartAnimation() {
        animationTask?.cancel()
        offset = 0
        guard needsScrolling else { return }
        animationTask = Task { await runLoop() }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let pauseNanos = UInt64(max(0, pause) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: pauseNanos)
            guard !Task.isCancelled else { return }

            let scrollDistance = textWidth - containerWidth + 16
            let duration = scrollDistance / max(speed, 1)

            await MainActor.run {
                withAnimation(.linear(duration: duration)) {
                    offset = -scrollDistance
                }
            }

            let animNanos = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: animNanos)
            guard !Task.isCancelled else { return }

            await MainActor.run { offset = 0 }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
