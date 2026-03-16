# Slice 06 Micro-slices Specification

## Purpose

This document defines **Slice 6: Navigation Logic + SwiftUI UI MVP**
for HarmoniaPlayer, and marks **v0.1 completion**.

Slice 6 adds playlist navigation (next/previous track, repeat modes,
auto-advance) to `AppState` in sub-slice 6-A, then wires all published
state into a functional SwiftUI interface in sub-slice 6-B.
After Slice 6 a user can launch the app and play music without writing code.

---

## Slice 6 Overview

### Goals
- Define `RepeatMode` enum (off / all / one) and add it to `AppState`
- Implement `playNextTrack()`, `playPreviousTrack()`, `cycleRepeatMode()`,
  and `trackDidFinishPlaying()` in `AppState`
- Add `FreeTierIAPManager` as the production `IAPManager` for the Free build
- Implement `TrackRowView`, `PlaylistView`, `PlayerView`, `ContentView`
- Wire `AppState` into `HarmoniaPlayerApp` via `@EnvironmentObject`
- Add XCUITest target covering core user flows

### Non-goals
- Shuffle mode (future)
- Gapless playback (future)
- Real-time `currentTime` polling / progress timer (future)
- Album artwork display (future)
- Multiple playlists / playlist persistence (future)
- macOS Pro IAP / StoreKit integration (future)
- waveform display (future)

### Dependencies
- Requires: Slice 5 complete — all audio services wired end-to-end
- Provides: v0.1 complete — user can launch app and play music

---

## Slice 6-A: Navigation Logic + RepeatMode

### Goal
Extend `AppState` with playlist navigation and repeat behaviour.
No SwiftUI code in this sub-slice. All tests use `FakePlaybackService`.

### Scope
- Add `RepeatMode` enum: `off` (default) / `all` / `one`; `Equatable`, `Sendable`
- Add `@Published private(set) var repeatMode: RepeatMode = .off` to `AppState`
- Add `func cycleRepeatMode()` — synchronous; cycles `off → all → one → off`
- Add `func playNextTrack() async` — advances playlist; respects `repeatMode`
- Add `func playPreviousTrack() async` — goes back; restarts if at first track
- Add `func trackDidFinishPlaying() async` — called by View layer on natural
  playback completion; dispatches based on `repeatMode`

### Navigation behaviour

**`playNextTrack()`**

| Condition | Action |
|-----------|--------|
| `playlist` is empty | no-op |
| `currentTrack` is `nil` | `play(trackID:)` first track |
| next track exists | `play(trackID:)` next track |
| at last track, `repeatMode == .off` | `stop()` |
| at last track, `repeatMode == .all` | `play(trackID:)` first track |
| `repeatMode == .one` | `play(trackID:)` `currentTrack` |

**`playPreviousTrack()`**

| Condition | Action |
|-----------|--------|
| `playlist` is empty | no-op |
| `currentTrack` is `nil` | `play(trackID:)` first track |
| previous track exists | `play(trackID:)` previous track |
| at first track | `seek(to: 0)` then `play(trackID:)` same track |

**`trackDidFinishPlaying()`**

| `repeatMode` | Action |
|-------------|--------|
| `.off` | `playNextTrack()` (last track → `stop()`) |
| `.all` | `playNextTrack()` (last track → first track) |
| `.one` | `play(trackID:)` `currentTrack` |
| `currentTrack` is `nil` | no-op |

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/RepeatMode.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/RepeatModeTests.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateNavigationTests.swift` (new)

### Public API shape — RepeatMode

```swift
enum RepeatMode: Equatable, Sendable {
    case off
    case all
    case one
}
```

### Public API shape — AppState additions

```swift
// Published state
@Published private(set) var repeatMode: RepeatMode = .off

