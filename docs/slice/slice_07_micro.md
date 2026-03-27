# Slice 07 Micro-slices Specification

## Purpose

This document defines **Slice 7: Volume Control, Multiple Playlists,
Playlist Import/Export, Drag-to-Reorder, Persistence, UI Localisation,
Column Customization, and File Info Panel** for HarmoniaPlayer.

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
- Expand `Track` model with full tag field set
- Allow users to show/hide and reorder metadata columns in PlaylistView
- Show file technical info in a File Info Panel (source URL editable)

### Non-goals
- iCloud sync (future)
- Gapless playback (future)
- Tag editing / writing (Pro feature — Slice 9)
- macOS Pro IAP / StoreKit integration (Slice 9)

### Constraints
- All persistence uses `UserDefaults`; no external files in this slice
- `import HarmoniaCore` restricted to Integration Layer files only
- HarmoniaCore changes in 7-A must not break existing HarmoniaCore tests
- Tag Editor is a Pro feature and must NOT appear in Slice 7

### Dependencies
- Requires: Slice 6 complete — app launches, plays music, menu bar and
  keyboard shortcuts functional
- Provides: Full persistence, volume control, multi-playlist, localisation,
  column customization, expanded Track model, File Info Panel

---

## Slice 7-A: Volume Control ✅

### Goal
Add a volume slider to `PlayerView`. Volume is controlled end-to-end through
the full stack: `AudioOutputPort` → `DefaultPlaybackService` →
`HarmoniaPlaybackServiceAdapter` → `AppState` → `PlayerView`.

### Scope

#### HarmoniaCore-Swift changes
- Add `setVolume(_ volume: Float)` to `AudioOutputPort` protocol (range 0.0–1.0; clamped)
- Implement in `AVAudioEngineOutputAdapter` using `engine.mainMixerNode.outputVolume`
- Add `setVolumeCallCount` tracking + no-op implementation to `MockAudioOutputPort`
- Add `func setVolume(_ volume: Float)` to `PlaybackService` protocol
- Implement in `DefaultPlaybackService` — forwards to `AudioOutputPort`

#### HarmoniaPlayer changes
- Add `func setVolume(_ volume: Float) async` to `HarmoniaPlayer.PlaybackService` protocol
- Implement in `HarmoniaPlaybackServiceAdapter` — delegates to `core.setVolume()`
- Add `setVolumeCallCount` + `lastSetVolume` stub to `FakePlaybackService`
- Add `@Published var volume: Float = 1.0` to `AppState`
- Add `func setVolume(_ volume: Float) async` to `AppState`
  — clamps to 0.0–1.0, sets `self.volume`, calls `playbackService.setVolume()`
- Add volume slider to `PlayerView` with thumb-anchored percentage label
  (appears on drag, fades after 1.5s)

### Files

#### HarmoniaCore-Swift
- `Sources/HarmoniaCore/Ports/AudioOutputPort.swift` (modify — add `setVolume`)
- `Sources/HarmoniaCore/Services/PlaybackService.swift` (modify — add `setVolume` to protocol)
- `Sources/HarmoniaCore/Services/DefaultPlaybackService.swift` (modify — implement `setVolume`)
- `Sources/HarmoniaCore/Adapters/AVAudioEngineOutputAdapter.swift` (modify — implement `setVolume`)
- `Tests/HarmoniaCoreTests/TestSupport/MockAudioOutputPort.swift` (modify — add `setVolumeCallCount`)

