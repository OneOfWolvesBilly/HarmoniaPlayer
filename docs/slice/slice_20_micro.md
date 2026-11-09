# Slice 20 Micro-slices Specification

## Purpose

Seventh stage of the AppState decomposition refactor program (design
authority: `appstate_refactor_plan.md`; pre-Pro milestone, no version
label). Extracts the fifth and last `@MainActor @Observable` feature
store — `PlaylistCollection` — behind the AppState strangler facade. The
four remaining `@Published` properties leave AppState (plan §3 rows
27–30), the playlist / tab / undo / M3U8 / persistence / metadata-refresh
code moves with them together with the format statics and the
`undoManager`, the playback reactions to playlist mutations move into
`PlaybackController` behind root-wired closures (plan §2), the transitional
`PlaylistContext` is now implemented by the collection and handed to the
controller at construction, `PlaylistView` and `HarmoniaPlayerCommands`
migrate off the facade, and the nine playlist test files are re-homed on
the store (plan §6.2). AppState ends as construction + wiring plus two
named stragglers.

## Slice 20 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 20-A | Extract `PlaylistCollection` (incl. M3U8) + playlist → playback reaction closures + `PlaylistContext` at controller init + facade removal + `@Environment` view migration + test migration | — | ⬜ |

### Goals

- Plan §3 rows 27–30 (`playlists`, `activePlaylistIndex`,
  `selectedTrackIDs`, `isPerformingBlockingOperation`), the `undoManager`,
  the format statics (`freeFormats`, `proOnlyFormats`, `allowedFormats`,
  `saveBatchSize`), and every playlist operation, tab operation, undo /
  redo entry point, M3U8 import / export, playlist persistence, and
  metadata-refresh method live in `PlaylistCollection`, which owns
  `tagReaderService`, `fileDropService`, `playlistStore`, and the
  `hp.activePlaylistIndex` key (plus the one-shot legacy `hp.playlists`
  migration).
- The playlist code holds no playback reference. Playlist mutations that
  affect playback are reported through six root-wired closures
  (`onTracksAppended`, `onTrackRemoved`, `onTracksRemoved`,
  `onPlaylistCleared`, `onPlaylistDeleted`, `onTrackQueuedNext`), and the
  reactions (stop, clear, play the next track, keep the shuffle queue in
  step) are `PlaybackController` methods.
- `PlaylistCollection` conforms to `PlaylistContext`; `PlaybackController`
  receives its context as an `init` argument held as a `let`, and the
  `weak var` + `nil` guards of the transitional form go (BL-19A-01).
- `PlaylistView` leaves `@EnvironmentObject appState` entirely
  (`@Environment` on `PlaylistCollection`, `PlaybackController`,
  `SettingsStore`, `AlertCenter`); `MiniPlayerView`, `PlayerView`, and
  `FileInfoView` read playlist state from the collection;
  `HarmoniaPlayerCommands` reaches it through
  `appState.playlistCollection`.
- The facade forwarders whose last internal reader leaves in this slice
  are deleted: the eleven playback forwarders, `replayGainMode`, the
  eleven AlertCenter forwarders, `allowDuplicateTracks`, `isProUnlocked`,
  `playlist`, `tagReaderService`, `fileDropService`, `playbackService`.
  AppState keeps `languageBundle`, `showPaywallIfNeeded()`, `saveState()`
  (the terminate-time save-all), and `switchMiniPlayerPlaylist(to:)` (the
  one cross-store orchestration).
- Tests whose real SUT is the playlist state move to a
  `PlaylistCollection*Tests` family that constructs the store directly
  (unit-test-core Rule 1); the playback-reaction logic gets its own
  controller rows; the playlist → playback flows that cross both stores
  are guarded end to end on AppState.
- `AppState+Playlist.swift` and `AppState+M3U8.swift` are deleted; the
  dead `PersistenceKey.sortKey` / `.sortAscending` entries go with
  AppState's `PersistenceKey` enum.

### Out of Scope

- Dropping `ObservableObject` / `import Combine` from `AppState`,
  migrating the `languageBundle` (`L()`) readers of the remaining
  `@EnvironmentObject` views, and replacing `@FocusedObject` in
  `HarmoniaPlayerCommands` → the language-mode close-out (plan §7.5). All
  three mechanisms require the conformance; nothing invalidates through
  AppState once the four rows leave.
- Deleting `languageBundle` and `showPaywallIfNeeded()` → plan §7.5
  (their readers are the `L()` helpers and the `onPaywallRequested` seam
  guards, which stay on AppState by the Slice 16 decision).
- `switchMiniPlayerPlaylist(to:)` leaving AppState → plan §7.5 decides
  its final home; here it is re-implemented over the two stores and stays.
- Fixing the next-track resolution after removing the playing track
  (BL-20A-01, below) → its own defect slice after v1.0.1's current items;
  the behaviour moves as it is.
- Change-time persistence of `volume` and `activePlaylistIndex`
  (BL-17A-01) → v1.0.1 item; this slice keeps terminate-time writes for
  both (see Constraints for the one difference).
- A standalone format-policy type → the Free / Pro isolation discussion
  (BL-16A-01); the statics move to the collection as plan §3 says.
- `architecture.md` §6.2 DI-excerpt drift beyond the AppState file list →
  plan §7.5 final doc realignment. This slice changes only the lines that
  would otherwise name deleted files, which triggers the HC 5-area audit.
- Moving `extension Array { subscript(safe:) }` out of `AppState.swift` →
  plan §7.5 (module-internal helper; no behaviour).
- Enabling any Pro feature — the commented-out gate lines in
  `PlaybackController+Navigation.swift` are re-pointed to the statics' new
  name and otherwise untouched; the fourteen commented-out gating tests
  move verbatim as comments (the Pro program re-specifies them).
- Any change to `EQCoordinator` / `NowPlayingCoordinator` → not in the
  program (plan §0).
- Deleting the Slice 12 baseline rows of files this slice does not touch
  → unchanged.

### Constraints

- Program constraints C1–C8 (plan §4) govern the observation mechanics;
  every scene hosting a migrated view must inject the store or the app
  crashes at first read (C3 — audit result: main window, Mini Player, and
  File Info host migrated views; the Equalizer and Settings subtrees do
  not).
- Dependency direction stays as plan §2 declares: `PlaylistCollection ←
  tagReaderService, fileDropService, playlistStore, undoManager,
  AlertCenter, SettingsStore` (+ `userDefaults` for its key) and
  `PlaybackController ← playbackService, AlertCenter, SettingsStore,
  PlaylistContext`. The collection holds no reference to the controller,
  AppState, or any coordinator; playback reactions go through closures
  wired by the composition root. Construction order in the root:
  collection before controller.
- Behaviour is preserved, including existing quirks: removing the playing
  track (shuffle off) continues with the first track of the playlist;
  clearing the playlist while playing clears the current track without
  stopping the service; choosing the current playlist in the Mini Player
  restarts it from the first track; `activePlaylistIndex` is written only
  by the save-all and by playlist mutations, not by a tab switch; undo of
  a single removal does not touch the shuffle queue.
- Two observable differences, accepted:
  (1) `hp.volume` is written only at terminate — today every playlist
  mutation's `saveState()` also wrote it; BL-17A-01 is the change-time
  replacement.
  (2) undo / redo of a batch removal no longer restores the shuffle-queue
  snapshot; the restored tracks re-enter the queue the next time it is
  rebuilt — the behaviour single-removal undo already has.
- `PlaylistCollection.init` restores the playlists, the active index, and
  the accessibility flags before returning and starts the background
  metadata refresh, as `AppState.init` does today through `restoreState()`;
  `@Observable` init-assignment semantics (Slice 16 amendment) keep the
  restore free of observers.
- The `playNext` insertion point depends on the playing track's position,
  which the collection cannot read; the caller passes the current track's
  id (`playNext(_:afterCurrent:)`).
- New store code builds warning-free under the Slice 12 baseline; this
  slice retires the baseline rows of the test files it deletes and
  re-measures every file it touches (plan §6.0 step 5).

### Dependencies

- Slice 13 (AlertCenter — a collection dependency), Slice 16
  (SettingsStore — a collection dependency; `didSet` / root-wired closure
  templates), Slice 19 (PlaybackController — the reaction target;
  `PlaylistContext`; `FakePlaylistContext`).
