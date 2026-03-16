# Slice 05 Micro-slices Specification

## Purpose

This document defines **Slice 5: HarmoniaCore Integration + Integration Tests**
for HarmoniaPlayer, and marks **service-layer completion**.

Slice 5 wires real HarmoniaCore-Swift services into `HarmoniaCoreProvider`,
bridges the synchronous HarmoniaCore interface to the async protocols used by
`AppState`, adds format gating for Pro-only formats, and validates the complete
system end-to-end through integration tests using real audio files.

---

## Slice 5 Overview

### Goals
- Bridge `HarmoniaCore.PlaybackService` (sync) to async `HarmoniaPlayer.PlaybackService`
- Bridge `TagReaderPort` (sync, `TagBundle`) to async `TagReaderService` (returns `Track`)
- Replace placeholder classes in `HarmoniaCoreProvider` with real adapter instances
- Add format gating to `AppState.play(trackID:)`: reject FLAC/DSF/DFF on Free tier
  before any service call
- Validate the complete system end-to-end with real `HarmoniaCoreProvider` and real
  audio bundle resources

### Non-goals
- Real-time `currentTime` polling / timer-based updates (future)
- Album artwork loading (future)
- Auto-advance to next track on completion (future)
- Repeat / shuffle modes (future)
- SwiftUI views / UI implementation

### Dependencies
- Requires: Slice 4 complete — `AppState` has full async playback control with
  `playbackState`, `currentTime`, `duration`, and transport methods
- Provides: service layer complete — all audio services wired end-to-end with real HarmoniaCore-Swift

---

## Slice 5-A: HarmoniaCore Adapters + Format Gating

### Goal
Implement the sync-to-async adapter classes, wire them into `HarmoniaCoreProvider`,
and add format gating to `AppState.play(trackID:)`. Covered by unit tests using
`FakePlaybackService` — no real audio I/O in this sub-slice.

### Scope
- Add `HarmoniaPlaybackServiceAdapter`: wraps `HarmoniaCore.DefaultPlaybackService`,
  conforms to async `HarmoniaPlayer.PlaybackService`; maps `HarmoniaCore.PlaybackState`
  to `HarmoniaPlayer.PlaybackState`; bridges sync `throws` to `async throws`
- Add `HarmoniaTagReaderAdapter`: wraps `AVMetadataTagReaderAdapter`, conforms to
  async `TagReaderService`; maps `TagBundle` fields to `Track`; falls back to
  URL-derived title when `bundle.title` is `nil`
- Update `HarmoniaCoreProvider`: `import HarmoniaCore`, construct real
  `DefaultPlaybackService` wrapped in `HarmoniaPlaybackServiceAdapter` from
  `makePlaybackService(isProUser:)`, construct real `AVMetadataTagReaderAdapter`
  wrapped in `HarmoniaTagReaderAdapter` from `makeTagReaderService()`; remove
  all placeholder classes
- Update `AppState.play(trackID:)`: check `track.url.pathExtension.lowercased()`
  against `"flac"`, `"dsf"`, `"dff"` and `featureFlags.supportsFLAC`; on mismatch
  set `currentTrack`, `lastError = .unsupportedFormat`,
  `playbackState = .error(.unsupportedFormat)`, return before `playbackService.load`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaPlaybackServiceAdapter.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaTagReaderAdapter.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaCoreProvider.swift`
  (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — format gating in `play(trackID:)`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateFormatGatingTests.swift`
  (new)

### Public API shape — HarmoniaPlaybackServiceAdapter

```swift
import Foundation
import HarmoniaCore

final class HarmoniaPlaybackServiceAdapter: PlaybackService {

    private let core: HarmoniaCore.PlaybackService

    init(core: HarmoniaCore.PlaybackService) { self.core = core }

    var state: PlaybackState {
        switch core.state {
        case .stopped:           return .stopped
        case .playing:           return .playing
        case .paused:            return .paused
        case .buffering:         return .loading
        case .error(let e):      return .error(.coreError(e.description))
        }
    }

    func load(url: URL) async throws              { try core.load(url: url) }
    func play() async throws                      { try core.play() }
    func pause() async                            { core.pause() }
    func stop() async                             { core.stop() }
    func seek(to seconds: TimeInterval) async throws { try core.seek(to: seconds) }
    func currentTime() async -> TimeInterval      { core.currentTime() }
    func duration() async -> TimeInterval         { core.duration() }
}
```

