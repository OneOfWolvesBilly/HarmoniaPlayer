# Slice 07 Micro-slices Specification

## Purpose

This document defines **Slice 7: Persistence, Volume, Multiple Playlists,
Drag-to-Reorder, and UI Localisation** for HarmoniaPlayer.

Slice 7 is the first post-v0.1 slice. It adds data persistence so the app
remembers the user's playlist and settings across launches, plus several UI
improvements that bring HarmoniaPlayer closer to a production music player.

---

## Slice 7 Overview

### Goals
- Add volume control to PlayerView
- Support multiple named playlists with tabs
- Import and export playlists as M3U8
- Allow drag-to-reorder tracks within a playlist
- Persist playlist, sort state, and settings across app launches
- Localise all UI text into 24 languages

### Non-goals
- iCloud sync (future)
- Playlist export/import (future)
- Gapless playback (future)
- macOS Pro IAP / StoreKit integration (future)

### Constraints
- All persistence uses `UserDefaults`; no external files in this slice
- `import HarmoniaCore` restricted to Integration Layer files only
- HarmoniaCore changes in 7-B must not break existing HarmoniaCore tests

### Dependencies
- Requires: Slice 6 complete — app launches, plays music, menu bar and
  keyboard shortcuts functional
- Provides: Full persistence, volume control, multi-playlist, localisation

---

## Slice 7-A: Volume Control

### Goal
Add a volume slider to `PlayerView`. Volume is controlled end-to-end through
the full stack: `AudioOutputPort` → `DefaultPlaybackService` →
`HarmoniaPlaybackServiceAdapter` → `AppState` → `PlayerView`.

> **Dependency note:** Volume state persistence requires Slice 7-E (Persistence).
> The slider is fully functional without persistence — it just resets to 1.0 on relaunch.

### Scope

#### HarmoniaCore-Swift changes

- Add `setVolume(_ volume: Float)` to `AudioOutputPort` protocol
  - Range 0.0–1.0; clamped by implementations
- Implement in `AVAudioEngineOutputAdapter` using `engine.mainMixerNode.outputVolume`
- Add `setVolumeCallCount` tracking + no-op implementation to `MockAudioOutputPort`
- Add `func setVolume(_ volume: Float)` to `PlaybackService` protocol
- Implement in `DefaultPlaybackService` — forwards to `AudioOutputPort`
- Update specs: `docs/specs/03_ports.md` (AudioOutputPort section),
  `docs/specs/04_services.md` (PlaybackService section),
  `docs/impl/02_01_apple.adapters_impl.md`

#### HarmoniaPlayer changes

- Add `func setVolume(_ volume: Float) async` to `HarmoniaPlayer.PlaybackService` protocol
- Implement in `HarmoniaPlaybackServiceAdapter` — delegates to `core.setVolume()`
- Add `setVolumeCallCount` + `lastSetVolume` stub to `FakePlaybackService`
- Add `@Published var volume: Float = 1.0` to `AppState`
- Add `func setVolume(_ volume: Float) async` to `AppState`
  — clamps to 0.0–1.0, sets `self.volume`, calls `playbackService.setVolume()`
- Add volume slider to `PlayerView` (range 0.0–1.0, default 1.0)
  — bind to `appState.volume`; call `appState.setVolume()` on change
- Volume state persisted via Slice 7-A (`volume` saved to `UserDefaults`)

### Files (HarmoniaCore-Swift)
- `Sources/HarmoniaCore/Ports/AudioOutputPort.swift` (modify — add `setVolume`)
- `Sources/HarmoniaCore/Services/PlaybackService.swift` (modify — add `setVolume` to protocol)
- `Sources/HarmoniaCore/Services/DefaultPlaybackService.swift` (modify — implement `setVolume`)
- `Sources/HarmoniaCore/Adapters/AVAudioEngineOutputAdapter.swift` (modify — implement `setVolume`)
- `Tests/HarmoniaCoreTests/TestSupport/MockAudioOutputPort.swift` (modify — add `setVolumeCallCount` + no-op)
- `docs/specs/03_ports.md` (modify — add `setVolume` to AudioOutputPort section)
- `docs/specs/04_services.md` (modify — add `setVolume` to PlaybackService section)
- `docs/impl/02_01_apple.adapters_impl.md` (modify — document `setVolume` implementation)