- Slice 12 (baseline must exist for the warning-clearing obligation).

---

## Slice 20-A: Extract PlaylistCollection ⬜

### Goal

Move the whole playlist surface out of AppState into a dedicated
`@MainActor @Observable` store that owns the playlist services, the undo
manager, and the playlist persistence, route its effects on playback
through root-wired closures into controller-side reaction methods, hand
the controller its playlist context at construction, migrate the five
views and the Commands that read playlist state, and delete every facade
forwarder that has no internal reader left.

### Scope (FROZEN as of spec commit)

**New store** `Shared/Models/PlaylistCollection.swift` (state, statics,
init, playlist operations, tab management, undo / redo, persistence,
metadata refresh, file info) and `Shared/Models/PlaylistCollection+M3U8.swift`
(`writeExport` ×2, `importPlaylist`, private `isURLSupported`) — see
Public API shape. Deliberate choices frozen with it:

- **State.** Rows 27–30 are observable stored properties; `playlist` is
  the computed `playlists[activePlaylistIndex]`. `undoManager`,
  `tagReaderService` are `let`, internal (the Commands reach the manager
  through `undo()` / `redo()` / `canUndo` / `canRedo`; the composition-root
  wiring tests read the service); `fileDropService`, `playlistStore`,
  `alertCenter`, `settingsStore`, `userDefaults` are `private let`.
  `init` sets `undoManager.levelsOfUndo = 10`.
- **Statics.** `freeFormats`, `proOnlyFormats`, `allowedFormats`,
  `saveBatchSize` move with their bodies and doc text; every reader uses
  `PlaylistCollection.<name>` (views) or `Self.<name>` (store code).
- **Persistence (plan §6.1).** The store owns `hp.activePlaylistIndex`
  and the legacy `hp.playlists` key (a private `PersistenceKey` enum with
  those two entries; AppState's enum, including the dead `sortKey` /
  `sortAscending`, is deleted). `saveState()` writes the playlists to
  `playlistStore` and the index to `userDefaults`; `restoreState()` is
  today's body (file store, one-shot legacy migration, index clamp,
  accessibility re-check, `Task { await refreshMetadataIfNeeded() }`) and
  is called at the end of `init`. `AppState.saveState()` becomes the
  terminate-time save-all: `playbackController.saveVolume()` then
  `playlistCollection.saveState()`.
- **Root-wired closures (`@ObservationIgnored`).**
  `onTracksAppended: (([Track.ID]) -> Void)?` — called by `load(urls:)`
  with the added ids after `insertionOrder` is extended, only when at
  least one track was added.
  `onTrackRemoved: ((Track.ID) -> Void)?` — called by `removeTrack(_:)`
  after the track and its `insertionOrder` entry are removed, only when a
  track was found.
  `onTracksRemoved: ((Set<Track.ID>) -> Void)?` — called by
  `removeTracks(_:)` with the ids actually removed, after the mutation and
  before the undo registration.
  `onPlaylistCleared: (() -> Void)?` — called by `clearPlaylist()` after
  the tracks are cleared.
  `onPlaylistDeleted: ((Playlist.ID) -> Void)?` — called by
  `deletePlaylist(at:)` with the deleted playlist's id, after the range
  guard and before the removal.
  `onTrackQueuedNext: ((Track.ID) -> Void)?` — called by
  `playNext(_:afterCurrent:)` after the re-insertion.
  Undo / redo closures call none of them (today's undo paths touch no
  playback state except the batch-removal queue snapshot, which goes).
- **Methods moved verbatim** (signatures unchanged unless noted), with the
  playback reads and writes listed in the draft replaced by the closure
  calls above: `handleFileDrop(urls:)`, `load(urls:)`, `clearPlaylist()`,
  `switchPlaylist(to:)`, `canUndo`, `canRedo`, `undo()`, `redo()`,
  `newPlaylist(name:)`, private `nextAvailablePlaylistName()`,
  `renamePlaylist(at:name:)`, `deletePlaylist(at:)`, `removeTrack(_:)`,
  `removeTracks(_:)`, `playNext(_:afterCurrent:)` (was `playNext(_:)`; the
  insertion index comes from `afterCurrent`), `applySort(_:key:ascending:)`,
  `restoreInsertionOrder()`, `moveTrack(fromOffsets:toOffset:)`,
  `moveTrack(id:before:)`, `saveState()`, `restoreState()`,
  `refreshMetadataIfNeeded()`, `showFileInfo(trackID:)`,
  `writeExport(to:pathStyle:)`, `writeExport(playlistAt:to:pathStyle:)`,
  `importPlaylist(from:)`. The alert and settings reads write / read
  `alertCenter.…` and `settingsStore.allowDuplicateTracks` directly. Undo
  closures target the collection (`registerUndo(withTarget: self)`) and
  call its `saveState()`.
- **`PlaylistContext` conformance** is declared on `PlaylistCollection`
  (`playlists`, `activePlaylistIndex`, `selectedTrackIDs` match by name
  and mutability — no body). `extension AppState: PlaylistContext {}` is
  deleted; the protocol's members are unchanged.

**`PlaybackController` changes** (`Shared/Models/PlaybackController.swift`,
`PlaybackController+Navigation.swift`, new
`PlaybackController+PlaylistReactions.swift`):

- `init` gains `playlistContext: any PlaylistContext`; the property
  becomes `@ObservationIgnored let playlistContext: any PlaylistContext`;
  the six `guard let context = playlistContext else { return }` lines go
  and the bodies read `playlistContext` directly.
