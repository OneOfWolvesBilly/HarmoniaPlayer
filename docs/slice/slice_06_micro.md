# Slice 06 Micro-slices Specification

## Purpose

This document defines **Slice 6: Navigation Logic + SwiftUI UI**
for HarmoniaPlayer.

v0.1 is complete when Slice 6-C (keyboard shortcuts) is done —
when all local playback features matching macOS Music.app are in place.

Slice 6 adds playlist navigation (next/previous track, repeat modes,
auto-advance) to `AppState` in sub-slice 6-A, then wires all published
state into a functional SwiftUI interface in sub-slice 6-B.
After Slice 6 a user can launch the app and play music without writing code.

---

## Slice 6 Overview

### Goals
- Define `RepeatMode` enum (off / all / one) and add it to `AppState`
- Add `isShuffled` toggle and shuffle-aware navigation to `AppState`
- Implement `playNextTrack()`, `playPreviousTrack()`, `cycleRepeatMode()`,
  and `trackDidFinishPlaying()` in `AppState`
- Add `FreeTierIAPManager` as the production `IAPManager` for the Free build
- Implement `TrackRowView`, `PlaylistView`, `PlayerView`, `ContentView`
- Wire `AppState` into `HarmoniaPlayerApp` via `@EnvironmentObject`
- Add XCUITest target covering core user flows

### Non-goals
- Gapless playback (future)
- Sub-100ms waveform-level audio metering (future)
- Album artwork display (future)
- Multiple playlists / playlist persistence (future)
- macOS Pro IAP / StoreKit integration (future)
- waveform display (future)

### Dependencies
- Requires: Slice 5 complete — all audio services wired end-to-end
- Provides: functional UI — user can launch app, play music, see progress, and auto-advance tracks
- v0.1 complete after Slice 6-C (keyboard shortcuts)

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
- Add `func trackDidFinishPlaying() async` — dispatches based on `repeatMode`
- Add `private var pollingTask: Task<Void, Never>?` to `AppState`
- Add `private func startPolling()` — 0.25s loop; updates `currentTime`;
  detects natural playback completion (service `.stopped` while
  `playbackState == .playing`); calls `trackDidFinishPlaying()`
- Add `private func stopPolling()` — cancels polling task
- Call `startPolling()` after `playbackState = .playing` in `play(trackID:)`
- Call `stopPolling()` at start of `stop()`

- Add `ShuffleMode.swift`: `typealias ShuffleMode = Bool` with `.off` / `.on` extensions
- Add `@Published private(set) var isShuffled: ShuffleMode = .off` to `AppState`
- Add `func toggleShuffle()` — synchronous; toggles `isShuffled`
- Update `playNextTrack()`: when `isShuffled == true`, pick random track
  (excluding `currentTrack`)

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

> **Design note:** `repeatMode == .one` only applies to natural track completion
> (`trackDidFinishPlaying`). Manual Next/Previous button presses always navigate
> the playlist regardless of repeat mode. This is designed for better user intuitiveness.
| `isShuffled == true` (any repeatMode except `.one`) | `play(trackID:)` random track (not `currentTrack`) |

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
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add repeatMode, navigation methods, polling timer)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/RepeatModeTests.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateNavigationTests.swift` (new)

- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/ShuffleMode.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add isShuffled, toggleShuffle, shuffle-aware playNextTrack)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateShuffleTests.swift` (new)

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
@Published private(set) var isShuffled: Bool = false

// New methods
func cycleRepeatMode()
func toggleShuffle()
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

### TDD matrix — Slice 6-A (Shuffle additions)

| Test | Given | When | Then |
|------|-------|------|------|
| `testIsShuffled_DefaultIsFalse` | Fresh `AppState` | read `isShuffled` | `false` |
| `testToggleShuffle_FalseToTrue` | `isShuffled == false` | `toggleShuffle()` | `isShuffled == true` |
| `testToggleShuffle_TrueToFalse` | `isShuffled == true` | `toggleShuffle()` | `isShuffled == false` |
| `testPlayNext_Shuffled_PlaysRandomTrack` | 3 tracks, `isShuffled == true` | `playNextTrack()` × 10 | at least 2 different tracks played |
| `testPlayNext_Shuffled_DoesNotRepeatCurrentTrack` | 2 tracks, playing track1, `isShuffled == true` | `playNextTrack()` | `currentTrack == track2` |