// New methods
func cycleRepeatMode()
func playNextTrack() async
func playPreviousTrack() async
func trackDidFinishPlaying() async
```

### TDD matrix — Slice 6-A

| Test | Given | When | Then |
|------|-------|------|------|
| `testRepeatMode_DefaultIsOff` | Fresh `AppState` | read `repeatMode` | `.off` |
| `testCycleRepeatMode_OffToAll` | `repeatMode == .off` | `cycleRepeatMode()` | `.all` |
| `testCycleRepeatMode_AllToOne` | `repeatMode == .all` | `cycleRepeatMode()` | `.one` |
| `testCycleRepeatMode_OneToOff` | `repeatMode == .one` | `cycleRepeatMode()` | `.off` |
| `testPlayNext_EmptyPlaylist_IsNoOp` | Empty playlist | `playNextTrack()` | `playCallCount == 0` |
| `testPlayNext_NoCurrentTrack_PlaysFirst` | 2 tracks, no `currentTrack` | `playNextTrack()` | `currentTrack == track1` |
| `testPlayNext_HasNextTrack_PlaysNext` | 2 tracks, playing track1 | `playNextTrack()` | `currentTrack == track2` |
| `testPlayNext_LastTrack_RepeatOff_Stops` | 2 tracks, playing track2, `.off` | `playNextTrack()` | `playbackState == .stopped` |
| `testPlayNext_LastTrack_RepeatAll_PlaysFirst` | 2 tracks, playing track2, `.all` | `playNextTrack()` | `currentTrack == track1` |
| `testPlayNext_RepeatOne_ReplaysCurrentTrack` | 2 tracks, playing track1, `.one` | `playNextTrack()` | `currentTrack == track1`, `loadCallCount == 2` |
| `testPlayPrevious_EmptyPlaylist_IsNoOp` | Empty playlist | `playPreviousTrack()` | `playCallCount == 0` |
| `testPlayPrevious_NoCurrentTrack_PlaysFirst` | 2 tracks, no `currentTrack` | `playPreviousTrack()` | `currentTrack == track1` |
| `testPlayPrevious_HasPreviousTrack_PlaysPrevious` | 2 tracks, playing track2 | `playPreviousTrack()` | `currentTrack == track1` |
| `testPlayPrevious_FirstTrack_RestartsTrack` | 2 tracks, playing track1 | `playPreviousTrack()` | `seekCallCount == 1`, `seekedToSeconds == [0]` |
| `testTrackDidFinish_RepeatOff_HasNext_PlaysNext` | 2 tracks, playing track1, `.off` | `trackDidFinishPlaying()` | `currentTrack == track2` |
| `testTrackDidFinish_RepeatOff_LastTrack_Stops` | 2 tracks, playing track2, `.off` | `trackDidFinishPlaying()` | `playbackState == .stopped` |
| `testTrackDidFinish_RepeatAll_LastTrack_PlaysFirst` | 2 tracks, playing track2, `.all` | `trackDidFinishPlaying()` | `currentTrack == track1` |
| `testTrackDidFinish_RepeatOne_ReplaysCurrentTrack` | track1 playing, `.one` | `trackDidFinishPlaying()` | `currentTrack == track1`, `loadCallCount == 2` |
| `testTrackDidFinish_NoCurrentTrack_IsNoOp` | No `currentTrack` | `trackDidFinishPlaying()` | `playCallCount == 0` |

### Done criteria
- `RepeatMode` defined; `Equatable` and `Sendable` conformances verified
- `AppState.repeatMode` initialises to `.off`
- All 4 navigation methods implemented and callable from `@MainActor` context
- All 19 Slice 6-A tests green; all Slice 1–5 tests still green

### Commit message
```
feat(slice 6-A): add RepeatMode and playlist navigation to AppState

- Add RepeatMode enum: off / all / one; Equatable, Sendable
- Add AppState.repeatMode published state (default: .off)
- Add cycleRepeatMode(): off → all → one → off
- Add playNextTrack(): advances playlist; respects repeatMode
- Add playPreviousTrack(): goes back; restarts if at first track
- Add trackDidFinishPlaying(): dispatches by repeatMode
- Add RepeatModeTests (4 cases)
- Add AppStateNavigationTests (15 cases)
```

---

## Slice 6-B: SwiftUI UI MVP

### Goal
Implement the minimum SwiftUI views that let a user launch the app and play
music. All views are thin: display `AppState` published state and forward
events via `Task { await appState.method() }`. No `import HarmoniaCore`
in any View file.

### Scope
- Add `FreeTierIAPManager`: production `IAPManager`; `isProUnlocked` always `false`
- Add `TrackRowView`: single track row — title, duration, playing indicator
- Add `PlaylistView`: track list + add-files button (`NSOpenPanel`) +
  drag-and-drop + `Delete` key removal
- Add `PlayerView`: now-playing info, progress slider (seek on release),
  transport controls (Previous / Play-Pause / Stop / Next), Repeat button
- Add `ContentView`: `HSplitView` combining `PlaylistView` and `PlayerView`
- Update `HarmoniaPlayerApp`: create `AppState` with `FreeTierIAPManager`
  and `HarmoniaCoreProvider`; inject via `.environmentObject`
- Add `HarmoniaPlayerUITests` target with `XCUITest` suite

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/FreeTierIAPManager.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/TrackRowView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlayerView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/ContentView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerUITests/HarmoniaPlayerUITests.swift` (new target)

