# Slice 08 Micro-slices Specification

## Purpose

This document defines **Slice 8: UX Polish, Mini Player, and ReplayGain**
for HarmoniaPlayer.

Slice 8 fixes known UX issues carried over from Slice 6-C, adds a floating
mini player window, and implements ReplayGain volume normalisation.

---

## Slice 8 Overview

### Sub-slice summary

| Sub-slice | Content | Status |
|---|---|---|
| 8-A | Menu bar UX fixes + UndoManager | ✅ |
| 8-C | Mini Player floating window | |
| 8-D | ReplayGain volume normalisation | |

> **8-B (Music Library / folder scanning)** — removed. Conflicts with the
> foobar2000 design philosophy: the app does not manage a library; users
> manage files themselves.
>
> **8-E (Play statistics + track rating)** — deferred to backlog. Fields
> (`playCount`, `lastPlayedAt`, `rating`) are already defined in `Track`
> model Group E (Slice 7-G). Can be added independently when needed.

### Goals
- Fix menu bar disabled states and Play/Pause label update issue
- Add UndoManager support for playlist operations (⌘Z / ⌘⇧Z)
- Add a compact floating mini player window
- Read ReplayGain tags and apply gain adjustment during playback

### Non-goals
- Music library / folder scanning (violates foobar2000 design philosophy)
- Play statistics and track rating (deferred to backlog)
- Tag editor (Pro feature — Slice 9)
- Equalizer / DSP plugins (requires HarmoniaCore DSP layer, future)
- AirPlay / iCloud sync (future)

### Constraints
- All Free tier features only
- `import HarmoniaCore` restricted to Integration Layer files only

### Dependencies
- Requires: Slice 7 complete — persistence, volume, multiple playlists,
  import/export, drag-to-reorder, column customization, File Info Panel,
  localisation

---

## Slice 8-A: Menu Bar UX Fixes + UndoManager ✅

### Goal
Fix two known issues in `HarmoniaPlayerCommands` carried over from Slice 6-C,
and add UndoManager support for playlist operations.

### Scope

#### Play/Pause label fix
`@FocusedObject` does not reliably re-evaluate `Commands` body when a
published property changes inside the focused object. Fixed by introducing
a `FocusedValueKey` carrying `PlaybackState` as a scalar value:

- New `PlaybackFocusedValues.swift` defines `PlaybackStateFocusedKey` and
  `FocusedValues.playbackState`
- `ContentView` propagates live state via
  `.focusedValue(\.playbackState, appState.playbackState)`
- `HarmoniaPlayerCommands` reads it via
  `@FocusedValue(\.playbackState) private var focusedPlaybackState`
- `playPauseLabel` now uses `focusedPlaybackState` instead of
  `appState?.playbackState`

#### `.disabled()` conditions

| Menu item | Disabled when | Rationale |
|---|---|---|
| Play / Pause | `playlist.tracks.isEmpty` | Nothing to play |
| Next Track | `playlist.tracks.isEmpty` | Matches `PlayerView`; works without `currentTrack` |
| Previous Track | `playlist.tracks.isEmpty` | Same; plays first track when nothing loaded |
| Stop | `playlist.tracks.isEmpty` OR `currentTrack == nil` | Needs loaded track |
| Seek Forward | `playlist.tracks.isEmpty` OR `currentTrack == nil` | Needs current position |
| Seek Backward | `playlist.tracks.isEmpty` OR `currentTrack == nil` | Needs current position |

Two computed helpers in `HarmoniaPlayerCommands`:
- `playlistIsEmpty` — used by Play/Pause, Next, Previous
- `needsActiveTrack` — used by Stop, Seek Forward, Seek Backward

#### Undo/Redo menu items
Replaced the empty `CommandGroup(replacing: .undoRedo) {}` with real
Undo / Redo items wired to `appState.undoManager`:
- ⌘Z → `appState?.undoManager.undo()`
- ⌘⇧Z → `appState?.undoManager.redo()`
- Items disabled when `canUndo` / `canRedo` is false

