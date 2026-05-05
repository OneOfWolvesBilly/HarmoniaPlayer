//
//  MPNowPlayingAdapter.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  Slice 9-L: production NowPlayingService implementation.
//
//  Bridges NowPlayingService (Application Layer abstraction) to the
//  system Now Playing surface — Control Center widget, lock screen,
//  Bluetooth headphones, media keys, Siri — via two `MediaPlayer`
//  framework singletons:
//
//    - MPNowPlayingInfoCenter   (push: metadata, state, elapsed time)
//    - MPRemoteCommandCenter    (pull: user actions on the system UI)
//
//  This file is the only place in HarmoniaPlayer that imports the
//  MediaPlayer framework. It conforms to NowPlayingService with no
//  knowledge of AppState or NowPlayingCoordinator — those layers
//  drive it through the protocol surface.
//

import Foundation
import AppKit
import MediaPlayer

/// Production adapter for `NowPlayingService` on Apple platforms.
///
/// Manages the `MPNowPlayingInfoCenter.default()` info dictionary
/// and `MPRemoteCommandCenter.shared()` handler registrations.
/// Constructed once at app launch via
/// `HarmoniaCoreProvider.makeNowPlayingService()`; lives the
/// process lifetime so Bluetooth / media-key / Siri commands work
/// at any moment regardless of current playback state.
final class MPNowPlayingAdapter: NowPlayingService {

    // MARK: - Pull-side callbacks (set by NowPlayingCoordinator)

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onStop: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    // MARK: - System singletons

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    // MARK: - Init

    init() {
        registerSupportedCommands()
        disableUnsupportedCommands()
        observeAppTermination()
    }

    // MARK: - Push surface

    func updateCurrentTrack(_ track: Track?) {
        guard let track else {
            clear()
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0 as Double,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0 as Double
        ]
        if let artwork = makeArtwork(from: track.artworkData) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        infoCenter.nowPlayingInfo = info
    }

    func updatePlaybackState(_ state: PlaybackState, rate: Double) {
        infoCenter.playbackState = mapPlaybackState(state)
        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        infoCenter.nowPlayingInfo = info
    }

    func updateElapsedTime(_ seconds: Double) {
        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        infoCenter.nowPlayingInfo = info
    }

    func clear() {
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .unknown
    }

    // MARK: - Helpers

    private func mapPlaybackState(_ state: PlaybackState) -> MPNowPlayingPlaybackState {
        switch state {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return .stopped
        case .idle, .loading, .error:
            return .unknown
        }
    }

    /// Build an `MPMediaItemArtwork` from raw embedded artwork data.
    /// Falls back to the application icon when the bytes fail to
    /// decode or are nil. Returns nil only when even the application
    /// icon cannot be obtained, in which case the caller skips the
    /// artwork key entirely and the system shows a generic icon.
    private func makeArtwork(from data: Data?) -> MPMediaItemArtwork? {
        if let data, let image = NSImage(data: data) {
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            return MPMediaItemArtwork(boundsSize: appIcon.size) { _ in appIcon }
        }
        return nil
    }

    // MARK: - MPRemoteCommandCenter wiring

    private func registerSupportedCommands() {
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?()
            return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.onStop?()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.onSeek?(positionEvent.positionTime)
            return .success
        }
    }

    /// Per spec 9-L Non-goals: keep the system widget UI clean by
    /// disabling commands the app does not implement, so the system
    /// does not render buttons that would do nothing if pressed.
    private func disableUnsupportedCommands() {
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.enableLanguageOptionCommand.isEnabled = false
        commandCenter.disableLanguageOptionCommand.isEnabled = false
        commandCenter.ratingCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false
    }

    // MARK: - App termination

    private func observeAppTermination() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc
    private func handleAppWillTerminate() {
        clear()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
