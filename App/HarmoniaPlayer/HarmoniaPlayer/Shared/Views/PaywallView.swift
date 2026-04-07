//
//  PaywallView.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Paywall sheet presented when a Free-tier user attempts a Pro-only action.
//
//  DESIGN NOTES
//  ------------
//  - Shown via `appState.showPaywall` binding in ContentView.
//  - Calls `appState.purchasePro()` and `appState.refreshEntitlements()`.
//  - On successful purchase or restore, `isProUnlocked` is updated in AppState
//    and the sheet is dismissed automatically.
//  - `IAPError.userCancelled` is silently swallowed (no error shown).
//  - All other errors surface as a brief error message below the feature list.
//

import SwiftUI

/// Paywall sheet for promoting the Pro upgrade.
///
/// Lists Pro-only features and provides "Unlock Pro" and "Restore Purchases" actions.
/// Automatically dismisses when `isProUnlocked` transitions to `true`.
struct PaywallView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isBusy = false
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 28) {
            headerSection
            featuresSection
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            actionsSection
        }
        .padding(32)
        .frame(minWidth: 380)
        .onChange(of: appState.isProUnlocked) {
            // Auto-dismiss once Pro is confirmed (purchase or restore).
            if appState.isProUnlocked { dismiss() }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
            Text("Unlock HarmoniaPlayer Pro")
                .font(.title2.bold())
            Text("One-time purchase. No subscription.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaywallFeatureRow(
                icon: "waveform",
                title: "FLAC & DSD Playback",
                detail: "Lossless and hi-res audio formats"
            )
            PaywallFeatureRow(
                icon: "pencil.and.list.clipboard",
                title: "Tag Editor",
                detail: "Edit ID3 and MP4 metadata directly"
            )
            PaywallFeatureRow(
                icon: "text.alignleft",
                title: "Synchronised Lyrics",
                detail: "Line-by-line LRC scrolling during playback"
            )
            PaywallFeatureRow(
                icon: "infinity",
                title: "Gapless Playback",
                detail: "Seamless transitions between tracks"
            )
        }
        .padding(.horizontal, 8)
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Unlock Pro — primary CTA
            Button {
                Task { await performPurchase() }
            } label: {
                ZStack {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock Pro")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            // Restore Purchases
            Button("Restore Purchases") {
                Task { await performRestore() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isBusy)

            // Dismiss
            Button("Maybe Later") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .font(.footnote)
            .disabled(isBusy)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func performPurchase() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await appState.purchasePro()
            // onChange(of: isProUnlocked) handles dismissal.
        } catch IAPError.userCancelled {
            // User tapped Cancel in the system purchase sheet — no error shown.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRestore() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        await appState.refreshEntitlements()
        if !appState.isProUnlocked {
            errorMessage = "No previous purchase found for this Apple ID."
        }
        // If purchase found, onChange(of: isProUnlocked) handles dismissal.
    }
}

// MARK: - PaywallFeatureRow

/// A single row in the PaywallView feature list.
private struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24, alignment: .center)
                .foregroundStyle(.tint)
                .font(.body.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