### Files (HarmoniaPlayer)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/PlaybackService.swift` (modify — add `setVolume`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaPlaybackServiceAdapter.swift` (modify — bridge `setVolume`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add `volume`, `setVolume()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlayerView.swift` (modify — add volume slider)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/FakeInfrastructure/FakeCoreProvider.swift` (modify — add `setVolumeCallCount`, `lastSetVolume` to `FakePlaybackService`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateVolumeTests.swift` (new — unit tests)

### Public API shape

```swift
// HarmoniaCore: AudioOutputPort addition
func setVolume(_ volume: Float)  // clamp to 0.0–1.0

// HarmoniaCore: PlaybackService protocol addition
func setVolume(_ volume: Float)

// HarmoniaPlayer: PlaybackService protocol addition
func setVolume(_ volume: Float) async

// AppState additions
@Published var volume: Float = 1.0

func setVolume(_ volume: Float) async
// Implementation: clamp to 0...1, set self.volume, call playbackService.setVolume()
```

### Done criteria
- Volume slider visible in `PlayerView`
- Dragging slider changes playback volume in real time
- Clamping: values outside 0.0–1.0 are silently clamped
- All HarmoniaCore tests still green
- All HarmoniaPlayer Slice 1–6 tests still green
- `AppStateVolumeTests` green

### Suggested commit message
```
feat(slice 7-A): add volume control end-to-end

HarmoniaCore:
- Add setVolume() to AudioOutputPort protocol
- Add setVolume() to PlaybackService protocol
- Implement in AVAudioEngineOutputAdapter (mainMixerNode.outputVolume)
- Implement in DefaultPlaybackService

HarmoniaPlayer:
- Add setVolume() to PlaybackService protocol
- Bridge in HarmoniaPlaybackServiceAdapter
- Add AppState.volume (@Published) and AppState.setVolume()
- Add volume slider to PlayerView
- Add AppStateVolumeTests
```


## Slice 7-B: Multiple Playlist Tabs

### Scope
- `AppState` holds `[Playlist]` instead of a single `Playlist`
- `AppState.activePlaylistIndex` tracks the current playlist
- `PlaylistView` shows tabs at the top (one per playlist)
- Menu bar additions: File → New Playlist, Rename Playlist, Delete Playlist
- All playlists persisted via Slice 7-A

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/HarmoniaPlayerCommands.swift` (modify)

### Public API shape

```swift
// AppState changes
@Published private(set) var playlists: [Playlist]
@Published private(set) var activePlaylistIndex: Int

var playlist: Playlist { playlists[activePlaylistIndex] }  // computed accessor

func newPlaylist(name: String)
func renamePlaylist(at index: Int, name: String)
func deletePlaylist(at index: Int)
```

### Done criteria
- Can create, rename, and delete playlists
- Each playlist has independent track list and sort state
- Switching playlists updates the now-playing context
- All playlists survive app relaunch

### Suggested commit message
```
feat(slice 7-B): add multiple playlist tabs with create/rename/delete
```

---

## Slice 7-C: Playlist Import/Export (M3U8)

### Goal
Allow users to export playlists as M3U8 files and import M3U8 files from
other apps (VLC, foobar2000, Apple Music). Uses absolute paths throughout.

### Scope
- **Export**: `File → Export Playlist…` saves current playlist as `.m3u8`
  with absolute paths and `#EXTINF` metadata
- **Import**: `File → Import Playlist…` reads `.m3u8`, resolves absolute paths,
  re-reads metadata via `TagReaderService` (ignores `#EXTINF` display text)