#### UndoManager in AppState
- New `let undoManager: UndoManager` property (injected at init for
  testability; defaults to `UndoManager()` in production)
- `load(urls:)` — registers undo that removes added tracks; nested redo
  re-appends them in original order
- `removeTrack(_:)` — captures index before mutation; undo re-inserts at
  original position; nested redo removes again
- `moveTrack(fromOffsets:toOffset:)` — captures before/after snapshots;
  undo restores `beforeTracks`; nested redo restores `afterTracks`

#### Localization
Added `menu_undo` and `menu_redo` keys in all three supported languages
(en, zh-Hant, ja).

### Files

- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaybackFocusedValues.swift`
  (new — `PlaybackStateFocusedKey`, `FocusedValues.playbackState`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/ContentView.swift`
  (modify — add `.focusedValue(\.playbackState, appState.playbackState)`)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift`
  (modify — `@FocusedValue`, `.disabled()` conditions, Undo/Redo items,
  `playlistIsEmpty`, `needsActiveTrack`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `undoManager`, update `init`, register undo in
  `load`, `removeTrack`, `moveTrack`)
- `App/HarmoniaPlayer/HarmoniaPlayer/{en,zh-Hant,ja}.lproj/Localizable.strings`
  (modify — add `menu_undo`, `menu_redo`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateUndoTests.swift`
  (new)

### Public API shape

```swift
// AppState additions
let undoManager: UndoManager  // injected; default UndoManager()

init(
    iapManager: IAPManager,
    provider: CoreServiceProviding,
    userDefaults: UserDefaults = .standard,
    undoManager: UndoManager = UndoManager()  // ← new, default preserves back-compat
)

// PlaybackFocusedValues.swift (new)
struct PlaybackStateFocusedKey: FocusedValueKey {
    typealias Value = PlaybackState
}
extension FocusedValues {
    var playbackState: PlaybackState? { get set }
}
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testUndoLoad_RemovesAddedTracks` | Empty playlist | `load(urls: [1])` → undo | `playlist.tracks.isEmpty` |
| `testUndoLoad_WithMultipleTracks` | Empty playlist | `load(urls: [3])` → undo | `playlist.tracks.isEmpty` |
| `testUndoRemoveTrack_ReInsertsTrack` | 2 tracks | `removeTrack(first)` → undo | `tracks.count == 2` |
| `testUndoMoveTrack_RestoresOrder` | 3 tracks A,B,C | move B to end → undo | order restored to A,B,C |
| `testRedoLoad_ReAddsTrack` | After undone load | redo | `tracks.count == 1` |

### Done criteria
- ✅ Play/Pause label updates reliably via `@FocusedValue`
- ✅ Playback menu items disabled when playlist is empty
- ✅ Stop / Seek Forward / Seek Backward disabled when no active track
- ✅ Next / Previous disabled only when playlist is empty (matches `PlayerView`)
- ✅ ⌘Z undoes `load` / `removeTrack` / `moveTrack`
- ✅ ⌘⇧Z redoes undone operation
- ✅ `AppStateUndoTests` (5 tests) green
- ✅ All Slice 1–7 tests still green

### Commit message
```
feat(slice 8-A): fix menu disabled states, Play/Pause label, and add UndoManager

- Add PlaybackFocusedValues.swift with FocusedValueKey for PlaybackState
- Propagate playbackState via .focusedValue in ContentView for reliable Commands updates
- Replace @FocusedObject playbackState observation with @FocusedValue in HarmoniaPlayerCommands
- Add .disabled() conditions to all Playback menu items matching PlayerView logic
  - Play/Pause, Next Track, Previous Track: disabled when playlist is empty
  - Stop, Seek Forward, Seek Backward: disabled when no active track
- Replace empty undoRedo CommandGroup with wired Undo/Redo menu items
- Add UndoManager to AppState with testable injection via init parameter
- Register undo/redo for load(urls:), removeTrack(_:), moveTrack(fromOffsets:toOffset:)
- Add AppStateUndoTests (5 tests: undo load, undo remove, undo move, redo load)
- Add menu_undo / menu_redo localization keys in en / zh-Hant / ja
```