### Done criteria
- `RepeatMode` defined; `Equatable` and `Sendable` conformances verified
- `AppState.repeatMode` initialises to `.off`
- `AppState.isShuffled` initialises to `false`
- All navigation methods implemented and callable from `@MainActor` context
- All 24 Slice 6-A tests green; all Slice 1–5 tests still green

### Commit message
```
feat(slice 6-A): add RepeatMode and playlist navigation to AppState

- Add RepeatMode enum: off / all / one; Equatable, Sendable
- Add AppState.repeatMode published state (default: .off)
- Add cycleRepeatMode(): off → all → one → off
- Add playNextTrack(): advances playlist; respects repeatMode
- Add playPreviousTrack(): goes back; restarts if at first track
- Add trackDidFinishPlaying(): dispatches by repeatMode
- Add AppState.isShuffled published state (default: false)
- Add toggleShuffle(): toggles isShuffled
- Update playNextTrack(): picks random track when isShuffled == true
- Add RepeatModeTests (4 cases)
- Add AppStateNavigationTests (19 cases)
- Add AppStateShuffleTests (5 cases)
```

---

## Slice 6-B: SwiftUI UI (Click & Right-click)

### Goal
Implement the minimum SwiftUI views that let a user launch the app and play
music. All views are thin: display `AppState` published state and forward
events via `Task { await appState.method() }`. No `import HarmoniaCore`
in any View file.

### Scope
- Add `FreeTierIAPManager`: production `IAPManager`; `isProUnlocked` always `false`
- Add `TrackRowView`: displays title, artist, duration, and playing indicator
- Add `PlaylistView`:
  - Column headers: Title, Artist, Duration (click to sort ascending/descending)
  - Track list showing title, artist, duration per row
  - Footer showing total track count and total duration
  - Single-click to select (highlight); double-click to play
  - Right-click Context Menu: Play, Play Next, Remove from Playlist
  - Add-files button (`NSOpenPanel`) and drag-and-drop
  - Empty state placeholder when playlist is empty
- Add `PlayerView`:
  - Album art (read from track metadata; grey placeholder when unavailable)
  - Now-playing title and artist
  - Seek slider: shows current position / total duration; drag to seek on release
  - Transport controls: Previous / Play-Pause / Stop / Next
  - Repeat button (cycles Off → All → One via `cycleRepeatMode()`)
  - Shuffle button (toggles `isShuffled` via `toggleShuffle()`)
  - Playback status label (Playing / Paused / Stopped)
  - After last track ends (repeatMode == .off), pressing Play starts from first track
- Add `ContentView`: `HSplitView` combining `PlaylistView` and `PlayerView`
- Update `HarmoniaPlayerApp`: create `AppState` with `FreeTierIAPManager`
  and `HarmoniaCoreProvider`; inject via `.environmentObject`
- Add polling timer to `AppState`: `startPolling()` / `stopPolling()` —
  0.25s loop that updates `currentTime` and detects natural playback
  completion; calls `trackDidFinishPlaying()` when `playbackService.state`
  transitions to `.stopped` while `playbackState == .playing`
- Add `HarmoniaPlayerUITests` target with `XCUITest` suite

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/FreeTierIAPManager.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/TrackRowView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlayerView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/ContentView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add polling timer)
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
| `"shuffle-button"` | Shuffle toggle in `PlayerView` |
| `"progress-slider"` | Seek slider in `PlayerView` |
| `"now-playing-title"` | Track title label in `PlayerView` |
| `"now-playing-artist"` | Artist label in `PlayerView` |
| `"album-art"` | Album art image in `PlayerView` |
| `"playback-status-label"` | State text in `PlayerView` |

### TDD matrix — Slice 6-B (XCUITest)

| Test | Given | When | Then |
|------|-------|------|------|
| `testAppLaunches_ShowsPlaylistAndPlayer` | App launch | view loads | `add-files-button` and `play-pause-button` exist |
| `testPlayPauseButton_Exists` | App launch | view loads | `play-pause-button` accessible |
| `testStopButton_Exists` | App launch | view loads | `stop-button` accessible |
| `testProgressSlider_Exists` | App launch | view loads | `progress-slider` accessible |
| `testRepeatButton_Exists` | App launch | view loads | `repeat-button` accessible |
| `testShuffleButton_Exists` | App launch | view loads | `shuffle-button` accessible |
| `testAddFilesButton_Exists` | App launch | view loads | `add-files-button` accessible |