- `#EXTINF` on export: `<duration_seconds>,<artist> - <title>`
- Files not found on import: skipped with a warning alert listing missing paths

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/M3U8Service.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/HarmoniaPlayerCommands.swift` (modify — add Export/Import to File menu)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add `exportPlaylist()`, `importPlaylist(from:)`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/M3U8ServiceTests.swift` (new)

### Public API shape

```swift
// M3U8Service
struct M3U8Service {
    func export(playlist: Playlist) -> String   // returns M3U8 string
    func parse(m3u8: String) -> [URL]           // returns absolute URLs
}

// AppState additions
func exportPlaylist() async         // opens NSSavePanel, writes .m3u8
func importPlaylist(from url: URL) async   // reads .m3u8, loads tracks
```

### Done criteria
- Export produces valid M3U8 with absolute paths readable by VLC / foobar2000
- Import reads M3U8, re-reads metadata via `TagReaderService`
- Missing files on import show warning alert with list of skipped paths
- All M3U8ServiceTests green

### Suggested commit message
```
feat(slice 7-C): add M3U8 playlist import/export

- Add M3U8Service: export playlist to .m3u8 (absolute paths)
- Add M3U8Service: parse .m3u8, return absolute URLs
- Add AppState.exportPlaylist(): NSSavePanel → write .m3u8
- Add AppState.importPlaylist(): read .m3u8 → TagReaderService
- Add File menu: Export Playlist…, Import Playlist…
- Add M3U8ServiceTests
```


## Slice 7-D: Drag-to-Reorder

### Scope
- SwiftUI `Table` does not support `onMove`; implement custom drag using
  `.onDrag` / `.onDrop` on table rows, or migrate to `List` for native reorder
- Reorder updates `playlist.tracks` and `playlist.insertionOrder`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify if needed)

### Public API shape
No new public API. Uses existing `moveTrack(fromOffsets:toOffset:)` in `AppState`.

### Done criteria
- Tracks can be dragged to a new position within the playlist
- Track order is updated after drag
- Reordered order persists via Slice 7-A

### Suggested commit message
```
feat(slice 7-D): add drag-to-reorder tracks in PlaylistView
```

---

## Slice 7-E: Persistence

### Scope
- `Track` conforms to `Codable`
- `Playlist` conforms to `Codable`
- `AppState` saves playlist and sort state to `UserDefaults` on quit;
  restores on launch
- `AppState` saves and restores `allowDuplicateTracks`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Track.swift` (modify — add `Codable`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Playlist.swift` (modify — add `Codable`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — save/restore on launch/quit)

### Public API shape

```swift
// AppState additions
func saveState()     // called on app quit
func restoreState()  // called on app launch
```

### Done criteria
- Playlist survives app quit and relaunch
- Sort state survives app quit and relaunch
- `allowDuplicateTracks` survives app quit and relaunch

### Suggested commit message
```
feat(slice 7-E): add persistence for playlist and settings via UserDefaults
```

---

## Slice 7-F: UI Localisation

### Supported languages
en, zh-Hant, zh-Hans, ja, ko, fr, de, es, pt, it, cs, sv, fi, nb, ru, pl,
et, lv, lt, ar, th, vi, id, hi