---

## Slice 8-C: Mini Player

### Goal
Add a compact floating mini player window showing now-playing info and
basic transport controls. Users can switch between full and mini player.

### Scope
- Mini player window: title, artist, play/pause, previous, next
- `Window → Mini Player` menu item toggles between full and mini window (⌘M)
- Mini player is always on top (`.floating` window level)
- Closing mini player restores full player
- Full player and mini player share the same `AppState` — stay in sync

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/MiniPlayerView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift`
  (modify — add mini player `Window` scene)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift`
  (modify — add Window menu with ⌘M)

### Done criteria
- Mini player opens with ⌘M
- Shows current track title, artist, and transport controls
- Stays on top of other windows
- Transport controls (play/pause, previous, next) work correctly
- Full player and mini player reflect the same playback state
- All Slice 1–7 tests still green

### Suggested commit message
```
feat(slice 8-C): add mini player floating window

- Add MiniPlayerView: title, artist, play/pause, previous, next
- Add Window menu with ⌘M toggle
- Wire mini player Window scene in HarmoniaPlayerApp
```

---

## Slice 8-D: ReplayGain

### Goal
Read ReplayGain tags from audio file metadata and apply gain adjustment
during playback to normalise volume across tracks.

### Scope
- `Track.replayGainTrack` and `Track.replayGainAlbum` already defined in
  Group C (Slice 7-G) — no model changes needed
- Add `ReplayGainMode` enum: `off` / `track` / `album`
- Add `@Published var replayGainMode: ReplayGainMode = .off` to `AppState`
- Apply gain in `HarmoniaPlaybackServiceAdapter` before calling `setVolume()`:
  - `track` mode: use `replayGainTrack` if present; fall back to `replayGainAlbum`
  - `album` mode: use `replayGainAlbum` if present; fall back to `replayGainTrack`
  - `off` mode: no adjustment
- Gain value is in dB; convert to linear scale before multiplying with volume
- Settings: ReplayGain mode picker (off / track / album)

> **Dependency:** Requires `setVolume()` from Slice 7-A and
> `Track.replayGainTrack` / `Track.replayGainAlbum` from Slice 7-G.

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/ReplayGainMode.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `replayGainMode`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaPlaybackServiceAdapter.swift`
  (modify — apply ReplayGain before setVolume)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/SettingsView.swift`
  (modify — add ReplayGain mode picker)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateReplayGainTests.swift` (new)

### Public API shape

```swift
enum ReplayGainMode: Equatable, Sendable, Codable {
    case off
    case track
    case album
}

// AppState addition
@Published var replayGainMode: ReplayGainMode = .off
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testReplayGainMode_DefaultIsOff` | Fresh `AppState` | read `replayGainMode` | `.off` |
| `testReplayGain_TrackMode_AppliesTrackGain` | `replayGainTrack = -3.0`, mode `.track` | `play(trackID:)` | volume adjusted by -3.0 dB |
| `testReplayGain_AlbumMode_AppliesAlbumGain` | `replayGainAlbum = -5.0`, mode `.album` | `play(trackID:)` | volume adjusted by -5.0 dB |
| `testReplayGain_TrackMode_FallsBackToAlbum` | `replayGainTrack = nil`, `replayGainAlbum = -4.0`, mode `.track` | `play(trackID:)` | volume adjusted by -4.0 dB |
| `testReplayGain_OffMode_NoAdjustment` | `replayGainTrack = -3.0`, mode `.off` | `play(trackID:)` | volume unchanged |
| `testReplayGain_NoTag_NoAdjustment` | Both gain fields `nil`, mode `.track` | `play(trackID:)` | volume unchanged |

### Done criteria
- `ReplayGainMode` enum defined with `off` / `track` / `album`
- Gain applied when mode is not `off` and tag is present
- No volume change when mode is `off` or tag is absent
- Fallback: `track` mode falls back to album gain; `album` mode falls back
  to track gain
- Settings picker for off / track / album
- `replayGainMode` persists across launches (via 7-E Persistence)
- All AppStateReplayGainTests green
- All Slice 1–7 tests still green

### Suggested commit message
```
feat(slice 8-D): add ReplayGain volume normalisation

