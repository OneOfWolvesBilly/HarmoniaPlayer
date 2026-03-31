//
//  PlaybackFocusedValues.swift
//  HarmoniaPlayer / Shared / Views
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Defines a FocusedValueKey for propagating live PlaybackState to
//  HarmoniaPlayerCommands.
//
//  DESIGN NOTES
//  ------------
//  @FocusedObject does not reliably re-evaluate Commands body on property
//  changes within the focused object. @FocusedValue with a scalar value
//  (PlaybackState) re-evaluates Commands correctly on every state change.
//
//  ContentView sets this value via:
//    .focusedValue(\.playbackState, appState.playbackState)
//
//  HarmoniaPlayerCommands reads it via:
//    @FocusedValue(\.playbackState) private var focusedPlaybackState: PlaybackState?
//

import SwiftUI

// MARK: - FocusedValueKey

/// FocusedValueKey carrying the current PlaybackState across the SwiftUI
/// focus system into Commands.
struct PlaybackStateFocusedKey: FocusedValueKey {
    typealias Value = PlaybackState
}

// MARK: - FocusedValues extension

extension FocusedValues {
    /// Current playback state propagated from the key window's ContentView.
    var playbackState: PlaybackState? {
        get { self[PlaybackStateFocusedKey.self] }
        set { self[PlaybackStateFocusedKey.self] = newValue }
    }
}