### Public API shape — HarmoniaTagReaderAdapter

```swift
import Foundation
import HarmoniaCore

final class HarmoniaTagReaderAdapter: TagReaderService {

    private let port: TagReaderPort

    init(port: TagReaderPort) { self.port = port }

    func readMetadata(for url: URL) async throws -> Track {
        let bundle = try port.read(url: url)
        return Track(
            url: url,
            title:  bundle.title  ?? url.deletingPathExtension().lastPathComponent,
            artist: bundle.artist ?? "",
            album:  bundle.album  ?? ""
        )
    }
}
```

### AppState.play(trackID:) — format gating addition

```swift
func play(trackID: Track.ID) async {
    guard let track = playlist.tracks.first(where: { $0.id == trackID }) else {
        currentTrack = nil
        return
    }
    currentTrack = track

    let ext = track.url.pathExtension.lowercased()
    if (ext == "flac" || ext == "dsf" || ext == "dff") && !featureFlags.supportsFLAC {
        lastError = .unsupportedFormat
        playbackState = .error(.unsupportedFormat)
        return
    }

    playbackState = .loading
    do {
        try await playbackService.load(url: track.url)
        duration = await playbackService.duration()
        try await playbackService.play()
        playbackState = .playing
    } catch {
        let mapped = mapToPlaybackError(error)
        lastError = mapped
        playbackState = .error(mapped)
    }
}
```

### TDD matrix — Slice 5-A

| Test | Given | When | Then |
|------|-------|------|------|
| `testFormatGating_FLAC_FreeTier_SetsUnsupportedFormat` | Free, `.flac` | `play(trackID:)` | `lastError == .unsupportedFormat` |
| `testFormatGating_FLAC_FreeTier_SetsErrorState` | Free, `.flac` | `play(trackID:)` | `playbackState == .error(.unsupportedFormat)` |
| `testFormatGating_FLAC_FreeTier_NoServiceCalls` | Free, `.flac` | `play(trackID:)` | `loadCallCount == 0` |
| `testFormatGating_FLAC_FreeTier_SetsCurrentTrack` | Free, `.flac` | `play(trackID:)` | `currentTrack == track` |
| `testFormatGating_DSF_FreeTier_SetsUnsupportedFormat` | Free, `.dsf` | `play(trackID:)` | `lastError == .unsupportedFormat` |
| `testFormatGating_DFF_FreeTier_SetsUnsupportedFormat` | Free, `.dff` | `play(trackID:)` | `lastError == .unsupportedFormat` |
| `testFormatGating_FLAC_ProTier_Proceeds` | Pro, `.flac` | `play(trackID:)` | `loadCallCount == 1` |
| `testFormatGating_MP3_FreeTier_Proceeds` | Free, `.mp3` | `play(trackID:)` | `loadCallCount == 1` |
| `testFormatGating_M4A_FreeTier_Proceeds` | Free, `.m4a` | `play(trackID:)` | `loadCallCount == 1` |

### Done criteria
- `HarmoniaPlaybackServiceAdapter` compiles; bridges sync HarmoniaCore to async protocol
- `HarmoniaTagReaderAdapter` compiles; maps `TagBundle` → `Track` with correct fallbacks
- `HarmoniaCoreProvider` uses real adapters; all placeholder classes removed;
  `// TODO: import HarmoniaCore` removed
- `AppState.play(trackID:)` rejects `.flac` / `.dsf` / `.dff` on Free tier before any
  service call
- All 5-A tests green; all Slice 1–4 tests still green

### Suggested commit message
```
feat(slice 5-A): add HarmoniaCore adapters and format gating with TDD

- Add HarmoniaPlaybackServiceAdapter: bridges sync DefaultPlaybackService
  to async HarmoniaPlayer.PlaybackService; maps HarmoniaCore.PlaybackState
- Add HarmoniaTagReaderAdapter: bridges TagReaderPort to async TagReaderService;
  maps TagBundle to Track with URL-derived title fallback
- Update HarmoniaCoreProvider: real adapter instances; remove placeholder classes
- Add format gating to AppState.play(trackID:): reject flac/dsf/dff on Free tier
  before playbackService.load; set lastError and playbackState = .error
- Add AppStateFormatGatingTests (9 cases)
```

---

## Slice 5-B: Integration Tests

### Goal
Validate the complete system using real `HarmoniaCoreProvider` and real audio
bundle resources. No fake service implementations used in this file.