- Reaction methods (new file), holding today's playlist-side reaction
  logic with the playlist content read through `playlistContext`:
  `handleTracksAppended(_ ids: [Track.ID])` — when shuffled, inserts each
  id at a random position after `shuffleQueueIndex` (today's `load` loop);
  otherwise nothing.
  `handleTrackRemoved(_ id: Track.ID)` — when `id` is the current track:
  if playing, resolves the next track as today (shuffled →
  `shuffleQueue[safe: shuffleQueueIndex]` before the queue is edited;
  otherwise the active playlist's first track), then
  `Task { await playbackService.stop(); currentTrack = nil; … }` either
  stopping (`.stopped`, `currentTime = 0`) when the playlist is empty or
  no next track resolved, or `play(trackID: next)`; if not playing,
  `currentTrack = nil`. Then, when shuffled, removes `id` from the queue
  and shifts `shuffleQueueIndex` back when the removed position was before
  it.
  `handleTracksRemoved(_ ids: Set<Track.ID>)` — when shuffled, filters the
  queue and clamps the index; when the current track is in `ids`,
  `Task { await playbackService.stop(); currentTrack = nil; currentTime =
  0; playbackState = .stopped }`.
  `handlePlaylistCleared()` — `currentTrack = nil`.
  `handlePlaylistDeleted(_ id: Playlist.ID)` — when `id == playingPlaylistID`,
  `Task { await stop() }`.
  `handleTrackQueuedNext(_ id: Track.ID)` — when shuffled, removes `id`
  from the queue and inserts it at `min(shuffleQueueIndex + 1, count)`.
- The three commented-out format-gate lines in
  `PlaybackController+Navigation.swift` read
  `PlaylistCollection.proOnlyFormats`.

**AppState changes:**

- `let playlistCollection: PlaylistCollection`, constructed after the
  lyrics store from `tagReaderService`, `fileDropService`, `playlistStore`
  (`?? FilePlaylistStore()`), `undoManager` (`?? UndoManager()`),
  `alertCenter`, `settingsStore`, `userDefaults`; the controller is then
  constructed with `playlistContext: playlistCollection`. The
  `playlistStore:` and `undoManager:` init parameters stay and pass
  through.
- Wiring step: the six collection closures target the controller's
  `handle…` methods (capturing the controller, never `self`); the existing
  five closures are unchanged; `playbackController.playlistContext = self`
  is gone.
- `switchMiniPlayerPlaylist(to:) async` stays on AppState, re-implemented
  over the stores with today's order and guards: range guard →
  `await playbackController.stop()` →
  `playlistCollection.activePlaylistIndex = index` →
  `playlistCollection.undoManager.removeAllActions()` → play the first
  track through `playbackController.play(trackID:)` when there is one.
- Deleted: the four `@Published` properties, `playlist`, `undoManager`,
  `tagReaderService`, `fileDropService`, `playlistStore`, `userDefaults`
  (stored property; the init parameter stays), the format statics, the
  `PersistenceKey` enum, `restoreState()`, `refreshMetadataIfNeeded()`,
  `showFileInfo(trackID:)`, the `PlaylistContext` conformance, and the
  facade forwarders below. `import Combine`, `ObservableObject`, the
  `Array[safe:]` extension, `init`, `saveState()`, `showPaywallIfNeeded()`,
  `languageBundle`, the store / coordinator references, and
  `nonisolated deinit` remain.
- **Facade verdicts, per member** (plan §6.0 step 7):

  | Member | Surviving reader after this slice | Facade |
  | --- | --- | --- |
  | `playlists`, `activePlaylistIndex`, `selectedTrackIDs`, `isPerformingBlockingOperation`, `playlist` | none (views on the store, Commands on the dotted path, tests retarget) | none — deleted |
  | `currentTrack`, `playbackState`, `currentTime`, `playingPlaylistID`, `repeatMode`, `isShuffled`, `shuffleQueue`, `shuffleQueueIndex`, `playbackService`, `stop()`, `play(trackID:)` | none (`switchMiniPlayerPlaylist` calls the controller directly) | deleted |
  | `replayGainMode` | none | deleted |
  | `lastError`, `lastErrorDetail`, `failedTrackName`, `showFileNotFoundAlert`, `skippedInaccessibleNames`, `skippedDuplicateURLs`, `skippedImportURLs`, `skippedUnsupportedURLs`, `fileInfoTrack`, `showPaywall`, `paywallDismissedThisSession` | none (the playlist code writes `alertCenter.…`; views read the store since Slice 13; tests retarget) | deleted |
  | `allowDuplicateTracks` | none | deleted |
  | `isProUnlocked` | none (`PlaylistView`, `MiniPlayerView` → `SettingsStore`; `AppStateTests` → `settingsStore.isProUnlocked`) | deleted |
  | `tagReaderService`, `fileDropService` | none on AppState (`AppStateTests` → `playlistCollection.tagReaderService`) | deleted — owned by the collection |
  | `undoManager`, `canUndo`, `canRedo`, `undo()`, `redo()` | Commands → `playlistCollection.…` | none — owned by the collection |
  | `languageBundle` | `L()` in nine views + Commands | get-only forwarder, unchanged |
  | `showPaywallIfNeeded()` | `AppStateTests` ×2 | method forwarder, unchanged |
  | `saveState()` | `HarmoniaPlayerApp` terminate | kept — save-all |
  | `switchMiniPlayerPlaylist(to:)` | `MiniPlayerView`, `MiniPlayerViewTests` | kept — cross-store orchestration |

- `@Published` count drops to zero; `AppState.swift` declares exactly
  these members: the store and coordinator `let`s, `languageBundle`,
  `init`, `nonisolated deinit`, `showPaywallIfNeeded()`, `saveState()`,
  `switchMiniPlayerPlaylist(to:)`, plus the `Array` extension.

**View changes:**

| File | Change |
| --- | --- |
| `HarmoniaPlayerApp.swift` | main window scene adds `.environment(appState.playlistCollection)`; Mini Player scene adds `.environment(appState.playlistCollection)` and `.environment(appState.settingsStore)`; File Info `WindowGroup` adds `.environment(appState.playlistCollection)`. C3 audit result: Equalizer and Settings host no migrated view and take no new injection. Injection comments updated |
| `PlaylistView.swift` | `@EnvironmentObject appState` removed; `@Environment(PlaylistCollection.self)`, `@Environment(PlaybackController.self)`, `@Environment(SettingsStore.self)` added (`AlertCenter` already present); `@Bindable` for the Table selection binding (`$playlistCollection.selectedTrackIDs`, C4); every playlist read / call on the collection, `play(trackID:)` / `currentTrack` / `playingPlaylistID` / `isShuffled` / `shuffleQueue` / `shuffleQueueIndex` on the controller, `isProUnlocked` / `languageBundle` on the settings store, `PlaylistCollection.proOnlyFormats`; `playNext(id, afterCurrent: playbackController.currentTrack?.id)`; header rewritten |
| `MiniPlayerView.swift` | `@Environment(PlaylistCollection.self)` for `playlists` / `activePlaylistIndex` / `playlist`; `@Environment(SettingsStore.self)` for `isProUnlocked` and `L()`; `PlaylistCollection.proOnlyFormats`; `@EnvironmentObject appState` stays for `.focusedSceneObject(appState)` and `switchMiniPlayerPlaylist`; header updated |
| `PlayerView.swift` | `@Environment(PlaylistCollection.self)` for the three `playlist.tracks.isEmpty` reads; `@EnvironmentObject appState` stays for `L()`; header updated |
| `FileInfoView.swift` | `@Environment(PlaylistCollection.self)` for the track lookup; `@EnvironmentObject appState` stays for `L()`; header updated |
| `HarmoniaPlayerCommands.swift` | undo / redo / `canUndo` / `canRedo`, `selectedTrackIDs`, `showFileInfo`, `newPlaylist`, `deletePlaylist`, `playlist`, `isPerformingBlockingOperation`, `writeExport`, `importPlaylist` read `appState?.playlistCollection.…` (plan §6.0); `exportPlaylist(appState:)` / `importPlaylist(appState:)` keep their signature and use the dotted path inside |

`ContentView.swift`, `LyricsPanel.swift`, `EQView.swift`, `EQWindow.swift`,
`SettingsView.swift`, `PaywallView.swift`, `AppDelegate.swift`: unchanged.

### Acceptance Criteria

1. AC1: `Shared/Models/PlaylistCollection.swift`,
   `Shared/Models/PlaylistCollection+M3U8.swift`, and
   `Shared/Models/PlaybackController+PlaylistReactions.swift` exist with
   the members of the Public API shape, including `nonisolated deinit {}`
   on the collection; `Shared/Models/AppState+Playlist.swift` and
   `Shared/Models/AppState+M3U8.swift` do not exist.
2. AC2: `AppState.swift` contains no `@Published`, no `PersistenceKey`,
   no `static` member, no `: PlaylistContext`, and no computed property
   other than `languageBundle`; its declared methods are exactly `init`,
   `saveState()`, `showPaywallIfNeeded()`, `switchMiniPlayerPlaylist(to:)`,
   and `nonisolated deinit`; `import Combine` and `ObservableObject` are
   present.
3. AC3: `PlaybackController.swift` declares
   `let playlistContext: any PlaylistContext` and no
   `weak var playlistContext`; `grep -n "guard let context = playlistContext"
   PlaybackController.swift PlaybackController+Navigation.swift` has no
   match; `PlaylistContext.swift` differs from the Slice 19 version only in
   its doc comment and the removed `extension AppState` line.
4. AC4: `git diff --stat` for `NowPlayingCoordinator.swift`,
   `EQCoordinator.swift`, `ContentView.swift`, `LyricsPanel.swift`,
   `AppDelegate.swift`, and `HarmoniaPlayer.xcodeproj/project.pbxproj` is
   empty at the code commit.
5. AC5: every TDD-matrix test passes in the file its Test File Decision
   names; the nine deleted test files no longer exist; the eight new test
   files exist; `FakeInfrastructure/FakePlaylistContext.swift` is
   unchanged.
6. AC6: full ⌘U suite green; final unit-test count = pre-slice count
   − 5 (deleted rows) + 37 (new rows); moved rows change file, never
   disappear. UITests unchanged (9). Pre-slice count: 531 passed /
   5 skipped / 0 failed on the 63fb1d2 tree (4149a95 is docs-only on top
   of it) → target 563 passed / 5 skipped.
7. AC7: `slice_12_micro.md` baseline — the rows of
   `AppStatePersistenceTests.swift` (20), `AppStateFormatGatingTests.swift`
   (8), and `AppStateUndoTests.swift` (2) retire with their files (30;
   test-target total 366 → 336 if the re-measured rows hold);
   `AppStateTests.swift` (2), `MiniPlayerViewTests.swift` (2),
   `AppStateReplayGainTests.swift` (20), `PlaylistView.swift` (16), and
   `HarmoniaPlayerApp.swift` (14) are re-measured and updated if the
   counts change; every added file and every touched file without a row
   builds with zero warnings. Table update + Slice 20-A re-measurement
   note land with the close-out.
8. AC8 (manual, binary): each flow behaves as before —
   (a) files added by drag-and-drop onto the table and by ⌘O; one track
   removed from the context menu; several selected tracks removed at
   once; a track dragged to a new position; a column header sorted and
   the order restored from the toolbar button;
   (b) the playing track removed while playing → playback continues with
   the first track of the playlist and the row icon follows; the playing
   track removed while paused → no track shown, nothing plays;
   (c) a tab created, renamed inline, switched, and deleted from its
   context menu; deleting the playing tab stops playback;
   (d) ⌘Z after adding files removes them, ⌘⇧Z re-adds them; the Undo /
   Redo items are disabled when there is nothing to undo / redo;
   (e) Export Playlist from the File menu and from a non-active tab's
   context menu writes an `.m3u8` of the right playlist; Import Playlist
   creates a tab named after the file; an import with a missing file
   shows the skipped-files alert;
   (f) app quit with ⌘Q → relaunch restores the playlists, the active tab,
   and strikes through a track whose file was moved to the Trash;
   (g) the Mini Player playlist picker switches to the chosen playlist and
   starts its first track; choosing the current playlist restarts it;
   (h) with Shuffle on, Play Next from the context menu plays that track
   after the current one; adding files with Shuffle on lists them in the
   shuffle-queue popover;
   (i) main window, Mini Player, Equalizer, File Info, and Settings all
   open without a missing-injection crash — Mini Player and File Info
   first;
   (j) the File Info window shows the track; after the track is removed
   from the playlist it shows the unavailable placeholder and stays open;
   (k) the player panel's transport buttons are disabled while the
   playlist is empty and enabled once a track is added;
   (l) ⌘I with a selected row opens File Info; Get Info is disabled with
   no selection.

### Out of Scope

- See slice-level Out of Scope.

### Deferred Backlog

1. BL-20A-01 — Removing the playing track resolves the next track
   wrongly: with shuffle off it always continues with the first track
   (the `insertionOrder` lookup runs after the id was removed from it, so
   the "track that moved into the slot", repeat-all wrap, and
   stop-at-end branches are unreachable); with shuffle on the queue entry
   at `shuffleQueueIndex` is resolved before the removed id leaves the
   queue, so it resolves to the removed track and playback clears
   instead of advancing. The behaviour moves as it is; the fix (play the
   track that moved into the slot; wrap only under repeat-all; otherwise
   stop; under shuffle advance to the next queue entry) is its own defect
   slice after the current v1.0.1 items.

### Files

- HarmoniaPlayer Application Layer:
  - add `Shared/Models/PlaylistCollection.swift`,
    `Shared/Models/PlaylistCollection+M3U8.swift`,
    `Shared/Models/PlaybackController+PlaylistReactions.swift`
  - modify `Shared/Models/AppState.swift`,
    `Shared/Models/PlaybackController.swift` (init, `let` context, guards),
    `Shared/Models/PlaybackController+Navigation.swift` (guards; three
    comment lines), `Shared/Models/PlaylistContext.swift` (doc comment;
    AppState conformance line removed)
  - delete `Shared/Models/AppState+Playlist.swift`,
    `Shared/Models/AppState+M3U8.swift`
- UI: modify `HarmoniaPlayerApp.swift`, `HarmoniaPlayerCommands.swift`,
  `PlaylistView.swift`, `MiniPlayerView.swift`, `PlayerView.swift`,
  `FileInfoView.swift`
- Tests:
  - add `SharedTests/PlaylistCollectionLoadTests.swift`,
    `PlaylistCollectionTrackTests.swift`, `PlaylistCollectionTabTests.swift`,
    `PlaylistCollectionUndoTests.swift`,
    `PlaylistCollectionPersistenceTests.swift`,
    `PlaylistCollectionM3U8Tests.swift`,
    `PlaybackControllerPlaylistReactionTests.swift`,
    `AppStatePlaylistPlaybackTests.swift`
  - delete `SharedTests/AppStatePlayerlistTests.swift`,
    `AppStateMultiPlaylistTests.swift`, `AppStateDragReorderTests.swift`,
    `AppStateUndoTests.swift`, `AppStateFormatGatingTests.swift`,
    `AppStateMetadataTests.swift`, `AppStatePersistenceTests.swift`,
    `AppStateErrorHandlingTests.swift`, `AppStateFileInfoTests.swift`
    (rows move)
  - modify `AppStateTests.swift` (retargets, 2 added, 1 moved in,
    1 deleted), `AppStateReplayGainTests.swift`, `IntegrationTests.swift`,
    `MiniPlayerViewTests.swift` (dotted-path retargets), the seven
    `PlaybackController*Tests.swift` (fixture: context passed at init)
  - `FakeInfrastructure/FakePlaylistContext.swift`,
    `FakePlaylistStore.swift`: no change
  - the test moves are made in the red phase and land with the single
    code commit
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change needed
  (`PBXFileSystemSynchronizedRootGroup`)
- Docs at green: `api_reference.md`, `module_boundary.md`,
  `development_guide.md`, `implementation_guide_swift.md`, `workflow.md`
  (§4.2 example), `architecture.md` (AppState file list; HC 5-area audit)
- Docs at close-out: `slice_12_micro.md` (retired rows + re-measurement
  note), this spec (status ticks, execution amendments),
  `HarmoniaPlayer_development_plan.md` (slice table tick)

### TDD matrix

The `PlaylistCollection*Tests` files build the SUT directly:

```swift
let tagReader = FakeTagReaderService()
let store = FakePlaylistStore()
let defaults = UserDefaults(suiteName: "hp-test-\(UUID().uuidString)")!
let sut = PlaylistCollection(tagReaderService: tagReader,
                             fileDropService: FileDropService(),
                             playlistStore: store,
                             undoManager: UndoManager(),
                             alertCenter: AlertCenter(),
                             settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
                             userDefaults: defaults)
```

The closures stay `nil` in collection tests except where a row installs a
recorder. A relaunch is simulated by building a second collection on the
same `FakePlaylistStore` and suite. `PlaybackControllerPlaylistReactionTests`
builds the controller as the Slice 19 files do, with
`playlistContext: context` at init, and seeds `context.playlists[0].tracks`.
`AppStatePlaylistPlaybackTests` builds `AppState` with `FakeCoreProvider`
and reads both stores. All eight new files use the `async tearDown +
makeSUT` fixture shape. Moved rows keep their names unless noted; their
Given / When / Then are unchanged apart from the fixture (reads of
`sut.playlist`, `sut.playlists` stay; `sut.lastError` → `alertCenter.lastError`;
`sut.skipped…` → `alertCenter.skipped…`; `sut.allowDuplicateTracks` →
`settingsStore.allowDuplicateTracks`), so the table states them briefly.

**Moved rows (99)**

| # | Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- | --- |
| 1 | `testLoad_EmptyPlaylist_AddsTrack` | empty | `load` 1 URL | `playlist.count == 1` | Move from `AppStatePlayerlistTests.swift` → New `PlaylistCollectionLoadTests.swift` |
| 2 | `testLoad_ExistingPlaylist_AppendsTrack` | 1 loaded | `load` 1 | 2 | same move |
| 3 | `testLoad_MultipleURLs_AddsAll` | empty | `load` 2 | 2 | same move |
| 4 | `testLoad_DerivesTitleFromFilename` | — | `load` `my-song.mp3` | title `"my-song"` | same move |
| 5 | `testLoad_DuplicateURL_DefaultBehaviour_IsSkipped` | URL loaded | `load` same URL | count 1; `alertCenter.skippedDuplicateURLs.count == 1` | same move |
| 6 | `testLoad_DuplicateURL_WhenAllowed_IsAdded` | `settingsStore.allowDuplicateTracks = true`, URL loaded | `load` same URL | count 2; skipped empty | same move |
| 7 | `testIsPerformingBlockingOperation_InitiallyFalse` | init | — | `false` | same move |
| 8 | `testLoad_ResetsBlockingFlagOnCompletion` | — | `load` | `false` after | same move |
| 9 | `testLoad_BookmarkCapturedAfterLoad` (was `testAppStatePlaylistLoad_BookmarkCapturedAfterLoad`) | real temp file | `load` | track accessible; encode / decode round-trips | same move |
| 10 | `testLoad_CallsTagReaderForEachURL` | 3 URLs | `load` | `readMetadataCallCount == 3` | Move from `AppStateMetadataTests.swift` → `PlaylistCollectionLoadTests.swift` |
| 11 | `testLoad_UsesMetadataTitle` | stubbed title | `load` | title used | same move |
| 12 | `testLoad_UsesMetadataArtist` | stubbed artist | `load` | artist used | same move |
| 13 | `testLoad_UsesMetadataAlbum` | stubbed album | `load` | album used | same move |
| 14 | `testLoad_UsesMetadataDuration` | stubbed 180 s | `load` | `180.0` | same move |
| 15 | `testLoad_MultipleURLs_AllEnriched` | 2 stubs | `load` | both enriched in order | same move |
| 16 | `testLoad_IsAdditive_WithMetadata` | 1 loaded | `load` 1 | 2, titles in order | same move |
| 17 | `testRefresh_FillsArtworkWhenNil` | track with nil artwork; stub now carries artwork | `refreshMetadataIfNeeded()` | artwork filled | same move |
| 18 | `testLoad_MetadataError_FallsBackToURLDerivedTrack` | stubbed error | `load` | title from filename | Move from `AppStateErrorHandlingTests.swift` → `PlaylistCollectionLoadTests.swift` |
| 19 | `testLoad_MetadataError_SetsLastError` | stubbed error | `load` | `alertCenter.lastError == .failedToOpenFile` | same move |
| 20 | `testLoad_PartialError_SuccessfulURLsStillEnriched` | one good, one error | `load` | good enriched, bad URL-derived | same move |
| 21 | `testLoad_NoError_LastErrorRemainsNil` | stub metadata | `load` | `alertCenter.lastError == nil` | same move |
| 22 | `testLoad_MultipleErrors_LastErrorIsSet` | two errors | `load` | `lastError != nil` | same move |
| 23 | `testLoad_FLAC_FreeTier_BlockedAsUnsupported` | Free | `load` `.flac` | empty; `alertCenter.skippedUnsupportedURLs.count == 1` | Move from `AppStateFormatGatingTests.swift` → `PlaylistCollectionLoadTests.swift` |
| 24 | `testLoad_DSF_FreeTier_BlockedAsUnsupported` | Free | `load` `.dsf` | same | same move |
| 25 | `testLoad_DFF_FreeTier_BlockedAsUnsupported` | Free | `load` `.dff` | same | same move |
| 26 | `testLoad_UnsupportedFormat_BlockedWithAlert` | — | `load` `.xyz` | empty; skipped 1 | same move |
| 27 | `testClearPlaylist_WithTracks_EmptiesPlaylist` | 3 tracks | `clearPlaylist()` | empty | Move from `AppStatePlayerlistTests.swift` → New `PlaylistCollectionTrackTests.swift` |
| 28 | `testRemoveTrack_ExistingID_RemovesTrack` | 3 | `removeTrack(b)` | 2, b gone | same move |
| 29 | `testRemoveTrack_InvalidID_NoChange` | 3 | `removeTrack(UUID())` | 3 | same move |
| 30 | `testRemoveTracks_AllSelected_EmptiesPlaylist` | 3 | `removeTracks(all)` | empty | same move |
| 31 | `testRemoveTracks_Subset_RemovesOnlySelectedKeepsOrder` | a b c d | `removeTracks([b, d])` | `[a, c]` | same move |
| 32 | `testMoveTrack_ValidIndices_Reorders` | a b c | `moveTrack(0 → 3)` | last is a | same move |
| 33 | `testPlayNext_MovesTrackAfterCurrentTrack` | a b c | `playNext(c, afterCurrent: a)` | `[a, c, b]` | same move (seeded current, no `play`) |
| 34 | `testPlayNext_UpdatesInsertionOrder` | a b c | `playNext(c, afterCurrent: a)` | `insertionOrder == tracks.map(\.id)` | same move |
| 35 | `testPlayNext_NoCurrentTrack_InsertsAtFront` | a b c | `playNext(c, afterCurrent: nil)` | c first | same move |
| 36 | `testMoveTrack_UpdatesInsertionOrder` | a b c | move 2 → 0 | `[c, a, b]` | Move from `AppStateDragReorderTests.swift` → `PlaylistCollectionTrackTests.swift` |
| 37 | `testMoveTrack_InsertionOrder_MatchesTracks` | a b c | move 0 → 3 | order matches | same move |
| 38 | `testMoveTrackIDBefore_MovesDraggedBeforeTarget` | a b c | `moveTrack(id: c, before: a)` | `[c, a, b]` | same move |
| 39 | `testMoveTrackIDBefore_NilTarget_AppendsToEnd` | a b c | `moveTrack(id: a, before: nil)` | `[b, c, a]` | same move |
| 40 | `testMoveTrackIDBefore_KeepsInsertionOrderInSync` | a b c | `moveTrack(id: c, before: a)` | `insertionOrder == [c, a, b]` | same move |
| 41 | `testMoveTrackIDBefore_NoOpWhenColumnSortActive` | `sortKey = .title` | `moveTrack(id:before:)` | unchanged | same move |
| 42 | `testMoveTrackIDBefore_DropOntoSelf_NoOp` | a b c | `moveTrack(id: b, before: b)` | unchanged | same move |
| 43 | `testShowFileInfo_SetsAlertCenterTrack` | track loaded | `showFileInfo(trackID:)` | `alertCenter.fileInfoTrack?.id` matches | Move from `AppStateFileInfoTests.swift` → `PlaylistCollectionTrackTests.swift` |
| 44 | `testShowFileInfo_UnknownID_NoOp` | empty | `showFileInfo(UUID())` | `fileInfoTrack == nil` | same move |
| 45 | `testInitial_PlaylistIsEmpty` | init | — | `playlist.isEmpty` | Move from `AppStatePlayerlistTests.swift` → New `PlaylistCollectionTabTests.swift` |
| 46 | `testInitialState_HasOnePlaylist` | init | — | 1 | Move from `AppStateMultiPlaylistTests.swift` → `PlaylistCollectionTabTests.swift` |
| 47 | `testInitialState_ActiveIndexIsZero` | init | — | 0 | same move |
| 48 | `testPlaylist_ComputedReturnsActive` | `newPlaylist("Rock")`, index 1 | — | `playlist == playlists[1]` | same move |
| 49 | `testNewPlaylist_IncreasesCount` | — | `newPlaylist("Rock")` | 2 | same move |
| 50 | `testNewPlaylist_SetsActiveIndex` | — | `newPlaylist` | index 1 | same move |
| 51 | `testNewPlaylist_EmptyName_UsesDefault` | — | `newPlaylist("")` | `"Playlist 2"` | same move |
| 52 | `testRenamePlaylist_UpdatesName` | — | `renamePlaylist(0, "Jazz")` | renamed | same move |
| 53 | `testRenamePlaylist_OutOfRange_NoOp` | — | `renamePlaylist(99, …)` | unchanged | same move |
| 54 | `testDeletePlaylist_DecreasesCount` | 2 | `deletePlaylist(1)` | 1 | same move |
| 55 | `testDeletePlaylist_LastOne_AutoInsertsPlaylist1` | 1 | `deletePlaylist(0)` | 1, `"Playlist 1"` | same move |
| 56 | `testDeletePlaylist_LastOne_ActiveIndexStaysZero` | 1 | `deletePlaylist(0)` | index 0 | same move |
| 57 | `testDeletePlaylist_AdjustsActiveIndex_WhenDeletingActive` | 2, index 1 | `deletePlaylist(1)` | 0 | same move |
| 58 | `testDeletePlaylist_DecrementsActiveIndex_WhenDeletingBeforeActive` | 3, index 2 | `deletePlaylist(0)` | 1 | same move |
| 59 | `testDeletePlaylist_OutOfRange_NoOp` | — | `deletePlaylist(99)` | unchanged | same move |
| 60 | `testSwitchPlaylist_ValidIndex_ChangesActiveIndex` | 2 | `switchPlaylist(to: 1)` | 1 | same move |
| 61 | `testSwitchPlaylist_SameIndex_IsNoOp` | index 1 | `switchPlaylist(to: 1)` | 1 | same move |
| 62 | `testSwitchPlaylist_SameIndex_PreservesUndoStack` | undo stack populated | `switchPlaylist(to: 0)` | `canUndo` | same move |
| 63 | `testSwitchPlaylist_OutOfRangeIndex_IsNoOp` | — | `switchPlaylist(to: 99)` | 0 | same move |
| 64 | `testSwitchPlaylist_DifferentIndex_ClearsUndoStack` | populated on 0 | `switchPlaylist(to: 1)` | `!canUndo` | same move |
| 65 | `testUndoLoad_RemovesAddedTracks` | — | `load` 1 → `undo` | empty | Move from `AppStateUndoTests.swift` → New `PlaylistCollectionUndoTests.swift` |
| 66 | `testUndoLoad_WithMultipleTracks` | — | `load` 3 → `undo` | empty | same move |
| 67 | `testUndoRemoveTrack_ReInsertsTrack` | 2 seeded | `removeTrack` → `undo` | 2 | same move |
| 68 | `testUndoRemoveTracks_ReInsertsWholeBatch` | a b c | `removeTracks([a, c])` → `undo` | 3 | same move |
| 69 | `testUndoMoveTrack_RestoresOrder` | a b c | move → `undo` | original order | same move |
| 70 | `testUndoMoveTrackIDBefore_RestoresOrder` | a b c | `moveTrack(id:before:)` → `undo` | original order | same move |
| 71 | `testRedoLoad_ReAddsTrack` | — | `load` → `undo` → `redo` | 1 | same move |
| 72 | `testPlayNext_PersistsOrderAfterSaveAndRestore` | a b c | `playNext(c, afterCurrent: a)` | second collection on the same store reads `[a, c, b]` | Move from `AppStatePlayerlistTests.swift` → New `PlaylistCollectionPersistenceTests.swift` |
| 73 | `testSaveAndRestore_Playlist_SurvivesRelaunch` | 3 loaded | `saveState()` → `restoreState()` | 3 | Move from `AppStatePersistenceTests.swift` → `PlaylistCollectionPersistenceTests.swift` |
| 74 | `testSaveAndRestore_TrackURL_Preserved` | 1 loaded | save → restore | URL equal | same move |
| 75 | `testSaveAndRestore_SortKey_Survives` | sorted | save → restore | `.title` | same move |
| 76 | `testRestoreState_WhenNoData_UsesDefaults` | nothing stored | `restoreState()` | 1 empty playlist | same move |
| 77 | `testLoad_ImmediatelySavesPlaylist` | — | `load` | second collection sees 1 | same move |
| 78 | `testRemoveTrack_ImmediatelySaves` | 2 | `removeTrack` | second sees 1 | same move |
| 79 | `testClearPlaylist_ImmediatelySaves` | 2 | `clearPlaylist()` | second sees 0 | same move |
| 80 | `testNewPlaylist_ImmediatelySaves` | — | `newPlaylist` | second sees 2 | same move |
| 81 | `testRenamePlaylist_ImmediatelySaves` | — | `renamePlaylist` | second sees name | same move |
| 82 | `testDeletePlaylist_ImmediatelySaves` | 2 | `deletePlaylist(1)` | second sees 1 | same move |
| 83 | `testMoveTrack_ImmediatelySaves` | A B | move | second sees B A | same move |
| 84 | `testApplySort_ImmediatelySaves` | — | `applySort` | second sees `.title` | same move |
| 85 | `testRestoreInsertionOrder_ImmediatelySaves` | sorted | `restoreInsertionOrder()` | second sees `.none` | same move |
| 86 | `testSaveState_WritesPlaylistsToStore_NotUserDefaults` | — | `load` | store has 1; no `hp.playlists` in defaults | same move |
| 87 | `testRestoreState_ReadsPlaylistsFromStore` | store seeded | `restoreState()` | restored | same move |
| 88 | `testRestoreState_MigratesLegacyUserDefaultsPlaylists` | legacy key, empty store | `restoreState()` | migrated; key removed | same move |
| 89 | `testImportPlaylist_ResetsBlockingFlagOnCompletion` | missing file | `importPlaylist` | flag `false` | Move from `AppStatePlayerlistTests.swift` → New `PlaylistCollectionM3U8Tests.swift` |
| 90 | `testImportPlaylist_SkipsUnsupportedFormat` | m3u8 with `.xyz` | `importPlaylist` | empty; `alertCenter.skippedImportURLs.count == 1` | Move from `AppStateFormatGatingTests.swift` → `PlaylistCollectionM3U8Tests.swift` |
| 91 | `testImportPlaylist_SkipsUnsupportedFormat_KeepsSupported` | `.mp3` + `.xyz` | `importPlaylist` | 1 track; 1 skipped | same move |
| 92 | `testImportPlaylist_FLAC_BlockedAsUnsupported` | `.flac` | `importPlaylist` | empty; 1 skipped | same move |
| 93 | `testClearPlaylist_NilsCurrentTrack` | track playing | `playlistCollection.clearPlaylist()` | `playbackController.currentTrack == nil` | Move from `AppStatePlayerlistTests.swift` → New `AppStatePlaylistPlaybackTests.swift` |
| 94 | `testRemoveTrack_CurrentTrack_StopsPlayback` | only track playing | `removeTrack` | empty; `.stopped` after the task | same move |
| 95 | `testRemoveTrack_OtherTrack_KeepsCurrentTrack` | a playing | `removeTrack(b)` | `currentTrack == a` | same move |
| 96 | `testRemoveTracks_IncludingCurrentTrack_StopsPlayback` | a playing | `removeTracks([a, b])` | empty; `currentTrack == nil`; `.stopped` | same move |
| 97 | `testRemoveTracks_ExcludingCurrentTrack_KeepsCurrentTrack` | a playing | `removeTracks([b, c])` | `[a]`; `currentTrack == a` | same move |
| 98 | `testSwitchPlaylist_DoesNotStopPlayback` | playing | `newPlaylist`; `activePlaylistIndex = 1` | `.playing` | Move from `AppStateMultiPlaylistTests.swift` → `AppStatePlaylistPlaybackTests.swift` |
| 99 | `testClearLastError_ErrorState_BecomesStopped` | controller `.error`, surface populated | `alertCenter.clearLastError()` | `.stopped`; surface cleared | Move from `AppStateErrorHandlingTests.swift` → Extend `AppStateTests.swift` |

**New rows (37)**

| # | Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- | --- |
| 100 | `testLoad_CallsOnTracksAppendedWithAddedIDs` | recorder on `onTracksAppended` | `load` 2 URLs | called once with the two new ids in order | New `PlaylistCollectionLoadTests.swift` |
| 101 | `testLoad_NothingAdded_DoesNotCallOnTracksAppended` | URL loaded, recorder | `load` same URL (duplicate) | not called | New `PlaylistCollectionLoadTests.swift` |
| 102 | `testRemoveTrack_CallsOnTrackRemoved` | 2 tracks, recorder | `removeTrack(a)` | called once with a | New `PlaylistCollectionTrackTests.swift` |
| 103 | `testRemoveTrack_UnknownID_DoesNotCallOnTrackRemoved` | recorder | `removeTrack(UUID())` | not called | New `PlaylistCollectionTrackTests.swift` |
| 104 | `testRemoveTracks_CallsOnTracksRemovedWithMatchingIDs` | a b c, recorder | `removeTracks([a, c, UUID()])` | called with `{a, c}` | New `PlaylistCollectionTrackTests.swift` |
| 105 | `testRemoveTracks_NoMatch_DoesNotCallOnTracksRemoved` | a, recorder | `removeTracks([UUID()])` | not called | New `PlaylistCollectionTrackTests.swift` |
| 106 | `testClearPlaylist_CallsOnPlaylistCleared` | recorder | `clearPlaylist()` | called once | New `PlaylistCollectionTrackTests.swift` |
| 107 | `testPlayNext_CallsOnTrackQueuedNext` | a b c, recorder | `playNext(c, afterCurrent: a)` | called once with c | New `PlaylistCollectionTrackTests.swift` |
| 108 | `testDeletePlaylist_CallsOnPlaylistDeletedWithID` | 2, recorder | `deletePlaylist(1)` | called with `playlists[1].id` | New `PlaylistCollectionTabTests.swift` |
| 109 | `testDeletePlaylist_OutOfRange_DoesNotCallOnPlaylistDeleted` | recorder | `deletePlaylist(99)` | not called | New `PlaylistCollectionTabTests.swift` |
| 110 | `testUndoAndRedo_ForwardToUndoManager` | `load` 1 | `undo()` then `redo()` | empty, then 1 | New `PlaylistCollectionUndoTests.swift` |
| 111 | `testInit_RestoresPlaylistsFromStore` | store seeded with one named playlist | init | `playlists.first?.name` matches | New `PlaylistCollectionPersistenceTests.swift` |
| 112 | `testInit_ClampsActivePlaylistIndexToRange` | store has 2 playlists; suite `hp.activePlaylistIndex = 5` | init | index 1 | New `PlaylistCollectionPersistenceTests.swift` |
| 113 | `testInit_MarksMissingFilesInaccessible` | stored track whose `originalPath` does not exist | init | `isAccessible == false` | New `PlaylistCollectionPersistenceTests.swift` |
| 114 | `testSaveState_WritesActivePlaylistIndex` | `newPlaylist` (index 1) | `saveState()` | suite `hp.activePlaylistIndex == 1` | New `PlaylistCollectionPersistenceTests.swift` |
| 115 | `testWriteExport_WritesActivePlaylistAsM3U8` | 1 track | `writeExport(to:pathStyle: .absolute)` | file starts with `#EXTM3U` and contains the track path | New `PlaylistCollectionM3U8Tests.swift` |
| 116 | `testWriteExport_PlaylistAt_WritesThatPlaylist` | 2 playlists, track in index 0, active 1 | `writeExport(playlistAt: 0, …)` | file contains the track path | New `PlaylistCollectionM3U8Tests.swift` |
| 117 | `testWriteExport_PlaylistAt_OutOfRange_WritesNothing` | — | `writeExport(playlistAt: 99, …)` | no file at the URL | New `PlaylistCollectionM3U8Tests.swift` |
| 118 | `testImportPlaylist_CreatesTabNamedAfterFile` | m3u8 `mix.m3u8` with one `.mp3` | `importPlaylist` | new active playlist named `"mix"` with 1 track | New `PlaylistCollectionM3U8Tests.swift` |
| 119 | `testImportPlaylist_UnreadableFile_SetsLastError` | missing file | `importPlaylist` | `alertCenter.lastError == .failedToOpenFile`; playlists unchanged | New `PlaylistCollectionM3U8Tests.swift` |
| 120 | `testHandleTracksAppended_Shuffled_InsertsAfterCurrentPosition` | shuffle on, queue `[a, b, c]`, index 0 | `handleTracksAppended([d])` | queue count 4; d's index ≥ 1 | New `PlaybackControllerPlaylistReactionTests.swift` |
| 121 | `testHandleTracksAppended_NotShuffled_LeavesQueueEmpty` | shuffle off | `handleTracksAppended([d])` | queue empty | same file |
| 122 | `testHandleTrackRemoved_PlayingTrack_PlaysFirstTrack` | a playing of a b c; context now holds b c | `handleTrackRemoved(a)` | after the task `currentTrack == b`, `.playing` | same file |
| 123 | `testHandleTrackRemoved_PlayingLastTrack_Stops` | only track playing; context empty | `handleTrackRemoved(a)` | `.stopped`, `currentTime == 0`, `currentTrack == nil` | same file |
| 124 | `testHandleTrackRemoved_PausedCurrentTrack_ClearsCurrentTrackOnly` | a paused | `handleTrackRemoved(a)` | `currentTrack == nil`; `stopCallCount` unchanged | same file |
| 125 | `testHandleTrackRemoved_OtherTrack_LeavesPlaybackUnchanged` | a playing | `handleTrackRemoved(b)` | `currentTrack == a`, `.playing` | same file |
| 126 | `testHandleTrackRemoved_Shuffled_RemovesFromQueueAndShiftsIndex` | queue `[x, y, z]`, index 2 | `handleTrackRemoved(x)` (not current) | queue `[y, z]`, index 1 | same file |
| 127 | `testHandleTracksRemoved_IncludingCurrent_StopsAndClears` | a playing | `handleTracksRemoved([a, b])` | `.stopped`, `currentTrack == nil`, `currentTime == 0` | same file |
| 128 | `testHandleTracksRemoved_ExcludingCurrent_LeavesPlaybackUnchanged` | a playing | `handleTracksRemoved([b])` | `currentTrack == a`, `.playing` | same file |
| 129 | `testHandleTracksRemoved_Shuffled_FiltersQueueAndClampsIndex` | queue `[x, y, z]`, index 2 | `handleTracksRemoved([y, z])` | queue `[x]`, index 0 | same file |
| 130 | `testHandlePlaylistCleared_ClearsCurrentTrackOnly` | a playing | `handlePlaylistCleared()` | `currentTrack == nil`; `playbackState` unchanged; `stopCallCount` unchanged | same file |
| 131 | `testHandlePlaylistDeleted_PlayingPlaylist_Stops` | a playing in PL1 | `handlePlaylistDeleted(PL1.id)` | after the task `.stopped`, `currentTrack == nil` | same file |
| 132 | `testHandlePlaylistDeleted_OtherPlaylist_NoOp` | a playing in PL1 | `handlePlaylistDeleted(PL2.id)` | `.playing` | same file |
| 133 | `testHandleTrackQueuedNext_Shuffled_PlacesTrackAtNextQueuePosition` | queue `[a, b, c]`, index 0 | `handleTrackQueuedNext(c)` | queue `[a, c, b]` | same file |
| 134 | `testHandleTrackQueuedNext_NotShuffled_NoOp` | shuffle off | `handleTrackQueuedNext(c)` | queue empty | same file |
| 135 | `testInit_PlaylistCollectionRestoresFromInjectedStore` | `FakePlaylistStore` seeded | `AppState(…, playlistStore:)` | `appState.playlistCollection.playlists.first?.name` matches | Extend `AppStateTests.swift` |
| 136 | `testInit_PlaybackControllerReadsPlaylistCollection` | one track loaded through `appState.playlistCollection` | `appState.playbackController.play()` | `currentTrack` is that track | Extend `AppStateTests.swift` |

**Retargeted at green (no row change)**

| Test | Change |
| --- | --- |
| `AppStateTests.testInit_FreeUser_WiresDependenciesCorrectly`, `testInit_ProUser_WiresDependenciesCorrectly` | `appState.settingsStore.isProUnlocked`, `appState.playbackController.playbackService`, `appState.playlistCollection.tagReaderService` |
| `AppStateTests.testInit_DoesNotExecuteBehavior` | `appState.playbackController.playbackService.state` |
| `AppStateTests.testAppState_TagReaderService_IsNotNil`, `_IsFromProvider`, `_NoMethodsCalled` | `sut.playlistCollection.tagReaderService` |
| `AppStateTests.testInit_WiresCurrentTrackChangeToLyricsStore` | `appState.playlistCollection.load(urls:)`, `appState.playlistCollection.playlist` |
| `AppStateReplayGainTests` (3 rows) | `sut.playlistCollection.load(urls:)`, `sut.playbackController.play(trackID:)` |
| `IntegrationTests` (11 rows) | `sut.playlistCollection.load` / `.playlist`; `sut.playbackController.play(trackID:)` / `.stop()` / `.playbackState` / `.currentTrack` / `.currentTime`; `sut.alertCenter.lastError` / `.skippedUnsupportedURLs`; `tearDown` stops through the controller; header count corrected |
| `MiniPlayerViewTests.testMiniPlayerView_InitializesWithNoTrack`, `_InitializesAfterLoad` | `appState.playbackController.currentTrack`; `appState.playlistCollection.load` / `.playlist` |
| `MiniPlayerViewTests.testSwitchMiniPlayerPlaylist_*` (3 rows) | `appState.playlistCollection.newPlaylist` / `.playlists` / `.activePlaylistIndex`; the method stays on AppState |
| the seven `PlaybackController*Tests` | `makeSUT` passes `playlistContext: context` (a `FakePlaylistContext`) at init; the `sut.playlistContext = …` lines go |

**Deleted rows (5)**

| Test | Reason |
| --- | --- |
| `AppStatePlayerlistTests.testInitial_CurrentTrackIsNil` | unit-test-core Smell 4 — a controller default already pinned by `PlaybackControllerTrackTests` |
| `AppStateFormatGatingTests.testPlayGate_MP3_FreeTier_Proceeds`, `testPlayGate_M4A_FreeTier_Proceeds` | Smell 4 — the gate is disabled, so both are the `play(trackID:)` load path pinned by `PlaybackControllerTrackTests.testPlayTrack_CallsLoad` |
| `AppStateFormatGatingTests.testPaywallDismissedThisSession_DefaultIsFalse` | Smell 4 — pinned by `AlertCenterTests.testInitialState_AllSurfacesCleared` |
| `AppStateTests.testAppState_InitialLastError_IsNil` | Smell 4 — same |

Count: 99 moved, 37 new, 5 deleted → net +32 (AC6).

Red phase — the collection skeleton holds every property at its default
(one empty `"Playlist 1"`, index 0), has empty method bodies (`saveState()`,
`restoreState()`, `showFileInfo`, the M3U8 methods included), restores
nothing, calls no closure, and `canUndo` / `canRedo` read the manager;
the controller's `handle…` methods are empty and its init takes the
context; AppState constructs the collection and passes it to the
controller but keeps its own playlist members and forwarders until green
(Slice 16 / 19 precedent). Of the 136 rows run against the skeleton:

- Green from the start (default-value guards): rows 7, 45, 46, 47, 76,
  121, 134.
- Negative guards, vacuously green against the honest empty skeleton:
  rows 29, 53, 59, 61, 63, 101, 103, 105, 109, 117, 125, 128, 132, and
  the retargeted negative rows.
- Expected red: every other row. The observed red set is recorded at
  close-out.

### Public API shape

```swift
@MainActor @Observable
final class PlaylistCollection: PlaylistContext {

    // Observed state (plan §3 rows 27–30)
    var playlists: [Playlist]
    var activePlaylistIndex: Int = 0
    var selectedTrackIDs = Set<Track.ID>()
    var isPerformingBlockingOperation = false
    var playlist: Playlist { get }                 // playlists[activePlaylistIndex]

    // Format classification
    static let freeFormats: Set<String>
    static let proOnlyFormats: Set<String>
    static var allowedFormats: Set<String> { get }
    static let saveBatchSize: Int

    // Dependencies
    let undoManager: UndoManager                   // levelsOfUndo = 10
    let tagReaderService: TagReaderService

    // Root-wired notifications
    @ObservationIgnored var onTracksAppended: (([Track.ID]) -> Void)?
    @ObservationIgnored var onTrackRemoved: ((Track.ID) -> Void)?
    @ObservationIgnored var onTracksRemoved: ((Set<Track.ID>) -> Void)?
    @ObservationIgnored var onPlaylistCleared: (() -> Void)?
    @ObservationIgnored var onPlaylistDeleted: ((Playlist.ID) -> Void)?
    @ObservationIgnored var onTrackQueuedNext: ((Track.ID) -> Void)?

    init(tagReaderService: TagReaderService,
         fileDropService: FileDropService,
         playlistStore: PlaylistStore,
         undoManager: UndoManager,
         alertCenter: AlertCenter,
         settingsStore: SettingsStore,
         userDefaults: UserDefaults)              // ends with restoreState()

    // Playlist operations
    func handleFileDrop(urls: [URL]) async
    func load(urls: [URL]) async
    func clearPlaylist()
    func removeTrack(_ trackID: Track.ID)
    func removeTracks(_ ids: Set<Track.ID>)
    /// Re-inserts `trackID` right after `currentID` (at the front when nil).
    func playNext(_ trackID: Track.ID, afterCurrent currentID: Track.ID?)
    func applySort(_ sorted: [Track], key: PlaylistSortKey, ascending: Bool)
    func restoreInsertionOrder()
    func moveTrack(fromOffsets: IndexSet, toOffset: Int)
    func moveTrack(id draggedID: Track.ID, before targetID: Track.ID?)

    // Tabs
    func switchPlaylist(to index: Int)
    func newPlaylist(name: String)
    func renamePlaylist(at index: Int, name: String)
    func deletePlaylist(at index: Int)

    // Undo / redo
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func undo()
    func redo()

    // File info
    func showFileInfo(trackID: Track.ID)

    // Persistence
    /// Writes the playlists to the store and hp.activePlaylistIndex.
    func saveState()
    func restoreState()
    func refreshMetadataIfNeeded() async

    // M3U8 (PlaylistCollection+M3U8.swift)
    func writeExport(to url: URL, pathStyle: M3U8PathStyle) throws
    func writeExport(playlistAt index: Int, to url: URL, pathStyle: M3U8PathStyle) throws
    func importPlaylist(from url: URL) async

    nonisolated deinit {}
}

// PlaybackController changes
init(playbackService: PlaybackService,
     alertCenter: AlertCenter,
     settingsStore: SettingsStore,
     playlistContext: any PlaylistContext,
     userDefaults: UserDefaults)
@ObservationIgnored let playlistContext: any PlaylistContext

// PlaybackController+PlaylistReactions.swift
func handleTracksAppended(_ ids: [Track.ID])
func handleTrackRemoved(_ id: Track.ID)
func handleTracksRemoved(_ ids: Set<Track.ID>)
func handlePlaylistCleared()
func handlePlaylistDeleted(_ id: Playlist.ID)
func handleTrackQueuedNext(_ id: Track.ID)

// AppState after this slice
let alertCenter: AlertCenter
let lyricsStore: LyricsStore
let settingsStore: SettingsStore
let playlistCollection: PlaylistCollection
let playbackController: PlaybackController
let eqCoordinator: EQCoordinator
let nowPlayingCoordinator: NowPlayingCoordinator
var languageBundle: Bundle { get }
init(iapManager:provider:userDefaults:playlistStore:undoManager:lyricsPreferenceStore:eqCoordinator:)
@discardableResult func showPaywallIfNeeded() -> Bool
/// Terminate-time save-all: playbackController.saveVolume(), then playlistCollection.saveState().
func saveState()
/// Mini Player: stop → switch the active playlist → clear undo → play its first track.
func switchMiniPlayerPlaylist(to index: Int) async
nonisolated deinit {}
```

### Implementation notes

- Red-phase skeleton precedent: 9-L / 13-A / 14-A / 16-A / 19-A.
- Construction order in `AppState.init`: alert store → settings store →
  factory and services → EQ coordinator → lyrics store → **playlist
  collection** → playback controller (with the collection as its context)
  → Now Playing coordinator → undo-manager-free wiring. The collection's
  `init` runs `restoreState()`, so the restore happens before the
  controller exists, as today's Step 10 did before the wiring step.
- Ownership is acyclic: AppState → collection (strong); AppState →
  controller (strong) → context (strong, the collection); the collection
  reaches the controller only through the six closures, which capture the
  controller from the root's local `let`.
- `@Observable` `didSet` and observer registration run for assignments
  made after `self` is fully initialised (Slice 16 amendment); the
  collection's `restoreState()` runs inside `init` after every stored
  property is set, so its assignments notify no observer — the same as
  today, where `AppState.init` runs it before any view subscribes.
- The reaction methods keep today's evaluation order inside
  `handleTrackRemoved`: the next-track id is resolved first, then the
  asynchronous stop / play task is started, then the shuffle queue is
  edited (BL-20A-01 documents what that order does).
- `PlaylistView`'s `@Bindable` is declared in `body` (`@Bindable var
  playlistCollection = playlistCollection`) for the Table selection
  binding; C1 keeps the row icon, tab icon, toolbar button, and popover
  observable-correct through the controller environment.
- Token discipline: the moved code gets clean doc comments (the `load`
  comment block and `PlaylistView` header carry stale slice / version
  narrative today); untouched regions keep their tokens for the slice that
  moves them. `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` on added lines before
  the commit.
- Doc obligations at green (skill Doc Update Table, full line-by-line
  read): `api_reference.md` (new §5.16 PlaylistCollection; §3 AppState
  rewritten to construction + wiring + the two stragglers; §3.6 / §5.15
  PlaylistContext conformance; §5.14 init and reaction methods; §8
  persistence-table ownership of `hp.activePlaylistIndex` and the legacy
  key; `saveVolume` note), `module_boundary.md` (new §4.11 PlaylistCollection
  placement and the playlist → playback closure direction; file list;
  `saveState` / `showFileInfo` mentions), `development_guide.md` (project
  tree, wiring example, deinit inventory eleven → twelve),
  `implementation_guide_swift.md` (file table, init example, terminate
  example), `workflow.md` (§4.2 example's `sut.undoManager` line),
  `architecture.md` (AppState file list → HC 5-area audit: Ports,
  Adapters, Services, Models, Errors read from the HarmoniaCore checkout
  at the pinned SHA).
