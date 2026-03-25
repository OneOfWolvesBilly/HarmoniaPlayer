# Slice 07 Micro-slices Specification

## Purpose

This document defines **Slice 7: Persistence, Volume, Multiple Playlists,
Drag-to-Reorder, Column Customization, File Info Panel, and UI Localisation**
for HarmoniaPlayer.

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
other apps (VLC, foobar2000, Apple Music).

Export supports both absolute paths (for local use) and relative paths
(relative to the saved `.m3u8` file, for portable use on USB drives or
sharing with others).

### Scope

#### Export
- `File → Export Playlist…` opens `NSSavePanel` (macOS layer)
- `NSSavePanel` offers a path-style picker: **Absolute** or **Relative**
- Writes current active playlist as `.m3u8` with `#EXTINF` metadata

#### Import
- `File → Import Playlist…` opens `NSOpenPanel` (macOS layer), limited to `.m3u8`
- Reads the file, resolves all paths to absolute URLs
  (relative paths are resolved relative to the `.m3u8` file's directory)
- Ignores `#EXTINF` lines — re-reads metadata via `TagReaderService`
- Creates a **new playlist tab** named after the `.m3u8` filename (without extension)
- Files not found on disk: skipped; a warning alert lists all missing paths

#### `#EXTINF` format on export
- `#EXTINF:<duration_seconds>,<artist> - <title>` when artist is non-empty
- `#EXTINF:<duration_seconds>,<title>` when artist is empty
- `duration == 0` → use `-1` (M3U8 standard for unknown duration)

### Architecture decisions
- `M3U8Service` is a pure value type — no I/O, no platform APIs
- `NSSavePanel` and `NSOpenPanel` live in `HarmoniaPlayerCommands` (macOS layer);
  `AppState` receives only plain `URL` values and never touches platform UI
- Path-style selection UI is owned by `HarmoniaPlayerCommands`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/M3U8Service.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift`
  (modify — add Export/Import to File menu, own NSSavePanel/NSOpenPanel)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `writeExport(to:pathStyle:)`, `importPlaylist(from:)`,
  `skippedImportURLs`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/M3U8ServiceTests.swift` (new)

### Public API shape

```swift
// M3U8Service
enum M3U8PathStyle {
    case absolute
    case relative(to: URL)  // URL of the .m3u8 file being written
}

struct M3U8Service {
    /// Generates M3U8 string from playlist.
    /// Paths are written as absolute or relative depending on pathStyle.
    func export(playlist: Playlist, pathStyle: M3U8PathStyle) -> String

    /// Parses M3U8 string and returns absolute URLs.
    /// Relative paths are resolved against baseURL (directory of the .m3u8 file).
    func parse(m3u8: String, baseURL: URL?) -> [URL]
}

// AppState additions
@Published var skippedImportURLs: [URL] = []

/// Writes M3U8 string to the given URL.
/// Called by HarmoniaPlayerCommands after NSSavePanel resolves the destination.
func writeExport(to url: URL, pathStyle: M3U8PathStyle) throws

/// Reads .m3u8 at url, creates a new playlist tab named after the filename,
/// re-reads metadata via TagReaderService, populates skippedImportURLs for
/// any files not found on disk.
func importPlaylist(from url: URL) async
```

### Done criteria
- Export produces valid M3U8 readable by VLC / foobar2000
- Absolute path export: paths are fully qualified `file://` or POSIX paths
- Relative path export: paths are relative to the `.m3u8` file location
- Import reads M3U8, creates a new playlist tab named after the filename
- Import re-reads metadata via `TagReaderService` (ignores `#EXTINF` text)
- Missing files on import: skipped, warning alert lists all missing paths
- All M3U8ServiceTests green

### Suggested commit message
```
feat(slice 7-C): add M3U8 playlist import/export

- Add M3U8Service: export(playlist:pathStyle:) → M3U8 string
- Add M3U8Service: parse(m3u8:baseURL:) → absolute URLs
- Add AppState.writeExport(to:pathStyle:): write .m3u8 file
- Add AppState.importPlaylist(from:): new tab + TagReaderService
- Add File menu: Export Playlist…, Import Playlist…
- Add M3U8ServiceTests
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
// PlaylistView (View-local, not AppState)
@AppStorage("playlistColumnCustomization")
private var columnCustomization: TableColumnCustomization<Track>

@State private var sortOrder: [KeyPathComparator<Track>] = [
    .init(\.title, order: .forward)
]
```

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
- Playback Statistics section (Played / First played / Last played / Added)
  reserved for Slice 8-E — not implemented here

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
- Add ExtendedAttributeServiceTests
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

### Slice 7-G — Column Customization (unit tests)

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultGenre_IsEmpty` | `Track(url:)` | read `genre` | `""` |
| `testTrack_DefaultYear_IsNil` | `Track(url:)` | read `year` | `nil` |
| `testTrack_DefaultBitrate_IsNil` | `Track(url:)` | read `bitrate` | `nil` |
| `testTrack_DefaultPlayCount_IsZero` | `Track(url:)` | read `playCount` | `0` |
| `testTrack_DefaultRating_IsNil` | `Track(url:)` | read `rating` | `nil` |
| `testTrack_AllNewFields_RoundTrip` | Track with all fields set | encode → decode | all fields match |

### Slice 7-H — File Info Panel (unit tests)

| Test | Given | When | Then |
|---|---|---|---|
| `testReadWhereFroms_WhenPresent_ReturnsURLs` | File with source attribute | `readWhereFroms(url:)` | returns non-empty array |
| `testReadWhereFroms_WhenAbsent_ReturnsEmpty` | Fresh temp file | `readWhereFroms(url:)` | returns `[]` |
| `testWriteWhereFroms_PersistsValue` | Fresh temp file | `writeWhereFroms(["https://x.com"], url:)` then read | `["https://x.com"]` |
| `testClearWhereFroms_RemovesAttribute` | File with source attribute | `clearWhereFroms(url:)` then read | `[]` |
| `testClearWhereFroms_WhenAbsent_DoesNotThrow` | Fresh temp file | `clearWhereFroms(url:)` | no throw |

### Slice 7-C — M3U8 Import/Export (unit tests)

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

---

## Slice 7 Completion Gate

### Required

- ✅ Volume slider visible and functional in PlayerView
- ✅ Multiple playlists supported with tabs
- ✅ Playlist export as M3U8 with absolute or relative paths (user choice)
- ✅ Playlist import from M3U8, creates new playlist tab named after filename
- ✅ Playlist import re-reads metadata via TagReaderService
- ✅ Drag-to-reorder functional within a playlist
- ✅ Playlist survives app quit and relaunch
- ✅ Sort state survives app quit and relaunch
- ✅ `allowDuplicateTracks` survives app quit and relaunch
- ✅ All UI text localised in 24 languages
- ✅ Language change in Settings takes effect immediately
- ✅ Arabic RTL layout verified
- ✅ `Track` model expanded with Groups A–E; all new fields `Codable`
- ✅ Group E fields defined but no UI exposed in Slice 7
- ✅ Fixed columns (title, artist, duration) always visible, cannot be hidden
- ✅ Optional columns toggleable and reorderable via column header
- ✅ All columns sortable by clicking header
- ✅ Column state survives app relaunch
- ✅ File Info Panel opens on right-click or ⌘I
- ✅ Location and General sections show correct values (read-only)
- ✅ Source field editable (Edit / Clear)
- ✅ All Slice 7 unit tests green
- ✅ All Slice 1–6 tests still green

---

## Related Slices

- **Slice 2 (Playlist Management)** — `playlist.tracks` data structure extended by 7-B to `[Playlist]`
- **Slice 3 (Metadata Reading)** — `TagReaderService` extended by 7-G to read Groups A–D fields
- **Slice 5 (Integration)** — `HarmoniaTagReaderAdapter` extended by 7-G with full tag mapping
- **Slice 6 (UI + Menu Bar)** — `AppState`, `PlayerView`, `PlaylistView`, `HarmoniaPlayerCommands`,
  and `SettingsView` all extended by Slice 7 sub-slices