### Done criteria
- App launches showing `ContentView` (no blank screen / no `Text("HarmoniaPlayer")`)
- `FreeTierIAPManager` is in main target; `isProUnlocked` always returns `false`
- No `import HarmoniaCore` in any View file
- All Slice 6-B XCUITest cases pass
- All Slice 1–6-A unit tests still green

### Commit message
```
feat(slice 6-B): add SwiftUI UI with full click and right-click interactions

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

---

## Slice 6-C: Menu Bar, Settings, and Keyboard Shortcuts (= v0.1 Gate)

### Goal
Add macOS menu bar commands, a Settings window, and keyboard shortcuts so all
playback and playlist actions can be operated without a mouse.
Completing this slice marks **v0.1**.

### Scope

#### Menu Bar
- **File** menu: Add Files (⌘O)
- **Playback** menu: Play/Pause (Space), Stop (⌘.), Next (⌘→), Previous (⌘←),
  Seek Forward 5s (→), Seek Backward 5s (←), Repeat Mode (⌘R), Shuffle (⌘S)

#### Settings (⌘,)
- **Allow duplicate tracks**: toggle to allow/disallow the same URL appearing
  multiple times in one playlist. Default: off.
- Stored as `@Published var allowDuplicateTracks: Bool = false` directly in
  `AppState`. No separate `AppSettings` class. `AppState.init` signature
  unchanged. Zero test file modifications required.

#### Keyboard Shortcuts
- `Space` — Play / Pause
- `⌘.` — Stop
- `⌘→` — Next track
- `⌘←` — Previous track
- `→` — Seek forward 5 seconds
- `←` — Seek backward 5 seconds
- `⌘R` — Cycle repeat mode
- `⌘S` — Toggle shuffle
- `⌘O` — Open file picker (add files)

#### Shuffle Queue Popover
- Visible only when `isShuffled == true`
- Button in `PlaylistView` toolbar (right side, next to `+`)
- Shows a popover listing all tracks in `shuffleQueue` order
- Highlights the current track (`shuffleQueueIndex`)
- Read-only — no interaction required

> **Media Keys (F7/F8/F9) deferred.** Requires system-level `NSEvent`
> monitoring; out of scope for v0.1.

### Architecture notes
- `HarmoniaPlayerCommands` uses `@FocusedObject private var appState: AppState?`.
  `HarmoniaPlayerApp` exposes it via `.focusedSceneObject(appState)` on the
  View inside `WindowGroup`.
- "Add Files…" posts `Notification.Name.openFilePicker`. `PlaylistView` listens
  with `.onReceive` and calls its existing `openFilePicker()` method.
- `SettingsView` uses `@EnvironmentObject var appState: AppState` and binds
  directly to `$appState.allowDuplicateTracks`. No `import HarmoniaCore`.

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/HarmoniaPlayerCommands.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/SettingsView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify —
  add `@Published var allowDuplicateTracks: Bool = false`;
  update `load()` guard to `!allowDuplicateTracks && existingURLs.contains(url)`;
  fix `insertionOrder` / `shuffleQueue` update to collect added IDs during the loop,
  not filter by `existingURLs` after)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift` (modify —
  add `.commands { HarmoniaPlayerCommands() }`, `Settings` scene,
  `.focusedSceneObject(appState)`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (modify —
  add `.onReceive(NotificationCenter.default.publisher(for: .openFilePicker))`;
  add shuffle queue button + popover in toolbar)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppSettingsTests.swift` (new — 3 unit tests)
- `App/HarmoniaPlayer/HarmoniaPlayerUITests/HarmoniaPlayerUITests.swift` (modify — add 2 XCUITest cases)

### Module boundary rules (enforced)
- Menu bar and keyboard shortcuts use `.commands` in `HarmoniaPlayerApp`
- All actions forward to `AppState` via `Task { await appState?.method() }`
- No direct service calls from View or Commands layer
- `SettingsView` uses `AppState` only; no `import HarmoniaCore`

### TDD matrix — Slice 6-C

#### Unit tests (AppSettingsTests)

| Test | Given | When | Then |
|------|-------|------|------|
| `testAllowDuplicateTracks_DefaultIsFalse` | Fresh `AppState` | read `allowDuplicateTracks` | `false` |
| `testLoad_DuplicateURL_DefaultBehaviour_IsSkipped` | 1 track loaded, `allowDuplicateTracks == false` | `load(urls:)` same URL | `tracks.count == 1`, `skippedDuplicateURLs.count == 1` |
| `testLoad_DuplicateURL_WhenAllowed_IsAdded` | 1 track loaded, `allowDuplicateTracks == true` | `load(urls:)` same URL | `tracks.count == 2`, `skippedDuplicateURLs.isEmpty` |

#### XCUITest additions (HarmoniaPlayerUITests)

| Test | Given | When | Then |
|------|-------|------|------|
| `testSettingsWindow_OpensWithKeyboardShortcut` | App running | `⌘,` pressed | Settings window appears |
| `testAllowDuplicateTracksToggle_ExistsInSettings` | Settings window open | view loads | `allow-duplicates-toggle` exists |

### Done criteria
- `allowDuplicateTracks` defaults to `false` in `AppState`
- `AppState.load()` respects `allowDuplicateTracks`
- `AppState.init` signature unchanged; zero test file modifications
- "Add Files…" menu item (⌘O) fires `NSOpenPanel` via notification
- Playback menu present with all items and correct shortcuts
- Settings window opens with ⌘,
- "Allow duplicate tracks" toggle works and affects `load()` behaviour
- `.focusedSceneObject(appState)` wired in `HarmoniaPlayerApp`
- No `import HarmoniaCore` in any View, Command, or Settings file
- All 3 AppSettingsTests green
- All 2 new XCUITest cases pass
- Shuffle queue button visible in `PlaylistView` toolbar when `isShuffled == true`
- Shuffle queue popover shows tracks in `shuffleQueue` order with current track highlighted
- `trackDidFinishPlaying()` respects `shuffleQueue` in `.off` mode
- **All Slice 1–6-B tests still green**

### Commit message
```
feat(slice 6-C): add menu bar, settings, and keyboard shortcuts — v0.1 complete

- Add HarmoniaPlayerCommands: File menu (Add Files ⌘O), Playback menu
  (Play/Pause Space, Stop ⌘., Next ⌘→, Previous ⌘←,
   Seek ±5s →/←, Repeat ⌘R, Shuffle ⌘S)
- Add SettingsView: allow duplicate tracks toggle
- Add AppState.allowDuplicateTracks: default false; load() respects it
- Wire HarmoniaPlayerApp: .commands, Settings scene, .focusedSceneObject
- Wire PlaylistView: .onReceive(openFilePicker) notification
- Add AppSettingsTests: 3 unit test cases
- Add HarmoniaPlayerUITests: 2 XCUITest cases
- Fix AppState.trackDidFinishPlaying(): respect shuffleQueue in .off mode
- Add PlaylistView shuffle queue button + popover (read-only, shows current position)
```

---

## Slice 6 Completion Gate (= v0.1 Gate)

- ✅ `RepeatMode` defined; `off` / `all` / `one`
- ✅ `ShuffleMode` defined; polling timer wired
- ✅ All navigation methods in `AppState`
- ✅ Full UI: playlist + player + album art + context menu
- ✅ All 28 Slice 6-A unit tests green
- ✅ App launches showing functional UI (not blank screen)
- ✅ No `import HarmoniaCore` in any View file
- ✅ `FreeTierIAPManager` in main target
- ✅ All 7 Slice 6-B XCUITest cases pass
- ✅ All Slice 1–5 tests still green
- ✅ Playback menu with shortcuts present and functional
- ✅ "Add Files…" menu item (⌘O) functional
- ✅ Settings window opens with ⌘,
- ✅ `allowDuplicateTracks` in `AppState`; `load()` respects it
- ✅ All 3 AppSettingsTests green
- ✅ All 2 new XCUITest cases pass
- ✅ Shuffle queue popover visible and correct when `isShuffled == true`
- ✅ `trackDidFinishPlaying()` respects `shuffleQueue` in `.off` mode

### Verification

```bash
⌘U in Xcode        # unit tests + XCUITest
⌘R in Xcode        # manual verification
```


## Related Slices

- **Slice 2 (Playlist Management)** — `playlist.tracks` order used by navigation
- **Slice 4 (Playback Control)** — `play(trackID:)`, `stop()`, `seek(to:)` called by navigation methods
- **Slice 5 (Integration)** — `HarmoniaCoreProvider` used in `HarmoniaPlayerApp` production wiring
---