### Module boundary rules (enforced)
- Views import `SwiftUI` only — no `import HarmoniaCore`
- Views access state via `@EnvironmentObject var appState: AppState`
- Views trigger actions via `Task { await appState.method() }` only

### Accessibility identifiers (required for XCUITest)

| Identifier | Element |
|-----------|---------|
| `"playlist-list"` | `List` in `PlaylistView` |
| `"add-files-button"` | `+` button in `PlaylistView` |
| `"track-row-\(track.id)"` | Each row in `PlaylistView` |
| `"play-pause-button"` | Play/Pause toggle in `PlayerView` |
| `"stop-button"` | Stop button in `PlayerView` |
| `"previous-button"` | Previous button in `PlayerView` |
| `"next-button"` | Next button in `PlayerView` |
| `"repeat-button"` | Repeat cycle button in `PlayerView` |
| `"progress-slider"` | Seek slider in `PlayerView` |
| `"now-playing-title"` | Track title label in `PlayerView` |
| `"playback-status-label"` | State text in `PlayerView` |

### TDD matrix — Slice 6-B (XCUITest)

| Test | Given | When | Then |
|------|-------|------|------|
| `testAppLaunches_ShowsPlaylistAndPlayer` | App launch | view loads | `playlist-list` and `play-pause-button` exist |
| `testPlayPauseButton_Exists` | App launch | view loads | `play-pause-button` accessible |
| `testStopButton_Exists` | App launch | view loads | `stop-button` accessible |
| `testProgressSlider_Exists` | App launch | view loads | `progress-slider` accessible |
| `testRepeatButton_Exists` | App launch | view loads | `repeat-button` accessible |
| `testAddFilesButton_Exists` | App launch | view loads | `add-files-button` accessible |

### Done criteria
- App launches showing `ContentView` (no blank screen / no `Text("HarmoniaPlayer")`)
- `FreeTierIAPManager` is in main target; `isProUnlocked` always returns `false`
- No `import HarmoniaCore` in any View file
- All Slice 6-B XCUITest cases pass
- All Slice 1–6-A unit tests still green

### Commit message
```
feat(slice 6-B): add SwiftUI UI MVP and wire AppState as environment object

- Add FreeTierIAPManager: production IAPManager, isProUnlocked always false
- Add TrackRowView: title, duration, playing indicator
- Add PlaylistView: track list, add-files button, drag-and-drop, Delete key
- Add PlayerView: now-playing info, progress slider, transport controls,
  repeat button; all controls forward to AppState via Task
- Add ContentView: HSplitView combining PlaylistView and PlayerView
- Update HarmoniaPlayerApp: inject AppState(FreeTierIAPManager, HarmoniaCoreProvider)
- Add HarmoniaPlayerUITests target: 6 XCUITest cases verifying UI elements exist
```

---

## Slice 6 Completion Gate (= v0.1 Gate)

- ✅ `RepeatMode` defined; `off` / `all` / `one`
- ✅ `AppState.repeatMode` defaults to `.off`
- ✅ `playNextTrack()` respects `repeatMode` for all cases
- ✅ `playPreviousTrack()` restarts track when at first position
- ✅ `trackDidFinishPlaying()` dispatches correctly by `repeatMode`
- ✅ All 19 Slice 6-A unit tests green
- ✅ App launches showing functional UI (not blank screen)
- ✅ No `import HarmoniaCore` in any View file
- ✅ `FreeTierIAPManager` in main target
- ✅ All 6 XCUITest cases pass
- ✅ All Slice 1–5 tests still green

### Verification

```bash
⌘U in Xcode        # unit tests + XCUITest
⌘R in Xcode        # manual: launch app, drag MP3, double-click to play
```

---

## Related Slices

- **Slice 2 (Playlist Management)** — `playlist.tracks` order used by navigation
- **Slice 4 (Playback Control)** — `play(trackID:)`, `stop()`, `seek(to:)` called by navigation methods
- **Slice 5 (Integration)** — `HarmoniaCoreProvider` used in `HarmoniaPlayerApp` production wiring