#### HarmoniaPlayer
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/PlaybackService.swift` (modify — add `setVolume`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaPlaybackServiceAdapter.swift` (modify — bridge `setVolume`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify — add `volume`, `setVolume()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlayerView.swift` (modify — add volume slider)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/FakeInfrastructure/FakeCoreProvider.swift` (modify — add `setVolumeCallCount`, `lastSetVolume`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateVolumeTests.swift` (new)

### Public API shape

```swift
// HarmoniaCore: AudioOutputPort addition
func setVolume(_ volume: Float)  // clamp to 0.0–1.0

// HarmoniaPlayer: PlaybackService protocol addition
func setVolume(_ volume: Float) async

// AppState additions
@Published var volume: Float = 1.0

func setVolume(_ volume: Float) async
// Implementation: clamp to 0...1, set self.volume, call playbackService.setVolume()
```

### TDD matrix

| Test | Given | When | Then |
|------|-------|------|------|
| `testSetVolume_ForwardsToService` | Any state | `appState.setVolume(0.5)` | `fakeService.setVolumeCallCount == 1` |
| `testSetVolume_Clamps_AboveOne` | Any state | `appState.setVolume(1.5)` | `fakeService.lastSetVolume == 1.0` |
| `testSetVolume_Clamps_BelowZero` | Any state | `appState.setVolume(-0.1)` | `fakeService.lastSetVolume == 0.0` |

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

---

## Slice 7-B: Multiple Playlist Tabs ✅

### Goal
Replace the single `playlist: Playlist` in `AppState` with `playlists: [Playlist]`
and a tab bar in `PlaylistView`.

### Scope
- `AppState` holds `[Playlist]` instead of a single `Playlist`
- `AppState.activePlaylistIndex` tracks the current playlist
- `PlaylistView` shows tabs at the top (one per playlist) with inline rename
- Menu bar additions: File → New Playlist, Rename Playlist, Delete Playlist
- Deleting the currently playing playlist stops playback and clears `currentTrack`
- New playlist auto-numbered (`"Playlist N"`, lowest unused N)
- 🔊 icon on tab whose `playlist.id == playingPlaylistID`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateMultiPlaylistTests.swift` (new)

### Public API shape

```swift
// AppState changes
@Published private(set) var playlists: [Playlist]
@Published var activePlaylistIndex: Int

var playlist: Playlist { playlists[activePlaylistIndex] }  // computed accessor

func newPlaylist(name: String)
func renamePlaylist(at index: Int, name: String)
func deletePlaylist(at index: Int)
```

### TDD matrix

| Test | Given | When | Then |
|------|-------|------|------|
| `testInitialState_HasOnePlaylist` | Fresh `AppState` | — | `playlists.count == 1` |
| `testInitialState_ActiveIndexIsZero` | Fresh `AppState` | — | `activePlaylistIndex == 0` |
| `testPlaylist_ComputedReturnsActive` | 2 playlists, index = 1 | read `playlist` | `playlists[1]` |
| `testNewPlaylist_IncreasesCount` | 1 playlist | `newPlaylist(name: "Rock")` | `playlists.count == 2` |
| `testNewPlaylist_SetsActiveIndex` | 1 playlist | `newPlaylist(name: "Rock")` | `activePlaylistIndex == 1` |
| `testNewPlaylist_EmptyName_UsesDefault` | 1 playlist | `newPlaylist(name: "")` | `playlists[1].name == "Playlist 2"` |
| `testRenamePlaylist_UpdatesName` | 1 playlist | `renamePlaylist(at: 0, name: "Jazz")` | `playlists[0].name == "Jazz"` |
| `testRenamePlaylist_OutOfRange_NoOp` | 1 playlist | `renamePlaylist(at: 5, name: "X")` | no crash |
| `testDeletePlaylist_DecreasesCount` | 2 playlists | `deletePlaylist(at: 1)` | `playlists.count == 1` |
| `testDeletePlaylist_LastOne_AutoInsertsSession` | 1 playlist | `deletePlaylist(at: 0)` | `playlists.count == 1` |
| `testDeletePlaylist_AdjustsActiveIndex_WhenDeletingActive` | 2 playlists, index = 1 | `deletePlaylist(at: 1)` | `activePlaylistIndex == 0` |
| `testDeletePlaylist_DecrementsActiveIndex_WhenDeletingBeforeActive` | 3 playlists, index = 2 | `deletePlaylist(at: 0)` | `activePlaylistIndex == 1` |
| `testDeletePlaylist_OutOfRange_NoOp` | 1 playlist | `deletePlaylist(at: 5)` | no crash |
| `testDeletePlaylist_StopsPlayback_WhenDeletingPlayingPlaylist` | Playing, 2 playlists | `deletePlaylist(at: playingIndex)` | `playbackState == .stopped`, `currentTrack == nil` |
| `testSwitchPlaylist_DoesNotStopPlayback` | Playing, 2 playlists | `activePlaylistIndex = 1` | `playbackState == .playing` |

### Done criteria
- Can create, rename, and delete playlists
- Each playlist has independent track list and sort state
- Switching playlists updates the now-playing context without stopping playback
- Deleting playing playlist stops playback and clears `currentTrack`
- All playlists survive app relaunch
- `AppStateMultiPlaylistTests` green

### Suggested commit message
```
feat(slice 7-B): add multiple playlist tabs with create/rename/delete

- Replace AppState.playlist with playlists: [Playlist]
- Add activePlaylistIndex, playlist computed accessor
- Add newPlaylist(name:), renamePlaylist(at:name:), deletePlaylist(at:)
- deletePlaylist stops playback when deleting playing playlist
- Add PlaylistView tab bar with inline rename
- Add File menu: New Playlist, Rename Playlist, Delete Playlist
- Add AppStateMultiPlaylistTests (15 cases)
```

---

## Slice 7-C: Playlist Import/Export (M3U8) ✅

### Goal
Allow users to export playlists as M3U8 files and import M3U8 files from
other apps (VLC, foobar2000, Apple Music).

### Scope

#### Export
- `File → Export Playlist…` opens `NSSavePanel` (macOS layer)
- Requires `User Selected File Read/Write` entitlement in App Sandbox
- `NSSavePanel` offers a path-style picker: **Absolute** or **Relative**
- Writes current active playlist as `.m3u8` with `#EXTINF` metadata

#### Import
- `File → Import Playlist…` opens `NSOpenPanel` (macOS layer)
- Reads the file, resolves all paths to absolute URLs
- Ignores `#EXTINF` lines — re-reads metadata via `TagReaderService`
- Creates a **new playlist tab** named after the `.m3u8` filename (without extension)
- Files not found on disk: skipped; a warning alert lists all missing paths

#### `#EXTINF` format on export
- `#EXTINF:<duration_seconds>,<artist> - <title>` when artist is non-empty
- `#EXTINF:<duration_seconds>,<title>` when artist is empty
- `duration == 0` → use `-1` (M3U8 standard for unknown duration)

#### Architecture decisions
- `M3U8Service` is a pure value type — no I/O, no platform APIs
- `NSSavePanel` and `NSOpenPanel` live in `HarmoniaPlayerCommands` (macOS layer)
- `AppState` receives only plain `URL` values
- `UTType(filenameExtension: "m3u8")` may return nil; use `if let` not `!`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/M3U8Service.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift`
  (modify — add Export/Import to File menu, own NSSavePanel/NSOpenPanel)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `writeExport(to:pathStyle:)`, `importPlaylist(from:)`, `skippedImportURLs`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/M3U8ServiceTests.swift` (new)

### Public API shape

```swift
enum M3U8PathStyle {
    case absolute
    case relative(to: URL)
}

struct M3U8Service {
    func export(playlist: Playlist, pathStyle: M3U8PathStyle) -> String
    func parse(m3u8: String, baseURL: URL?) -> [URL]
}

// AppState additions
@Published var skippedImportURLs: [URL] = []

func writeExport(to url: URL, pathStyle: M3U8PathStyle) throws
func importPlaylist(from url: URL) async
```

### TDD matrix

| Test | Given | When | Then |
|------|-------|------|------|
| `testExport_ProducesValidM3U8` | Playlist with 2 tracks | `export(playlist:pathStyle:.absolute)` | starts with `#EXTM3U`, contains absolute paths |
| `testExport_EXTINF_WithArtist` | title="Creep", artist="Radiohead", duration=237 | `export(playlist:pathStyle:.absolute)` | contains `#EXTINF:237,Radiohead - Creep` |
| `testExport_EXTINF_EmptyArtist` | title="Untitled", artist="", duration=180 | `export(playlist:pathStyle:.absolute)` | contains `#EXTINF:180,Untitled` |
| `testExport_EXTINF_UnknownDuration` | duration=0 | `export(playlist:pathStyle:.absolute)` | contains `#EXTINF:-1,` |
| `testExport_RelativePaths` | track at `/music/a.mp3`, m3u8 at `/music/export.m3u8` | `export(playlist:pathStyle:.relative(to:))` | path written as `a.mp3` |
| `testExport_RelativePaths_SubDirectory` | track at `/music/rock/a.mp3`, m3u8 at `/music/export.m3u8` | `export(playlist:pathStyle:.relative(to:))` | path written as `rock/a.mp3` |
| `testParse_AbsolutePaths_ReturnsURLs` | M3U8 with 2 absolute paths | `parse(m3u8:baseURL:nil)` | returns 2 `file://` URLs |
| `testParse_RelativePaths_ResolvesAgainstBase` | M3U8 with `a.mp3`, baseURL=`/music/` | `parse(m3u8:baseURL:)` | returns `file:///music/a.mp3` |
| `testParse_IgnoresCommentLines` | M3U8 with `#EXTM3U` and `#EXTINF` lines | `parse(m3u8:baseURL:nil)` | only returns path lines |
| `testParse_EmptyString` | `""` | `parse(m3u8:baseURL:nil)` | returns `[]` |

### Done criteria
- Export produces valid M3U8 readable by VLC / foobar2000
- Absolute path export: paths are fully qualified `file://` or POSIX paths
- Relative path export: paths are relative to the `.m3u8` file location
- Import reads M3U8, creates new playlist tab named after filename
- Import re-reads metadata via `TagReaderService` (ignores `#EXTINF` text)
- Missing files on import: skipped, warning alert lists all missing paths
- `User Selected File Read/Write` entitlement added to project
- All M3U8ServiceTests green

### Suggested commit message
```
feat(slice 7-C): add M3U8 playlist import/export

- Add M3U8Service: export(playlist:pathStyle:) → M3U8 string
- Add M3U8Service: parse(m3u8:baseURL:) → absolute URLs
- Add AppState.writeExport(to:pathStyle:): write .m3u8 file
- Add AppState.importPlaylist(from:): new tab + TagReaderService
- Add File menu: Export Playlist…, Import Playlist…
- Fix UTType(filenameExtension:) force-unwrap crash in NSSavePanel
- Add User Selected File Read/Write entitlement
- Add M3U8ServiceTests (10 cases)
```

---

## Slice 7-D: Drag-to-Reorder ✅

### Goal
Fix `AppState.moveTrack` to keep `insertionOrder` in sync with `tracks`.
Drag UI is deferred to Slice 7-G (SwiftUI Table intercepts drag gestures).

### Scope
- Fix `AppState.moveTrack(fromOffsets:toOffset:)` to update `insertionOrder`
  after reordering `tracks`
- `shuffleQueue` must not be touched by `moveTrack`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — fix `moveTrack` to sync `insertionOrder`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateDragReorderTests.swift` (new)

### Public API shape
No new public API. Uses existing `moveTrack(fromOffsets:toOffset:)` in `AppState`.

### TDD matrix

| Test | Given | When | Then |
|------|-------|------|------|
| `testMoveTrack_UpdatesInsertionOrder` | Playlist [A, B, C] | `moveTrack(fromOffsets:[2], toOffset:0)` | `insertionOrder == [C.id, A.id, B.id]` |
| `testMoveTrack_InsertionOrder_MatchesTracks` | Playlist [A, B, C] | `moveTrack(fromOffsets:[0], toOffset:3)` | `insertionOrder == tracks.map(\.id)` |

### Done criteria
- `AppState.moveTrack` syncs `insertionOrder` with `tracks` after every reorder
- `AppStateDragReorderTests` green
- All Slice 1–7-C tests still green

### Suggested commit message
```
fix(slice 7-D): sync insertionOrder in moveTrack

- moveTrack was updating tracks but not insertionOrder
- add AppStateDragReorderTests (2 cases)
- drag UI deferred to slice 7-G (SwiftUI Table blocks drag gestures)
```

---

## Slice 7-E: Persistence ✅

### Goal
Persist playlist, settings, and sort state to `UserDefaults` so they survive
app quit and relaunch.

### Scope
- `Track` conforms to `Codable`
- `Playlist` conforms to `Codable`
- `AppState.saveState()` writes playlists, activePlaylistIndex, allowDuplicateTracks,
  volume, selectedLanguage, repeatMode, isShuffled to `UserDefaults`
- `AppState.restoreState()` reads them back on init
- `saveState()` wired to `NSApplication.willTerminateNotification` in `HarmoniaPlayerApp`
- `restoreState()` called in `AppState.init()` after services are wired
- `TableColumnCustomization` persisted separately via `@AppStorage` (SwiftUI automatic)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Track.swift` (modify — add `Codable`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Playlist.swift` (modify — add `Codable`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `saveState()`, `restoreState()`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePersistenceTests.swift` (new)

### Public API shape

```swift
// AppState additions
func saveState()     // called on app quit
func restoreState()  // called on app launch

// UserDefaults keys (private enum PersistenceKey)
// hp.playlists, hp.activePlaylistIndex, hp.allowDuplicateTracks,
// hp.volume, hp.selectedLanguage, hp.sortKey, hp.sortAscending,
// hp.repeatMode, hp.isShuffled
```

### TDD matrix

| Test | Given | When | Then |
|------|-------|------|------|
| `testSaveAndRestore_Playlist_SurvivesRelaunch` | Playlist with 3 tracks | `saveState()` then `restoreState()` | `playlist.tracks.count == 3` |
| `testSaveAndRestore_TrackURL_Preserved` | Track with URL | save → restore | `url` matches |
| `testSaveAndRestore_SortKey_Survives` | `sortKey == .title` | `saveState()` then `restoreState()` | `sortKey == .title` |
| `testSaveAndRestore_AllowDuplicates_Survives` | `allowDuplicateTracks == true` | save → restore | `true` |
| `testSaveAndRestore_Volume_Survives` | `volume == 0.7` | save → restore | `0.7` |
| `testRestoreState_WhenNoData_UsesDefaults` | Empty UserDefaults | `restoreState()` | 1 empty playlist, volume 1.0 |

### Done criteria
- Playlist survives app quit and relaunch
- Sort state survives app quit and relaunch
- `allowDuplicateTracks`, `volume`, `selectedLanguage` survive app quit and relaunch
- `AppStatePersistenceTests` green

### Suggested commit message
```
feat(slice 7-E): add persistence for playlist and settings via UserDefaults

- Add Codable to Track and Playlist
- Add AppState.saveState(): writes playlists, settings, sort state
- Add AppState.restoreState(): restores on launch with defaults fallback
- Wire saveState() to NSApplication.willTerminateNotification
- Add AppStatePersistenceTests (6 cases)
```

---

## Slice 7-F: UI Localisation ✅

### Goal
Replace all hardcoded UI strings with localised equivalents and add a
language picker to Settings so users can override the app language at runtime.

### Supported languages
en, zh-Hant, zh-Hans, ja, ko, fr, de, es, pt, it, cs, sv, fi, nb, ru, pl,
et, lv, lt, ar, th, vi, id, hi

### Scope
- Replace all hardcoded UI strings with
  `NSLocalizedString(key, bundle: appState.languageBundle, comment: "")` via
  a private `L(_ key: String)` helper in each View
- Create `Localizable.strings` for all 24 languages (70 keys each)
- Add `@Published var selectedLanguage: String = "system"` to `AppState`
- Add `var languageBundle: Bundle` computed property to `AppState`
  — loads matching `.lproj` sub-bundle; falls back to `Bundle.main`
- App defaults to English on first launch (writes `AppleLanguages = ["en"]`
  in `HarmoniaPlayerApp.init()`)
- Language change writes `AppleLanguages` to `UserDefaults` and restarts app
  so system menus also switch language
- Settings: language picker (system default + 24 languages)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `selectedLanguage`, `languageBundle`, saveState/restoreState)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift`
  (modify — `init()` applies saved language, defaults to en on first launch)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/SettingsView.swift`
  (modify — add language picker, `applyLanguageAndRestart()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/ContentView.swift` (modify — L() helper)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlayerView.swift` (modify — L() helper)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift` (modify — L() helper)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift` (modify — L() helper)
- `App/HarmoniaPlayer/HarmoniaPlayer/{lang}.lproj/Localizable.strings` × 24 (new)
- `App/HarmoniaPlayer/HarmoniaPlayerUITests/HarmoniaPlayerUITests.swift`
  (modify — force English via launchArguments)

### Public API shape

```swift
// AppState additions
@Published var selectedLanguage: String = "system"  // "system" or BCP-47 tag

var languageBundle: Bundle {
    guard selectedLanguage != "system" else { return .main }
    guard let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return .main }
    return bundle
}
```

### TDD matrix
No dedicated unit tests for 7-F (UI-layer strings; verified by XCUITest
English-forced launch). UI tests force English via:

```swift
app.launchArguments += [
    "-AppleLanguages", "(en)",
    "-AppleLocale", "en_US",
    "-hp.selectedLanguage", "en",
]
```

### Done criteria
- All UI text is localised
- First launch defaults to English regardless of system language
- Language change triggers app restart; system menus update after restart
- Language selection persists across launches
- `Localizable.strings` × 24 present in target bundle (70 keys each)
- All existing XCUITests pass with English-forced launch

### Suggested commit message
```
feat(slice 7-F): add UI localisation for 24 languages

- Add AppState.selectedLanguage (@Published, persisted via UserDefaults)
- Add AppState.languageBundle (runtime .lproj bundle switching)
- Add saveState/restoreState for selectedLanguage
- Add Localizable.strings x24: en, zh-Hant, zh-Hans, ja, ko, fr, de, es,
  pt, it, cs, sv, fi, nb, ru, pl, et, lv, lt, ar, th, vi, id, hi (70 keys each)
- Replace all hardcoded UI strings with NSLocalizedString(bundle:) in
  ContentView, PlayerView, PlaylistView, SettingsView, HarmoniaPlayerCommands
- Add language picker to SettingsView (system default + 24 languages)
- Write AppleLanguages on language change and restart app for full effect
- Default to English on first launch via HarmoniaPlayerApp.init()
- Fix HarmoniaPlayerUITests: force English via launchArguments
```

---

## Slice 7-G: Column Customization

### Goal
Allow users to show/hide optional metadata columns in `PlaylistView`, drag
columns left/right to reorder, and sort by clicking any column header.
Three columns (title, artist, duration) are always visible.
This slice also expands `Track` with the full tag field set required by
later slices (ReplayGain in 8-D, Tag Editor in Slice 9).

### Scope
- Expand `Track`: add Groups A–D (tag fields + file technical info) and
  Group E (reserved: playCount, lastPlayedAt, rating, artworkData — always
  nil/default in Slice 7, no UI exposed)
- Map Groups A–D in `HarmoniaTagReaderAdapter`
- Migrate `PlaylistView` to SwiftUI `Table` with `TableColumnCustomization`
- Fixed columns (cannot be hidden): title, artist, duration
- Optional columns (hidden by default except album): album, albumArtist, year,
  trackNumber, discNumber, genre, composer, bpm, bitrate, sampleRate,
  channels, fileSize, fileFormat, comment
- All columns sortable by clicking header
- Column visibility and order persisted via `@AppStorage`

> Full field list and TagReaderAdapter mapping table: see
> `HarmoniaPlayer_slice_7_micro.md` § Slice 7-G.

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Track.swift`
  (modify — add Groups A–E)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaTagReaderAdapter.swift`
  (modify — map Groups A–D)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift`
  (modify — migrate to Table + TableColumnCustomization)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/TrackTests.swift`
  (modify — add tests for new fields)

### Public API shape

```swift
// Track new fields (Groups A–E)
// See HarmoniaPlayer_slice_7_micro.md for complete list

// PlaylistView (View-local, not AppState)
@AppStorage("playlistColumnCustomization")
private var columnCustomization: TableColumnCustomization<Track>

@State private var sortOrder: [KeyPathComparator<Track>] = [
    .init(\.title, order: .forward)
]
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultGenre_IsEmpty` | `Track(url:)` | read `genre` | `""` |
| `testTrack_DefaultYear_IsNil` | `Track(url:)` | read `year` | `nil` |
| `testTrack_DefaultBitrate_IsNil` | `Track(url:)` | read `bitrate` | `nil` |
| `testTrack_DefaultPlayCount_IsZero` | `Track(url:)` | read `playCount` | `0` |
| `testTrack_DefaultRating_IsNil` | `Track(url:)` | read `rating` | `nil` |
| `testTrack_AllNewFields_RoundTrip` | Track with all fields set | encode → decode | all fields match |

### Done criteria
- Fixed columns (title, artist, duration) always visible, cannot be hidden
- Optional columns toggleable via right-click on column header
- All columns draggable left/right to reorder
- Clicking any column header sorts ascending; clicking again sorts descending
- Column state survives app relaunch
- Group E fields in model but no UI in Slice 7
- All TrackTests green; all Slice 1–6 tests still green

### Suggested commit message
```
feat(slice 7-G): expand Track model and add column customization to PlaylistView

- Add Groups A–E fields to Track (albumArtist, composer, genre, year,
  trackNumber, trackTotal, discNumber, discTotal, bpm, replayGainTrack,
  replayGainAlbum, comment, bitrate, sampleRate, channels, fileSize,
  fileFormat, playCount, lastPlayedAt, rating, artworkData)
- Map Groups A–D in HarmoniaTagReaderAdapter
- Migrate PlaylistView to Table with TableColumnCustomization
- Fixed: title, artist, duration; optional: album + 13 columns
- All columns sortable; column state persisted via AppStorage
- Add TrackTests for new fields
```

---

## Slice 7-H: File Info Panel

### Goal
Show technical file information for the selected track via right-click →
"Get Info" or ⌘I. The source URL field (`kMDItemWhereFroms`) is editable —
user can clear or modify the value.

### Scope
- New `ExtendedAttributeService`: reads / writes `kMDItemWhereFroms` via
  Darwin `getxattr` / `setxattr` / `removexattr`
- New `FileInfoView` sheet with three sections:
  - **Location** (read-only): file name, folder, path, size, dates
  - **General** (read-only): format, duration, bit rate, sample rate,
    channels, tag type
  - **Source** (editable): `kMDItemWhereFroms`; Edit / Clear buttons
- Playback Statistics section reserved for Slice 8-E — not implemented here

> Display spec tables for all three sections: see
> `HarmoniaPlayer_slice_7_micro.md` § Slice 7-H.

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/FileInfoView.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/ExtendedAttributeService.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift`
  (modify — add right-click "Get Info" context menu item)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift`
  (modify — add ⌘I shortcut)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/ExtendedAttributeServiceTests.swift` (new)

### Public API shape

```swift
struct ExtendedAttributeService {
    func readWhereFroms(url: URL) -> [String]
    func writeWhereFroms(_ sources: [String], url: URL) throws
    func clearWhereFroms(url: URL) throws
}
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testReadWhereFroms_WhenPresent_ReturnsURLs` | File with source attribute | `readWhereFroms(url:)` | returns non-empty array |
| `testReadWhereFroms_WhenAbsent_ReturnsEmpty` | Fresh temp file | `readWhereFroms(url:)` | returns `[]` |
| `testWriteWhereFroms_PersistsValue` | Fresh temp file | `writeWhereFroms(["https://x.com"], url:)` then read | `["https://x.com"]` |
| `testClearWhereFroms_RemovesAttribute` | File with source attribute | `clearWhereFroms(url:)` then read | `[]` |
| `testClearWhereFroms_WhenAbsent_DoesNotThrow` | Fresh temp file | `clearWhereFroms(url:)` | no throw |

### Done criteria
- File Info panel opens on right-click → "Get Info" or ⌘I
- Location and General sections display correct values (read-only)
- Source field shows `kMDItemWhereFroms` when present; `(none)` when absent
- Clear removes attribute; Edit + save updates attribute
- No crash when attribute is absent
- ExtendedAttributeServiceTests green; all Slice 1–6 tests still green

### Suggested commit message
```
feat(slice 7-H): add File Info Panel with editable source URL

- Add ExtendedAttributeService: read/write/clear kMDItemWhereFroms
- Add FileInfoView: Location + General (read-only), Source (editable)
- Add right-click "Get Info" in PlaylistView
- Add ⌘I shortcut in HarmoniaPlayerCommands
- Add ExtendedAttributeServiceTests (5 cases)
```

---

## Slice 7 Completion Gate

- ✅ Volume slider visible and functional in PlayerView
- ✅ Multiple playlists supported with tabs
- ✅ Deleting playing playlist stops playback and clears currentTrack
- ✅ Playlist export as M3U8 with absolute or relative paths (user choice)
- ✅ Playlist import from M3U8, creates new playlist tab named after filename
- ✅ Playlist import re-reads metadata via TagReaderService
- ✅ Drag-to-reorder: insertionOrder synced (drag UI in 7-G)
- ✅ Playlist survives app quit and relaunch
- ✅ Sort state survives app quit and relaunch
- ✅ `allowDuplicateTracks`, `volume`, `selectedLanguage` survive app quit and relaunch
- ✅ All UI text localised in 24 languages
- ✅ First launch defaults to English regardless of system language
- ✅ Language change restarts app; system menus update after restart
- ✅ Language selection persists across launches
- ⬜ `Track` model expanded with Groups A–E; all new fields `Codable`
- ⬜ Group E fields defined but no UI exposed in Slice 7
- ⬜ Fixed columns (title, artist, duration) always visible, cannot be hidden
- ⬜ Optional columns toggleable and reorderable via column header
- ⬜ All columns sortable by clicking header
- ⬜ Column state survives app relaunch
- ⬜ File Info Panel opens on right-click or ⌘I
- ⬜ Location and General sections show correct values (read-only)
- ⬜ Source field editable (Edit / Clear)
- ✅ All Slice 7-A–F unit tests green
- ✅ All Slice 1–6 tests still green

---

## Related Slices

- **Slice 2 (Playlist Management)** — `playlist.tracks` data structure extended by 7-B to `[Playlist]`
- **Slice 3 (Metadata Reading)** — `TagReaderService` extended by 7-G to read Groups A–D fields
- **Slice 5 (Integration)** — `HarmoniaTagReaderAdapter` extended by 7-G with full tag mapping
- **Slice 6 (UI + Menu Bar)** — `AppState`, `PlayerView`, `PlaylistView`,
  `HarmoniaPlayerCommands`, `SettingsView` all extended by Slice 7 sub-slices