- Add ReplayGainMode enum: off / track / album
- Add AppState.replayGainMode (persisted)
- Apply gain in HarmoniaPlaybackServiceAdapter before setVolume()
- Add Settings ReplayGain mode picker
- Add AppStateReplayGainTests
```

---

## Slice 8 TDD Matrix

### Slice 8-A — UndoManager (unit tests) ✅

| Test | Given | When | Then |
|---|---|---|---|
| `testUndoLoad_RemovesAddedTracks` | Empty playlist | `load(urls:)` then `undo` | `playlist.tracks.isEmpty` |
| `testUndoLoad_WithMultipleTracks` | Empty playlist | `load(urls: [3 urls])` then `undo` | `playlist.tracks.isEmpty` |
| `testUndoRemoveTrack_ReInsertsTrack` | 2 tracks | `removeTrack()` then `undo` | `tracks.count == 2` |
| `testUndoMoveTrack_RestoresOrder` | 3 tracks A,B,C | `moveTrack` B to end then `undo` | order restored to A,B,C |
| `testRedoLoad_ReAddsTrack` | After undone load | `redo` | `playlist.tracks.count == 1` |

### Slice 8-D — ReplayGain (unit tests)

| Test | Given | When | Then |
|---|---|---|---|
| `testReplayGainMode_DefaultIsOff` | Fresh `AppState` | read `replayGainMode` | `.off` |
| `testReplayGain_TrackMode_AppliesTrackGain` | `replayGainTrack = -3.0`, mode `.track` | `play(trackID:)` | volume adjusted by -3.0 dB |
| `testReplayGain_AlbumMode_AppliesAlbumGain` | `replayGainAlbum = -5.0`, mode `.album` | `play(trackID:)` | volume adjusted by -5.0 dB |
| `testReplayGain_TrackMode_FallsBackToAlbum` | `replayGainTrack = nil`, `replayGainAlbum = -4.0`, mode `.track` | `play(trackID:)` | volume adjusted by -4.0 dB |
| `testReplayGain_OffMode_NoAdjustment` | `replayGainTrack = -3.0`, mode `.off` | `play(trackID:)` | volume unchanged |
| `testReplayGain_NoTag_NoAdjustment` | Both gain fields `nil`, mode `.track` | `play(trackID:)` | volume unchanged |

---

## Slice 8 Completion Gate

### Required

- ✅ Play/Pause label updates correctly on state change
- ✅ Playback menu items disabled when playlist is empty
- ✅ Stop / Seek disabled when no active track; Next / Previous only when playlist empty
- ✅ `⌘Z` / `⌘⇧Z` undo/redo all three playlist operations
- ⬜ Mini player opens with `⌘M`, stays on top
- ⬜ Mini player transport controls functional and in sync with full player
- ⬜ `ReplayGainMode` enum defined
- ⬜ ReplayGain applied when mode is enabled and tag is present
- ⬜ Fallback behaviour correct (track ↔ album)
- ⬜ `replayGainMode` persists across launches
- ✅ All Slice 8-A unit tests green
- ✅ All Slice 1–7 tests still green

---

## Related Slices

- **Slice 6 (UI + Menu Bar)** — `HarmoniaPlayerCommands` and `PlayerView`
  extended by 8-A and 8-C
- **Slice 7-A (Volume)** — `setVolume()` used by 8-D to apply ReplayGain
- **Slice 7-E (Persistence)** — `replayGainMode` persisted via UserDefaults
- **Slice 7-G (Track model)** — `replayGainTrack` / `replayGainAlbum` in
  Group C, consumed by 8-D