### Scope
- Add `IntegrationTests.swift` using `HarmoniaCoreProvider` directly
- Add five audio resource files to the test target bundle
- Use `XCTSkip` (not `XCTFail`) when a bundle resource is missing

### Files
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/IntegrationTests.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/Resources/Audio/test_tagged.mp3`
  (new — valid MP3, ID3 tags: title ≠ filename)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/Resources/Audio/test_playback.mp3`
  (new — valid MP3, ≥ 3 seconds)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/Resources/Audio/test_track2.mp3`
  (new — second valid MP3)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/Resources/Audio/test_corrupt.mp3`
  (new — zero-byte file)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/Resources/Audio/test_format.flac`
  (new — any content, `.flac` extension)

### TDD matrix — Slice 5-B

| Test | Given | When | Then |
|------|-------|------|------|
| `testIntegration_CompletePlaybackFlow` | Real MP3 | `load` → `play(trackID:)` | `playbackState == .playing` |
| `testIntegration_MetadataEnrichment` | Tagged MP3 | `load(urls:)` | `track.title != url.lastPathComponent` |
| `testIntegration_CorruptFile_SetsError` | Zero-byte `.mp3` | `load` → `play(trackID:)` | `lastError != nil` |
| `testIntegration_UnsupportedFormat_Free` | `.flac`, Free tier | `load` → `play(trackID:)` | `lastError == .unsupportedFormat` |
| `testIntegration_TrackSwitching` | 2 valid MP3s | `play(track1)` → `play(track2)` | `currentTrack == track2`, `.playing` |
| `testIntegration_StopResetsState` | Playing | `stop()` | `.stopped`, `currentTime == 0` |
| `testIntegration_PauseSetsPausedState` | Playing | `pause()` | `playbackState == .paused` |
| `testIntegration_SeekUpdatesCurrentTime` | Playing | `seek(to: 1.0)` | `currentTime == 1.0 ± 0.5` |

### Done criteria
- `IntegrationTests.swift` compiles using `HarmoniaCoreProvider` (no fakes)
- All 8 integration tests pass with real audio resources in bundle
- All 7 `HarmoniaPlaybackServiceAdapter` methods exercised by integration tests
- Audio resources added to test target under Build Phases → Copy Bundle Resources
- All Slice 1–5-A tests still green

### Suggested commit message
```
feat(slice 5-B): add integration tests with real HarmoniaCore services

- Add IntegrationTests.swift: 8 cases using HarmoniaCoreProvider
  (complete flow, metadata enrichment, corrupt file, format gating,
  track switching, stop reset, pause, seek)
- Cover all 7 HarmoniaPlaybackServiceAdapter methods via integration tests
- Add test audio resources: test_tagged.mp3, test_playback.mp3,
  test_track2.mp3, test_corrupt.mp3, test_format.flac
- Use XCTSkip for missing bundle resources
```

---

## Slice 5 Completion Gate

- ✅ `HarmoniaPlaybackServiceAdapter` bridges sync HarmoniaCore to async protocol
- ✅ `HarmoniaTagReaderAdapter` maps `TagBundle` → `Track` with fallbacks
- ✅ `HarmoniaCoreProvider` uses real adapters; no placeholder classes remain
- ✅ `AppState.play(trackID:)` rejects FLAC/DSF/DFF on Free tier before service call
- ✅ All 5-A format gating tests green (9 cases)
- ✅ All 5-B integration tests green (8 cases)
- ✅ All 7 `HarmoniaPlaybackServiceAdapter` methods exercised by integration tests
- ✅ All Slice 1–4 tests still green
- ✅ No module boundary violations (`import HarmoniaCore` only in Integration Layer)
- ✅ `// TODO: import HarmoniaCore` removed from `HarmoniaCoreProvider`

### Verification

```bash
⌘U in Xcode
```

Expected output:
```
Slice 1 tests:   All passing
Slice 2 tests:   All passing
Slice 3 tests:   All passing
Slice 4 tests:   All passing
Slice 5-A tests: All passing
Slice 5-B tests: All passing
```

---

## Related Slices

- **Slice 1 (Foundation)** — `HarmoniaCoreProvider` first introduced as placeholder
- **Slice 3-B/C (Metadata)** — async `TagReaderService` pattern reused in `HarmoniaTagReaderAdapter`
- **Slice 4-C (play(trackID:))** — load-and-play flow extended with format gating in 5-A
- **Slice 4-B (Transport Controls)** — `mapToPlaybackError` helper reused unchanged