### Scope
- Replace all hardcoded UI strings with `String(localized:)` or `LocalizedStringKey`
- Create `Localizable.strings` for all 24 languages
- Add `selectedLanguage` setting to `AppState` (persisted via Slice 7-A)
- Override app language at runtime using `Bundle` locale override
- Settings: language picker (system default + 24 languages)
- Arabic (`ar`) is RTL — verify all views in RTL mode

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add `selectedLanguage`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/SettingsView.swift` (modify — add language picker)
- All View files (modify — replace hardcoded strings)
- `App/HarmoniaPlayer/HarmoniaPlayer/Resources/` (new — `Localizable.strings` × 24)

### Public API shape

```swift
// AppState addition
@Published var selectedLanguage: String = "system"  // "system" or BCP-47 tag
```

### Done criteria
- All UI text is localised
- Changing language in Settings updates UI immediately
- Language selection persists across launches
- RTL layout verified for Arabic

### Suggested commit message
```
feat(slice 7-F): add UI localisation for 24 languages
```

---

## Slice 7 TDD Matrix

> Detailed test cases to be defined per sub-slice during implementation.
> Each sub-slice follows the same TDD red → green → commit cycle.

### Slice 7-E — Persistence (unit tests)

| Test | Given | When | Then |
|------|-------|------|------|
| `testSaveAndRestore_Playlist_SurvivesRelaunch` | Playlist with 3 tracks | `saveState()` then `restoreState()` | `playlist.tracks.count == 3` |
| `testSaveAndRestore_SortKey_Survives` | `sortKey == .title` | `saveState()` then `restoreState()` | `sortKey == .title` |
| `testSaveAndRestore_AllowDuplicates_Survives` | `allowDuplicateTracks == true` | `saveState()` then `restoreState()` | `allowDuplicateTracks == true` |

### Slice 7-A — Volume (unit tests)

| Test | Given | When | Then |
|------|-------|------|------|
| `testSetVolume_ForwardsToService` | Playing state | `appState.setVolume(0.5)` | `fakeService.setVolumeCallCount == 1` |
| `testSetVolume_Clamps_AboveOne` | Any state | `appState.setVolume(1.5)` | called with `1.0` |
| `testSetVolume_Clamps_BelowZero` | Any state | `appState.setVolume(-0.1)` | called with `0.0` |

### Slice 7-B — Multiple Playlists (unit tests)

| Test | Given | When | Then |
|------|-------|------|------|
| `testNewPlaylist_IncreasesCount` | 1 playlist | `newPlaylist(name:)` | `playlists.count == 2` |
| `testDeletePlaylist_DecreasesCount` | 2 playlists | `deletePlaylist(at: 1)` | `playlists.count == 1` |
| `testActivePlaylist_SwitchesContext` | 2 playlists | `activePlaylistIndex = 1` | `playlist == playlists[1]` |

---

### Slice 7-C — Playlist Import/Export (unit tests)

| Test | Given | When | Then |
|------|-------|------|------|
| `testExport_ProducesValidM3U8` | Playlist with 2 tracks | `export(playlist:)` | output starts with `#EXTM3U`, contains absolute paths |
| `testExport_EXTINF_Format` | Track with title/artist/duration | `export(playlist:)` | `#EXTINF:237,Artist - Title` |
| `testParse_ReturnsAbsoluteURLs` | Valid M3U8 string | `parse(m3u8:)` | returns 2 `file://` URLs |
| `testParse_IgnoresCommentLines` | M3U8 with `#EXTM3U` and `#EXTINF` | `parse(m3u8:)` | only returns file path lines |

---

## Slice 7 Completion Gate

### Required

- ✅ Volume slider visible and functional in PlayerView
- ✅ Multiple playlists supported with tabs
- ✅ Playlist export as M3U8 with absolute paths
- ✅ Playlist import from M3U8, metadata re-read via TagReaderService
- ✅ Drag-to-reorder functional within a playlist
- ✅ Playlist survives app quit and relaunch
- ✅ Sort state survives app quit and relaunch
- ✅ `allowDuplicateTracks` survives app quit and relaunch
- ✅ All UI text localised in 24 languages
- ✅ Language change in Settings takes effect immediately
- ✅ Arabic RTL layout verified
- ✅ All Slice 7 unit tests green
- ✅ All Slice 1–6 tests still green

---

## Related Slices

- **Slice 6 (UI + Menu Bar)** — provides `AppState`, `PlayerView`, `PlaylistView`,
  `HarmoniaPlayerCommands`, and `SettingsView` that Slice 7 extends