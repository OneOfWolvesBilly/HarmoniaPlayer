# Slice 19 Micro-slices Specification

## Purpose

Sixth stage of the AppState decomposition refactor program (design
authority: `appstate_refactor_plan.md`; pre-Pro milestone, no version
label). Extracts the fourth `@MainActor @Observable` feature store —
`PlaybackController` — behind the AppState strangler facade. It is the
largest extraction of the program: nine `@Published` properties leave
AppState (plan §3 rows 19–26 and the deleted `eqEnabled` mirror, row 31),
the transport / navigation / polling / ReplayGain / error-mapping /
sleep-wake code moves with them, the last four Combine sinks and both
publisher hand-offs in AppState init are replaced (plan §5), and ten
playback test files are re-homed on the store (plan §6.2, "largest test
move"). It introduces the transitional `PlaylistContext` protocol through
which the controller reads and writes playlist state until the
PlaylistCollection stage replaces it.

## Slice 19 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 19-A | Extract `PlaybackController` + `PlaylistContext` + Combine sink / publisher replacement + persistence split + `@Environment` view migration + test migration | — | ✅ |

### Goals

- Plan §3 rows 19–26 (`playbackState`, `currentTrack`, `currentTime`,
  `duration`, `playingPlaylistID`, `volume`, `repeatMode`, `isShuffled`),
  the non-published playback state (`pendingSeekTime`, `shuffleQueue`,
  `shuffleQueueIndex`, `lastPlayedTrackID`, `pollingTask`,
  `wasPlayingBeforeSleep`), and every transport, navigation, polling,
  ReplayGain, error-mapping, and sleep/wake method live in
  `PlaybackController`, which owns `playbackService` and the three
  playback persistence keys.
- `repeatMode` and `isShuffled` persist on change from the store itself;
  `volume` keeps today's terminate-time write through the store's
  `saveVolume()`. The `$repeatMode`, `$isShuffled`, `$currentTrack`, and
  `eqCoordinator.$isEnabled` sinks and both `AnyPublisher` hand-offs are
  removed from AppState init; `cancellables` and `import Combine` leave
  `AppState.swift`.
- The `eqEnabled` mirror is deleted; `PlayerView` reads `EQCoordinator`
  directly (plan §3 row 31).
- `currentTrack` changes reach `LyricsStore.updateResolution(for:)` and
  successful seeks reach `NowPlayingCoordinator.notifySeekCompleted(at:)`
  through closures wired by the composition root; `NowPlayingCoordinator`
  is constructed from the store's publishers and becomes a `let`.
- Dismissing an error alert clears the alert surface in `AlertCenter` and
  returns playback from `.error` to `.stopped` through a root-wired
  `onErrorCleared` closure; `AppState.clearLastError()` is deleted.
- `displayName(for:)` becomes `Track.displayName` (plan §3).
- `PlayerView`, `MiniPlayerView`, `ContentView`, and `LyricsPanel` observe
  `PlaybackController` via `@Environment(PlaybackController.self)`;
  `HarmoniaPlayerCommands` and `AppDelegate` reach it through
  `appState.playbackController`.
- Tests whose real SUT is the playback state move to a
  `PlaybackController*Tests` family that constructs the store directly
  (unit-test-core Rule 1 placement).
- `AppState+Playback.swift` and `AppState+Navigation.swift` are deleted.

### Out of Scope

- Migrating `PlaylistView` off the facade (it reads `playingPlaylistID`,
  `isShuffled`, `currentTrack`, `shuffleQueue`, `shuffleQueueIndex`, and
  calls `play(trackID:)`) → PlaylistCollection stage (plan §7.4), which
  owns that view's migration; the forwarders it needs survive this slice.
- `switchMiniPlayerPlaylist(to:)` — needs `undoManager`, so it stays on
  AppState (moved into `AppState+Playlist.swift`) and migrates with the
  PlaylistCollection stage (plan §7.4).
- Replacing `PlaylistContext` with `PlaylistCollection` and turning the
  controller's context into an init parameter → plan §7.4.
- Change-time persistence of `volume` (BL-17A-01) → v1.0.1 item (the
  development plan's Version Targets section), handled after §7.4; this
  slice keeps the terminate-time write (see Scope, persistence).
- Deleting the facade forwarders that survive this slice (`currentTrack`,
  `playbackState`, `currentTime`, `playingPlaylistID`, `repeatMode`,
  `isShuffled`, `shuffleQueue`, `shuffleQueueIndex`, `playbackService`,
  `stop()`, `play(trackID:)`) → the last slice with an internal reader of
  each (plan §6.0 step 7): PlaylistCollection stage, else the language-mode
  close-out (plan §7.5).
- The `@EnvironmentObject appState` the four migrated views keep for
  `languageBundle` (`L()`), `playlist`, `playlists`, `activePlaylistIndex`,
  `isProUnlocked`, and `switchMiniPlayerPlaylist` → each member's own stage
  / the close-out (Slice 16 Out of Scope, unchanged).
- `architecture.md` §6.2 DI-excerpt drift beyond the AppState file list →
  plan §7.5 final doc realignment. This slice changes only the lines that
  would otherwise name deleted files, which triggers the HC 5-area audit.
- The dead `PersistenceKey.sortKey` / `.sortAscending` entries in
  `AppState.swift` (sort state is persisted inside `Playlist`) → plan §7.4.
- Enabling any Pro feature — the commented-out Pro gating in the moved
  transport / navigation code moves verbatim (BL-16A-01 target unchanged).
- Any change to `EQCoordinator` / `NowPlayingCoordinator` → not in the
  program (plan §0).
- Deleting the Slice 12 baseline rows of files this slice does not touch
  → unchanged.

### Constraints

- Program constraints C1–C8 (plan §4) govern the observation mechanics;
  every scene hosting a migrated view must inject the store or the app
  crashes at first read (C3 — audit result: main window and Mini Player;
  the Equalizer, File Info, and Settings subtrees host no migrated view).
- Dependency direction stays as plan §2 declares:
  `PlaybackController ← playbackService, AlertCenter, SettingsStore,
  PlaylistContext` (+ `userDefaults` for its three keys). The store holds
  no reference to AppState (other than through the `PlaylistContext`
  existential), `LyricsStore`, `NowPlayingCoordinator`, or
  `EQCoordinator`; lateral and upward effects go through closures wired by
  the composition root.
- `AppState` is itself the `PlaylistContext` until plan §7.4, so the
  context cannot be an init argument of a store that AppState constructs
  while initialising; the controller holds it as an `@ObservationIgnored
  weak var` assigned by the root after AppState's stored properties are
  initialised, and context-dependent methods are no-ops while it is `nil`.
- Behaviour is preserved, including existing quirks: `playPreviousTrack()`
  at the first track seeks through the service directly, without Now
  Playing notification and without writing `lastErrorDetail`; `volume` is
  written to `UserDefaults` only at terminate; a `repeatMode` / `isShuffled`
  assignment persists even when the value is unchanged (today's
  `@Published` sink semantics, matched by `didSet`).
- One observable difference, accepted: `shuffleQueue` / `shuffleQueueIndex`
  become observable store properties (they have a view reader, the
  `PlaylistView` shuffle-queue popover), so that popover re-renders on
  queue mutation; today it does not (plain `var` on an `ObservableObject`).
- `@Observable` init-assignment semantics (Slice 16 execution amendment):
  the controller's restore assignments are made before any stored property
  without a default, so restore neither re-persists nor notifies.
- `import Combine` remains in `PlaybackController.swift` for the two
  `CurrentValueSubject`s that feed the unchanged `NowPlayingCoordinator`
  init signature.
- New store code builds warning-free under the Slice 12 baseline; this
  slice retires the baseline rows of the test files it deletes and
  re-measures every file it touches (plan §6.0 step 5).

### Dependencies

- Slice 13 (AlertCenter — a controller dependency; facade-forwarder
  template), Slice 14 (no-forwarder template; `LyricsStore` closure
  target), Slice 16 (SettingsStore — a controller dependency; `didSet`
  persistence and root-wired closure templates).
- Slice 11 (sleep/wake recovery — the code moves).
- Slice 12 (baseline must exist for the warning-clearing obligation).

---

## Slice 19-A: Extract PlaybackController ✅

### Goal

Move the whole playback surface out of AppState into a dedicated
`@MainActor @Observable` store that owns the playback service and its
three persistence keys, replace the remaining Combine plumbing in AppState
init with store-side `didSet` logic, root-wired closures, and store-owned
publishers, migrate the four views that read playback state, and keep
facade forwarders only for members that still have internal or
un-migrated-view readers.

### Scope (FROZEN as of spec commit)

**New store** `Shared/Models/PlaybackController.swift` (state, init,
transport, polling, ReplayGain, error mapping, sleep/wake, persistence)
and `Shared/Models/PlaybackController+Navigation.swift` (`playNextTrack`,
`playPreviousTrack`, `trackDidFinishPlaying`, `buildShuffleQueue`) — see
Public API shape. Deliberate choices frozen with it:

- **State.** Rows 19–26 plus `shuffleQueue` / `shuffleQueueIndex` are
  observable stored properties. `pendingSeekTime`, `lastPlayedTrackID`,
  `pollingTask`, and `wasPlayingBeforeSleep` are `@ObservationIgnored` (no
  view reads them); `pollingTask` stays `internal` for the polling tests,
  `wasPlayingBeforeSleep` stays `private(set)`.
- **Persistence split (plan §6.1).** The store owns `hp.volume`,
  `hp.repeatMode`, `hp.isShuffled` (a private `PersistenceKey` enum, the
  three entries leave AppState's). `init` restores all three from the
  injected `UserDefaults` with today's `restoreState()` logic (missing
  key → default; undecodable repeat data → `.off`). `repeatMode` and
  `isShuffled` persist in `didSet`. `volume` is written only by
  `saveVolume()`, which `AppState.saveState()` calls at terminate — the
  terminate-time behaviour BL-17A-01 later turns into a `didSet`.
- **Root-wired closures (`@ObservationIgnored`).**
  `onCurrentTrackChanged: ((Track?) -> Void)?` — called from
  `currentTrack`'s `didSet` on every assignment (today's sink fires on
  every `@Published` send, including same-value sends).
  `onSeekCompleted: ((TimeInterval) -> Void)?` — called where `seek(to:)`
  today calls `nowPlayingCoordinator.notifySeekCompleted(at:)`: after a
  successful service seek, never on failure.
- **Now Playing bridge (plan §5).** Two private
  `CurrentValueSubject`s (`Track?`, `PlaybackState`) are fed from the
  `didSet` of `currentTrack` / `playbackState`; `currentTrackPublisher`
  and `playbackStatePublisher` expose them as `AnyPublisher`s for the
  unchanged `NowPlayingCoordinator.init`.
- **`PlaylistContext`** (`Shared/Models/PlaylistContext.swift`): a
  `@MainActor` class-bound protocol with exactly the members the moved
  code uses — `playlists` (get set), `activePlaylistIndex` (get set),
  `selectedTrackIDs` (get). `extension AppState: PlaylistContext {}` has
  no body (AppState's members already match). The controller reads and
  writes `playlistContext?.…` where the moved code today reads AppState's
  own members (track resolution across playlists, switching the active
  playlist in `play(trackID:)`, the `isAccessible = false` write on an
  inaccessible track, the selection fallback in `play()`).
- **Dependencies written directly.** Error paths write
  `alertCenter.lastError` / `lastErrorDetail` / `failedTrackName` /
  `showFileNotFoundAlert` / `skippedInaccessibleNames` (today reached
  through facade forwarders); `applyReplayGainVolume` reads
  `settingsStore.replayGainMode`.
- **`recoverFromError()`** — new; moves `playbackState` from `.error` to
  `.stopped` and does nothing in any other state. It is the playback half
  of today's `AppState.clearLastError()`.
- **Methods moved verbatim** (signatures unchanged): `play()`, `pause()`,
  `stop()`, `seek(to:)`, `setVolume(_:)`, `play(trackID:)`,
  `cycleRepeatMode()`, `toggleShuffle()`,
  `buildShuffleQueue(startingWith:)`, private `startPolling()` /
  `stopPolling()`, `applyReplayGainVolume(for:requiresActivePlayback:)`,
  `mapToPlaybackError(_:)`, `makeErrorDetail(code:track:)`,
  `playNextTrack()`, `playPreviousTrack()`, `trackDidFinishPlaying()`,
  `handleSystemWillSleep()`, `handleSystemDidWake()`. The commented-out
  Pro gating moves with its surrounding code. `makeErrorDetail` and the
  navigation code call `track.displayName`.
- `playbackService`, `alertCenter`, `settingsStore`, `userDefaults` are
  `let` (`playbackService` internal — AppState's forwarder and the
  composition-root tests read it; the other three `private`).

**`Track` change** (`Shared/Models/Track.swift`): `var displayName:
String` in an extension — the body of today's `AppState.displayName(for:)`
unchanged (title + artist → `"title - artist"`; title only; artist only;
neither → filename of `originalPath` without extension).

**`AlertCenter` change** (`Shared/Models/AlertCenter.swift`):
`@ObservationIgnored var onErrorCleared: (() -> Void)?`, called at the end
of `clearLastError()` after the five surface fields are cleared. No other
change.

**AppState changes:**

- `let playbackController: PlaybackController` and
  `let nowPlayingCoordinator: NowPlayingCoordinator` (the implicitly
  unwrapped optional goes: the coordinator's seven action closures capture
  the controller, a local `let` at construction time, instead of
  `[weak self]`; its publishers and `currentTimeProvider` read the
  controller). Construction order: the controller is built after the
  services (Step 3) from `playbackService`, `alertCenter`, `settingsStore`,
  `userDefaults`; the coordinator is built from it immediately after;
  both are assigned before any other stored property is read.
- New wiring step (after every stored property is initialised, replacing
  Steps 12, 13, 13b, 14): `playbackController.playlistContext = self`;
  `settingsStore.onReplayGainModeChanged` → `Task { @MainActor in await
  playbackController.applyReplayGainVolume(requiresActivePlayback: true) }`
  (the Slice 16 closure retargeted from AppState to the controller);
  `playbackController.onCurrentTrackChanged` →
  `lyricsStore.updateResolution(for:)`;
  `playbackController.onSeekCompleted` → `[weak nowPlayingCoordinator]
  notifySeekCompleted(at:)`; `alertCenter.onErrorCleared` →
  `playbackController.recoverFromError()`. Every closure captures the
  stores it targets, not `self`.
- Deleted: the nine `@Published` properties, `pendingSeekTime`,
  `shuffleQueue`, `shuffleQueueIndex`, `lastPlayedTrackID`, `pollingTask`,
  `wasPlayingBeforeSleep`, `handleSystemWillSleep()`,
  `handleSystemDidWake()`, `clearLastError()`, `displayName(for:)`,
  `cancellables`, `import Combine`, the `PersistenceKey` entries `volume` /
  `repeatMode` / `isShuffled`, and the three keys' lines in `saveState()`
  / `restoreState()`. `saveState()` calls `playbackController.saveVolume()`
  before writing playlists. `let playbackService` becomes a get-only
  forwarder.
- `AppState+Playback.swift` and `AppState+Navigation.swift` are deleted;
  `switchMiniPlayerPlaylist(to:)` moves verbatim into
  `AppState+Playlist.swift` (it calls `stop()` and `play(trackID:)` through
  the method forwarders).
- **Facade verdicts, per member** (plan §6.0 step 7, by surviving
  internal / un-migrated-view readers after this slice):

  | Member | Surviving reader | Facade |
  | --- | --- | --- |
  | `currentTrack` | `AppState+Playlist` (`clearPlaylist`, `removeTrack`, `removeTracks`, `playNext`); `PlaylistView` row icon | get + set forwarder |
  | `playbackState` | `AppState+Playlist` (`removeTrack`, `removeTracks`) | get + set forwarder |
  | `currentTime` | `AppState+Playlist` (`removeTrack`, `removeTracks` reset) | get + set forwarder |
  | `playingPlaylistID` | `AppState+Playlist` (`deletePlaylist`); `PlaylistView` tab icon | get-only forwarder |
  | `repeatMode` | `AppState+Playlist` (`removeTrack`) | get-only forwarder |
  | `isShuffled` | `AppState+Playlist` (`load`, `removeTrack`, `removeTracks`, `playNext`); `PlaylistView` toolbar | get-only forwarder |
  | `shuffleQueue`, `shuffleQueueIndex` | `AppState+Playlist` (`load`, `removeTrack`, `removeTracks`, `playNext`, undo closures); `PlaylistView` popover | get + set forwarders |
  | `playbackService` | `AppState+Playlist` (`removeTrack`, `removeTracks` call `playbackService.stop()`); `AppStateTests` wiring rows | get-only forwarder |
  | `stop()` | `AppState+Playlist` (`deletePlaylist`, `switchMiniPlayerPlaylist`) | method forwarder |
  | `play(trackID:)` | `AppState+Playlist` (`removeTrack`, `switchMiniPlayerPlaylist`); `PlaylistView` ×2 | method forwarder |
  | `duration`, `volume` | none after the view migration | none — tests read `playbackController.…` |
  | `play()`, `pause()`, `seek(to:)`, `setVolume(_:)`, `playNextTrack()`, `playPreviousTrack()`, `trackDidFinishPlaying()`, `cycleRepeatMode()`, `toggleShuffle()`, `buildShuffleQueue(startingWith:)`, `applyReplayGainVolume` | none (Commands use the dotted path; `AppStateMultiPlaylistTests` / `IntegrationTests` retarget) | none |
  | `handleSystemWillSleep()`, `handleSystemDidWake()`, `wasPlayingBeforeSleep` | `AppDelegate` → dotted path | none |
  | `pendingSeekTime`, `lastPlayedTrackID`, `pollingTask` | none | none |
  | `clearLastError()` | `ContentView` → `alertCenter.clearLastError()` | none (deleted) |
  | `displayName(for:)` | none (→ `Track.displayName`) | none (deleted) |
  | `eqEnabled` | `PlayerView` → `EQCoordinator.isEnabled` | deleted (row 31) |

- `@Published` count drops by exactly 9 (13 → 4).

**View changes:**

| File | Change |
| --- | --- |
| `HarmoniaPlayerApp.swift` | main window scene adds `.environment(appState.playbackController)` and `.environmentObject(appState.eqCoordinator)` (replaces the `eqEnabled` mirror for `PlayerView`); Mini Player scene adds `.environment(appState.playbackController)`. C3 audit result: Equalizer (reads `appState.eqCoordinator` via the facade), File Info, and Settings host no migrated view and take no injection |
| `PlayerView.swift` | `@Environment(PlaybackController.self)` for every playback read and transport call; `@EnvironmentObject private var eqCoordinator: EQCoordinator` replaces `appState.eqEnabled`; `@EnvironmentObject appState` stays for `playlist.tracks.isEmpty` and `L()`; header rewritten |
| `MiniPlayerView.swift` | `@Environment(PlaybackController.self)` for every playback read and transport call; `.focusedSceneValue(\.playbackState, playbackController.playbackState)`; `@EnvironmentObject appState` stays for `switchMiniPlayerPlaylist`, `playlists`, `activePlaylistIndex`, `playlist`, `isProUnlocked`, `AppState.proOnlyFormats`, `L()`; header rewritten |
| `ContentView.swift` | `@Environment(PlaybackController.self)` for the lyrics-column `currentTrack` condition and `.focusedValue(\.playbackState, playbackController.playbackState)`; the five error-alert dismiss actions call `alertCenter.clearLastError()`; header updated |
| `LyricsPanel.swift` | `@Environment(PlaybackController.self)` for `currentTrack`; `@EnvironmentObject appState` stays for `L()`; header updated |
| `HarmoniaPlayerCommands.swift` | transport actions, `needsActiveTrack`, and the Repeat / Shuffle labels read `appState?.playbackController.…` (plan §6.0: Commands stay on the focused `appState` and dotted paths); `@FocusedValue(\.playbackState)` unchanged |
| `AppDelegate.swift` | sleep / wake observers call `appState?.playbackController.handleSystemWillSleep()` / `handleSystemDidWake()` |
| `PlaybackFocusedValues.swift` | header comment: the value is set from `playbackController.playbackState` |

`PlaylistView.swift`, `EQWindow.swift`, `EQView.swift`, `FileInfoView.swift`,
`SettingsView.swift`, `PaywallView.swift`: unchanged (forwarders keep
`PlaylistView` compiling and observable-correct through C1).

### Acceptance Criteria

1. AC1: `Shared/Models/PlaybackController.swift`,
   `Shared/Models/PlaybackController+Navigation.swift`, and
   `Shared/Models/PlaylistContext.swift` exist with the members of the
   Public API shape, including `nonisolated deinit {}`;
   `Shared/Models/AppState+Playback.swift` and
   `Shared/Models/AppState+Navigation.swift` do not exist.
2. AC2: `grep -c "@Published" AppState.swift` drops by exactly 9;
   `grep -n 'import Combine\|cancellables\|\$repeatMode\|\$isShuffled\|\$currentTrack\|\$isEnabled\|eqEnabled\|NowPlayingCoordinator!' AppState.swift`
   has no match; `volume`, `repeatMode`, `isShuffled`, `currentTrack`,
   `playbackState`, `currentTime`, `playingPlaylistID`, `shuffleQueue`,
   `shuffleQueueIndex`, `playbackService`, `stop`, `play(trackID` appear
   in `AppState.swift` only as forwarder declarations, wiring lines, and
   doc text.
3. AC3: `git diff --stat` for `NowPlayingCoordinator.swift`,
   `EQCoordinator.swift`, `PlaylistView.swift`, and
   `HarmoniaPlayer.xcodeproj/project.pbxproj` is empty at the code commit.
4. AC4: every TDD-matrix test passes in the file its Test File Decision
   names; the nine deleted test files no longer exist;
   `FakeInfrastructure/FakePlaylistContext.swift` exists.
5. AC5: full ⌘U suite green; final unit-test count = pre-slice count
   − 5 (deleted rows) + 17 (new rows); moved rows change file, never
   disappear. UITests unchanged (9). Pre-slice count re-measured at spec
   time on the 5e747d0 tree: 519 passed / 5 skipped / 0 failed → target
   531 passed / 5 skipped.
6. AC6: `slice_12_micro.md` baseline — the rows of
   `AppStatePlaybackControlTests.swift` (14),
   `AppStatePlaybackStateTests.swift` (14),
   `AppStatePlaybackTrackTests.swift` (14),
   `AppStateTrackSelectionTests.swift` (14), `AppStatePollingTests.swift`
   (14), `AppStateVolumeTests.swift` (14), and `RepeatModeTests.swift` (2)
   retire with their files (86; test-target total 452 → 366 if the
   re-measured rows hold); `AppStateReplayGainTests.swift` (20),
   `AppStatePersistenceTests.swift` (20), `AppStateTests.swift` (2),
   `HarmoniaPlayerApp.swift` (14), and `AppDelegate.swift` (2) are
   re-measured and updated if the counts change; every added file and
   every touched file without a row builds with zero warnings. Table
   update + Slice 19-A re-measurement note land with the close-out.
7. AC7 (manual, binary): each flow behaves as before —
   (a) play / pause / stop / next / previous / seek from the main window,
   the Mini Player, the Playback menu, and the media keys;
   (b) Repeat and Shuffle toggled, then the app force-quit from Activity
   Monitor → relaunch shows the toggled modes (change-time persistence);
   (c) volume changed, app quit with ⌘Q → relaunch restores it
   (terminate-time persistence);
   (d) Control Center Now Playing shows the track and state, follows
   track changes and pause / play, and its scrubber re-anchors after a
   seek made in the app;
   (e) playing track → sleep → wake resumes; paused → sleep → wake stays
   paused;
   (f) the lyrics panel follows a track change;
   (g) playing a missing file shows the error alert; OK dismisses it and
   the transport shows the stopped state;
   (h) toggling EQ in the Equalizer window updates the main window's EQ
   button state;
   (i) the Playback menu's Repeat and Shuffle labels update after the
   modes are changed from the main window toolbar;
   (j) main window, Mini Player, Equalizer, File Info, and Settings all
   open without a missing-injection crash — Mini Player first;
   (k) with Shuffle on, the `PlaylistView` shuffle-queue popover lists the
   queue.

### Out of Scope

- See slice-level Out of Scope.

### Deferred Backlog

1. BL-19A-01 — `PlaylistContext` is replaced by `PlaylistCollection`
   passed to `PlaybackController.init`, and the `weak var` + `nil` guards
   go. Target: PlaylistCollection stage (plan §7.4).
2. BL-19A-02 — If AC7(i) fails (Commands body not re-evaluated by an
   `@Observable` property read through the focused `appState`), the
   Repeat / Shuffle labels move to scalar `FocusedValues` keys like
   `playbackState`. Target: spec amendment commit of this slice before
   any code change (template discipline rule 1); otherwise closed at
   close-out as not needed.

### Files

- HarmoniaPlayer Application Layer:
  - add `Shared/Models/PlaybackController.swift`,
    `Shared/Models/PlaybackController+Navigation.swift`,
    `Shared/Models/PlaylistContext.swift`
  - modify `Shared/Models/AppState.swift`,
    `Shared/Models/AppState+Playlist.swift` (receives
    `switchMiniPlayerPlaylist(to:)`; its playback reads stay on the
    forwarders), `Shared/Models/AlertCenter.swift` (`onErrorCleared`),
    `Shared/Models/Track.swift` (`displayName`)
  - delete `Shared/Models/AppState+Playback.swift`,
    `Shared/Models/AppState+Navigation.swift`
  - `Shared/Models/AppState+M3U8.swift`: no change
- UI: modify `HarmoniaPlayerApp.swift`, `AppDelegate.swift`,
  `HarmoniaPlayerCommands.swift`, `ContentView.swift`, `PlayerView.swift`,
  `MiniPlayerView.swift`, `LyricsPanel.swift`,
  `PlaybackFocusedValues.swift` (header comment)
- Tests:
  - add `FakeInfrastructure/FakePlaylistContext.swift`
  - add `SharedTests/PlaybackControllerTransportTests.swift`,
    `PlaybackControllerTrackTests.swift`,
    `PlaybackControllerNavigationTests.swift`,
    `PlaybackControllerPollingTests.swift`,
    `PlaybackControllerReplayGainTests.swift`,
    `PlaybackControllerErrorMappingTests.swift`,
    `PlaybackControllerPersistenceTests.swift`
  - delete `SharedTests/AppStatePlaybackControlTests.swift`,
    `AppStatePlaybackStateTests.swift`, `AppStatePlaybackTrackTests.swift`,
    `AppStateTrackSelectionTests.swift`, `AppStatePollingTests.swift`,
    `AppStateShuffleTests.swift`, `AppStateNavigationTests.swift`,
    `AppStateVolumeTests.swift`, `RepeatModeTests.swift` (rows move)
  - modify `AppStateReplayGainTests.swift` (7 rows leave; 3 cross-component
    rows stay, retargeted), `AppStateErrorHandlingTests.swift` (3 rows
    leave, 1 deleted, 1 retargeted), `AppStatePersistenceTests.swift`
    (5 rows leave; one assertion dropped), `AppStateTests.swift` (2 rows
    deleted, 2 added, `import Combine` removed), `TrackTests.swift`
    (4 added), `AlertCenterTests.swift` (1 added), `IntegrationTests.swift`
    and `AppStateMultiPlaylistTests.swift` (dotted-path retarget only)
  - the test moves are made in the red phase and land with the single
    code commit
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change needed
  (`PBXFileSystemSynchronizedRootGroup`)
- Docs at green: `api_reference.md`, `module_boundary.md`,
  `development_guide.md`, `implementation_guide_swift.md`,
  `architecture.md` (AppState file list; HC 5-area audit)
- Docs at close-out: `slice_12_micro.md` (retired rows + re-measurement
  note), this spec (status ticks, execution amendments),
  `HarmoniaPlayer_development_plan.md` (slice table tick)

### TDD matrix

The `PlaybackController*Tests` files build the SUT directly:

```swift
let fake = FakePlaybackService()
let context = FakePlaylistContext()          // one empty playlist, index 0
let defaults = UserDefaults(suiteName: "hp-test-\(UUID().uuidString)")!
let sut = PlaybackController(playbackService: fake,
                             alertCenter: AlertCenter(),
                             settingsStore: SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults),
                             userDefaults: defaults)
sut.playlistContext = context
```

Tracks are seeded as `context.playlists[0].tracks = [Track(url: …)]`
instead of `load(urls:)`; a relaunch is simulated by building a second
controller on the same suite. All seven files use the `async tearDown +
makeSUT` fixture shape (the Slice 12 zero-warning shape). Moved rows keep
their names unless noted; their Given / When / Then are unchanged apart
from the fixture, so the table states them briefly.

**Moved rows (93)**

| # | Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- | --- |
| 1 | `testPlay_CallsPlaybackServicePlay` | track selected | `play()` | `playCallCount == 1` | Move from `AppStatePlaybackControlTests.swift` → New `PlaybackControllerTransportTests.swift` |
| 2 | `testPlay_SetsPlayingState` | track selected | `play()` | `.playing` | same move |
| 3 | `testPlay_OnError_SetsLastError` | fake `play` throws | `play()` | `alertCenter.lastError != nil` | same move |
| 4 | `testPlay_OnError_SetsErrorState` | fake `play` throws | `play()` | `.error` | same move |
| 5 | `testPause_CallsPlaybackServicePause` | playing | `pause()` | `pauseCallCount == 1` | same move |
| 6 | `testPause_SetsPausedState` | playing | `pause()` | `.paused` | same move |
| 7 | `testStop_CallsPlaybackServiceStop` | playing | `stop()` | `stopCallCount == 1` | same move |
| 8 | `testStop_SetsStoppedState` | playing | `stop()` | `.stopped` | same move |
| 9 | `testStop_ResetsCurrentTimeToZero` | time advanced | `stop()` | `currentTime == 0` | same move |
| 10 | `testStop_ClearsCurrentTrack` | playing | `stop()` | `currentTrack == nil` | same move |
| 11 | `testStop_ClearsPlayingPlaylistID` | playing | `stop()` | `playingPlaylistID == nil` | same move |
| 12 | `testSeek_CallsPlaybackServiceSeek` | playing | `seek(to:)` | `seekCallCount == 1` | same move |
| 13 | `testSeek_PassesCorrectSeconds` | playing | `seek(to: 42)` | `seekedToSeconds == [42]` | same move |
| 14 | `testSeek_Success_UpdatesCurrentTime` | playing | `seek(to:)` | `currentTime` updated | same move |
| 15 | `testSeek_Error_SetsLastError` | fake `seek` throws | `seek(to:)` | `alertCenter.lastError != nil` | same move |
| 16 | `testSeek_Error_DoesNotChangePlaybackState` | fake `seek` throws | `seek(to:)` | state unchanged | same move |
| 17 | `testPlay_NoCurrentTrack_WithSelection_PlaysSelectedTrack` | `context.selectedTrackIDs` = one | `play()` | that track plays | same move |
| 18 | `testPlay_NoCurrentTrack_WithMultipleSelection_PlaysFirstInPlaylistOrder` | selection of two | `play()` | first in playlist order | same move |
| 19 | `testPlay_NoCurrentTrack_NoSelection_PlaysFirstTrack` | tracks, no selection | `play()` | first track | same move |
| 20 | `testPlay_NoCurrentTrack_EmptyPlaylist_IsNoop` | empty playlist | `play()` | no service call | same move |
| 21 | `testInitialPlaybackState_IsIdle` (was `testAppState_InitialPlaybackState_IsIdle`) | init | — | `.idle` | Move from `AppStatePlaybackStateTests.swift` → `PlaybackControllerTransportTests.swift` |
| 22 | `testInitialCurrentTime_IsZero` (was `testAppState_…`) | init | — | `0` | same move |
| 23 | `testInitialDuration_IsZero` (was `testAppState_…`) | init | — | `0` | same move |
| 24 | `testWillSleepRecordsPlayingState` | playing | `handleSystemWillSleep()` | `wasPlayingBeforeSleep == true` | same move |
| 25 | `testWillSleepRecordsFalseWhenPaused` | paused | `handleSystemWillSleep()` | `false` | same move |
| 26 | `testDidWakeResumesWhenWasPlaying` | slept while playing | `handleSystemDidWake()` | `play` called | same move |
| 27 | `testDidWakeDoesNotResumeWhenWasPaused` | slept while paused | `handleSystemDidWake()` | no `play` call | same move |
| 28 | `testDidWakeClearsFlag` | slept while playing | `handleSystemDidWake()` | flag `false` | same move |
| 29 | `testSetVolume_ForwardsToService` | — | `setVolume(0.5)` | fake receives `0.5` | Move from `AppStateVolumeTests.swift` → `PlaybackControllerTransportTests.swift` |
| 30 | `testSetVolume_Clamps_AboveOne` | — | `setVolume(1.5)` | `volume == 1` | same move |
| 31 | `testSetVolume_Clamps_BelowZero` | — | `setVolume(-0.5)` | `volume == 0` | same move |
| 32 | `testPlayTrack_SetsCurrentTrack` | tracks seeded | `play(trackID:)` | `currentTrack` set | Move from `AppStatePlaybackTrackTests.swift` → New `PlaybackControllerTrackTests.swift` |
| 33 | `testPlayTrack_CallsLoad` | tracks seeded | `play(trackID:)` | `loadCallCount == 1` | same move |
| 34 | `testPlayTrack_LoadsCorrectURL` | tracks seeded | `play(trackID:)` | loaded URL matches | same move |
| 35 | `testPlayTrack_CallsPlay` | tracks seeded | `play(trackID:)` | `playCallCount == 1` | same move |
| 36 | `testPlayTrack_SetsPlayingState` | tracks seeded | `play(trackID:)` | `.playing` | same move |
| 37 | `testPlayTrack_UpdatesDuration` | fake duration stub | `play(trackID:)` | `duration` updated | same move |
| 38 | `testPlayTrack_LoadError_SetsLastError` | fake `load` throws | `play(trackID:)` | `alertCenter.lastError != nil` | same move |
| 39 | `testPlayTrack_LoadError_SetsErrorState` | fake `load` throws | `play(trackID:)` | `.error` | same move |
| 40 | `testPlayTrack_LoadError_DoesNotCallPlay` | fake `load` throws | `play(trackID:)` | `playCallCount == 0` | same move |
| 41 | `testPlayTrack_InvalidID_NoServiceCalls` | tracks seeded | `play(trackID: UUID())` | no service call | same move |
| 42 | `testPlayTrack_InvalidID_NilsCurrentTrack` | playing | `play(trackID: UUID())` | `currentTrack == nil` | same move |
| 43 | `testPlay_SwitchTrack_UpdatesCurrentTrack` | track 1 playing | `play(trackID: track2)` | `currentTrack == track2` | Move from `AppStateTrackSelectionTests.swift` → `PlaybackControllerTrackTests.swift` |
| 44 | `testPlay_EmptyPlaylist_ClearsCurrentTrack` | playing, playlist emptied | `play(trackID:)` | `currentTrack == nil` | same move |
| 45 | `testPlayNext_EmptyPlaylist_IsNoOp` | empty | `playNextTrack()` | no `load` | Move from `AppStateNavigationTests.swift` → New `PlaybackControllerNavigationTests.swift` |
| 46 | `testPlayNext_NoCurrentTrack_PlaysFirst` | 2 tracks | `playNextTrack()` | track 1 | same move |
| 47 | `testPlayNext_HasNextTrack_PlaysNext` | track 1 playing | `playNextTrack()` | track 2 | same move |
| 48 | `testPlayNext_LastTrack_RepeatOff_WrapsToFirst` | track 2 playing | `playNextTrack()` | track 1 | same move |
| 49 | `testPlayNext_LastTrack_RepeatAll_PlaysFirst` | `.all`, track 2 | `playNextTrack()` | track 1 | same move |
| 50 | `testPlayNext_RepeatOne_AdvancesToNextTrack` | `.one`, track 1 | `playNextTrack()` | track 2 | same move |
| 51 | `testPlayNext_SingleTrack_RepeatOff_ReplaysTrack` | 1 track | `playNextTrack()` | same track | same move |
| 52 | `testPlayNext_SingleTrack_RepeatAll_ReplaysTrack` | 1 track, `.all` | `playNextTrack()` | `loadCallCount == 2` | same move |
| 53 | `testPlayPrevious_EmptyPlaylist_IsNoOp` | empty | `playPreviousTrack()` | no `load` | same move |
| 54 | `testPlayPrevious_NoCurrentTrack_PlaysFirst` | 2 tracks | `playPreviousTrack()` | track 1 | same move |
| 55 | `testPlayPrevious_HasPreviousTrack_PlaysPrevious` | track 2 playing | `playPreviousTrack()` | track 1 | same move |
| 56 | `testPlayPrevious_FirstTrack_SeeksToZero` | track 1 playing | `playPreviousTrack()` | `seekedToSeconds == [0]` | same move |
| 57 | `testPlayPrevious_FirstTrack_RestartsPlayback` | track 1 playing | `playPreviousTrack()` | `.playing` | same move |
| 58 | `testTrackDidFinish_NoCurrentTrack_IsNoOp` | no current | `trackDidFinishPlaying()` | no `load` | same move |
| 59 | `testTrackDidFinish_RepeatOff_HasNext_PlaysNext` | track 1 | `trackDidFinishPlaying()` | track 2 | same move |
| 60 | `testTrackDidFinish_RepeatOff_LastTrack_Stops` | track 2 | `trackDidFinishPlaying()` | `.stopped` | same move |
| 61 | `testTrackDidFinish_RepeatAll_LastTrack_PlaysFirst` | `.all`, track 2 | `trackDidFinishPlaying()` | track 1 | same move |
| 62 | `testTrackDidFinish_RepeatOne_ReplaysCurrentTrack` | `.one` | `trackDidFinishPlaying()` | same track, `loadCallCount == 2` | same move |
| 63 | `testTrackDidFinish_PlayingDiffersFromActive_RepeatOff_StopsAndClears` | playing PL2, browsing PL1 (`context.activePlaylistIndex = 0`) | `trackDidFinishPlaying()` | `.stopped`, `currentTrack == nil` | same move |
| 64 | `testTrackDidFinish_PlayingDiffersFromActive_RepeatOne_Replays` | as 63, `.one` | `trackDidFinishPlaying()` | same track replays | same move |
| 65 | `testIsShuffled_DefaultIsFalse` | init | — | `.off` | Move from `AppStateShuffleTests.swift` → `PlaybackControllerNavigationTests.swift` |
| 66 | `testToggleShuffle_OffToOn` | `.off` | `toggleShuffle()` | `.on` | same move |
| 67 | `testToggleShuffle_OnToOff` | `.on` | `toggleShuffle()` | `.off` | same move |
| 68 | `testPlayNext_Shuffled_DoesNotRepeatCurrentTrack` | shuffled, playing | `playNextTrack()` | different track | same move |
| 69 | `testPlayNext_Shuffled_PlaysRandomTrack` | shuffled | `playNextTrack()` | a playlist track plays | same move |
| 70 | `testRepeatMode_DefaultIsOff` | init | — | `.off` | Move from `RepeatModeTests.swift` → `PlaybackControllerNavigationTests.swift` |
| 71 | `testCycleRepeatMode_OffToAll` | `.off` | `cycleRepeatMode()` | `.all` | same move |
| 72 | `testCycleRepeatMode_AllToOne` | `.all` | `cycleRepeatMode()` | `.one` | same move |
| 73 | `testCycleRepeatMode_OneToOff` | `.one` | `cycleRepeatMode()` | `.off` | same move |
| 74 | `testStopPolling_CancelsTask` | polling | `stop()` | `pollingTask == nil` | Move from `AppStatePollingTests.swift` → New `PlaybackControllerPollingTests.swift` |
| 75 | `testPolling_StopsOnCancellation` | polling | cancel | loop ends | same move |
| 76 | `testPollingReflectsServicePaused` | fake state `.paused` | poll tick | `.paused` | same move |
| 77 | `testPollingReflectsServiceError` | fake state error | poll tick | `.error` | same move |
| 78 | `testPollingStillDetectsStopped` | fake state `.stopped` | poll tick | `.stopped` | same move |
| 79 | `testReplayGain_Off_DoesNotAdjustVolume` | mode `.off` | play tagged track | plain volume | Move from `AppStateReplayGainTests.swift` → New `PlaybackControllerReplayGainTests.swift` |
| 80 | `testReplayGain_TrackMode_UsesTrackGain` | mode `.track` | play | track gain applied | same move |
| 81 | `testReplayGain_TrackMode_FallbackToAlbum_WhenTrackGainNil` | `.track`, no track gain | play | album gain | same move |
| 82 | `testReplayGain_AlbumMode_UsesAlbumGain` | `.album` | play | album gain | same move |
| 83 | `testReplayGain_AlbumMode_FallbackToTrack_WhenAlbumGainNil` | `.album`, no album gain | play | track gain | same move |
| 84 | `testReplayGain_BothTagsNil_UsesPlainVolume` | no tags | play | plain volume | same move |
| 85 | `testReplayGain_LargePositiveGain_ClampsTo1` | +20 dB | play | `≤ 1.0` | same move |
| 86 | `testLastErrorDetail_PlayTrackDecodeFailure_ContainsCodeAndPath` | fake `load` throws decode | `play(trackID:)` | detail has code + path | Move from `AppStateErrorHandlingTests.swift` → New `PlaybackControllerErrorMappingTests.swift` |
| 87 | `testLastErrorDetail_InaccessibleTrack_ContainsCodeAndPath` | inaccessible track | `play(trackID:)` | detail has code + path; `context.playlists[0]` track `isAccessible == false` | same move |
| 88 | `testLastErrorDetail_SeekFailure_ContainsCodeAndNoTrack` | fake `seek` throws | `seek(to:)` | detail has code, no track | same move |
| 89 | `testVolume_SurvivesRelaunch_AfterSaveVolume` (was `testSaveAndRestore_Volume_Survives`) | `setVolume(0.3)`, `saveVolume()` | second controller | `volume == 0.3` | Move from `AppStatePersistenceTests.swift` → New `PlaybackControllerPersistenceTests.swift` |
| 90 | `testRepeatMode_SurvivesRelaunch` (was `testSaveAndRestore_RepeatMode_Survives`) | `cycleRepeatMode()` | second controller | `.all` | same move (no save call) |
| 91 | `testShuffleMode_SurvivesRelaunch` (was `testSaveAndRestore_ShuffleMode_Survives`) | `toggleShuffle()` | second controller | `.on` | same move (no save call) |
| 92 | `testRepeatMode_PersistsOnChange` (was `testRepeatMode_AutoSaves_ViaCombineSink`) | fresh | `cycleRepeatMode()` | suite's `hp.repeatMode` written, no save call | same move |
| 93 | `testShuffleMode_PersistsOnChange` (was `testShuffleMode_AutoSaves_ViaCombineSink`) | fresh | `toggleShuffle()` | suite's `hp.isShuffled == true`, no save call | same move |

**New rows (17)**

| # | Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- | --- |
| 94 | `testRecoverFromError_ErrorState_BecomesStopped` | fake `play` throws → `.error` | `recoverFromError()` | `.stopped` | New `PlaybackControllerTransportTests.swift` |
| 95 | `testRecoverFromError_WhenNotError_LeavesStateUnchanged` | `.paused` | `recoverFromError()` | `.paused` | New `PlaybackControllerTransportTests.swift` |
| 96 | `testSeek_Success_CallsOnSeekCompleted` | recorder on `onSeekCompleted` | `seek(to: 42)` | called once with `42` | New `PlaybackControllerTransportTests.swift` |
| 97 | `testSeek_Failure_DoesNotCallOnSeekCompleted` | fake `seek` throws, recorder | `seek(to:)` | not called | New `PlaybackControllerTransportTests.swift` |
| 98 | `testCurrentTrackChange_CallsOnCurrentTrackChanged` | recorder | `play(trackID:)` | called with that track | New `PlaybackControllerTransportTests.swift` |
| 99 | `testPublishers_EmitCurrentTrackAndPlaybackState` | sinks on both publishers | `play(trackID:)` then `pause()` | track emitted; `.playing`, `.paused` emitted | New `PlaybackControllerTransportTests.swift` |
| 100 | `testPlayTrack_InOtherPlaylist_SwitchesActivePlaylistIndex` | two context playlists, index 0 | `play(trackID:)` of a PL2 track | `context.activePlaylistIndex == 1`, `playingPlaylistID == PL2.id` | New `PlaybackControllerTrackTests.swift` |
| 101 | `testInit_NoVolumeKey_VolumeIsOne` | empty suite | init | `volume == 1.0` | New `PlaybackControllerPersistenceTests.swift` |
| 102 | `testInit_RestoresPersistedPlaybackSettings` | suite seeded: volume `0.25`, repeat `.one`, shuffle `true` | init | the three properties read back | New `PlaybackControllerPersistenceTests.swift` |
| 103 | `testVolume_NotPersistedBeforeSaveVolume` | fresh | `setVolume(0.3)` | suite has no `hp.volume`; after `saveVolume()` it is `0.3` | New `PlaybackControllerPersistenceTests.swift` |
| 104 | `testDisplayName_TitleAndArtist` | title + artist | `displayName` | `"title - artist"` | Extend `TrackTests.swift` |
| 105 | `testDisplayName_TitleOnly` | title, empty artist | `displayName` | title | Extend `TrackTests.swift` |
| 106 | `testDisplayName_ArtistOnly` | empty title, artist | `displayName` | artist | Extend `TrackTests.swift` |
| 107 | `testDisplayName_NeitherUsesFilename` | both empty, `originalPath` `/x/song.mp3` | `displayName` | `"song"` | Extend `TrackTests.swift` |
| 108 | `testClearLastError_CallsOnErrorCleared` | recorder on `onErrorCleared` | `clearLastError()` | called once, after the surface is cleared | Extend `AlertCenterTests.swift` |
| 109 | `testInit_WiresCurrentTrackChangeToLyricsStore` | `FakeLyricsService` provider | `appState.playbackController.play(trackID:)` | `lyricsStore.lyricsResolution` updated for that track | Extend `AppStateTests.swift` |
| 110 | `testInit_PlaybackControllerRestoresFromInjectedDefaults` | suite pre-seeded `hp.repeatMode` = `.all` | `AppState(…, userDefaults: suite)` | `appState.playbackController.repeatMode == .all` | Extend `AppStateTests.swift` |

**Retargeted at green (no row change)**

| Test | Change |
| --- | --- |
| `AppStateErrorHandlingTests.testClearLastError_ErrorState_BecomesStopped` | calls `sut.alertCenter.clearLastError()`, asserts `sut.playbackController.playbackState == .stopped` — end-to-end guard of the `onErrorCleared` root wiring |
| `AppStateReplayGainTests.testReplayGain_ModeSwitch_DuringPlayback_AppliesImmediately`, `…_WhenStopped_DoesNotCallSetVolume` | set `sut.settingsStore.replayGainMode`, read the fake — end-to-end guards of the `onReplayGainModeChanged` root wiring (Slice 16 row 25 precedent) |
| `AppStateReplayGainTests.testEQReplayGainInteraction_AdditiveCombination` | transport calls through `sut.playbackController` — cross-component (EQCoordinator × controller) |
| `AppStatePersistenceTests.testRestoreState_WhenNoData_UsesDefaults` | the `volume` assertion is dropped (row 101 owns it) |
| `AppStateTests.testInit_*WiresDependenciesCorrectly`, `testInit_DoesNotExecuteBehavior` | `playbackService` reads stay on the forwarder |
| `AppStateMultiPlaylistTests.testSwitchPlaylist_DoesNotStopPlayback`, `IntegrationTests` (8 transport rows) | `play()`, `pause()`, `seek(to:)`, `playbackState`, `currentTrack`, `currentTime` reads without a forwarder go through `sut.playbackController` |

**Deleted rows (5)**

| Test | Reason |
| --- | --- |
| `AppStateTrackSelectionTests.testPlay_ValidID_SetsCurrentTrack` | unit-test-core Smell 4 — same path and observation as row 32 |
| `AppStateTrackSelectionTests.testPlay_InvalidID_ClearsCurrentTrack` | Smell 4 — same as row 42 |
| `AppStateErrorHandlingTests.testLastErrorDetail_ClearedOnClearLastError` | after the move its only observation is `AlertCenter.clearLastError()` clearing `lastErrorDetail`, already pinned by `AlertCenterTests.testClearLastError_ClearsErrorSurface` (Smell 4) |
| `AppStateTests.testEQEnabled_InitialValue_MatchesCoordinator` | the mirror is deleted (plan §3 row 31) |
| `AppStateTests.testEQEnabled_ReflectsCoordinatorToggle` | same |

Count: 93 moved, 17 new, 5 deleted → net +12 (AC5).

Red phase — the skeleton holds every property at its default, has empty
method bodies (`recoverFromError()`, `saveVolume()` included), restores
nothing, runs no `didSet` logic, calls no closure, and creates the two
subjects (so the publishers emit only their initial value);
`Track.displayName` returns `""`; `AlertCenter.onErrorCleared` is
declared but not called; AppState constructs the controller and assigns
its context but keeps its own playback members, sinks, and coordinator
wiring until green (Slice 16 precedent). Of the 111 rows that run
against the skeleton (rows 1–110 plus the retargeted
`testClearLastError_ErrorState_BecomesStopped`):

- Green from the start (6, default-value guards): rows 21, 22, 23, 65,
  70, 101.
- Negative guards, vacuously green against the honest empty skeleton
  (16): rows 16, 20, 25, 27, 28, 40, 41, 42, 44, 45, 53, 58, 74, 79, 95,
  103 (13-A amendment precedent — forcing them red would need a
  deliberately-wrong skeleton body).
- Expected red (89): every other row.

Execution amendments (recorded at close-out):

- **`import Combine` stays in `AppState.swift`.** The Goals, the Scope
  "Deleted" list, and AC2 say the import leaves the file. It cannot:
  `AppState` is still an `ObservableObject` with four `@Published`
  properties (the playlist rows), and both are Combine declarations — a
  build without the import fails with "missing import of defining module
  'Combine'". `cancellables` and every sink did leave. The import goes
  when the playlist rows leave AppState (plan §7.4). AC2's
  `import Combine` clause is therefore not met and not meetable in this
  slice.
- **AC2 `@Published` count.** The thirteen `@Published` declarations drop
  to four (nine removed), as specified. The literal
  `grep -c "@Published" AppState.swift` drops by ten (15 → 5), because
  one of the two doc-comment lines that mention the attribute — the old
  `nowPlayingCoordinator` comment — was rewritten with the property.
- **`alertCenter` is module-internal on the controller**, not `private`
  as the Scope states: the navigation code lives in
  `PlaybackController+Navigation.swift`, and a `private` member is not
  visible to an extension in another file. `settingsStore` and
  `userDefaults` stay `private`.
- **Red set.** Observed 93 red of the 111 rows run against the skeleton
  (prediction: 89). Eight rows predicted vacuously green were red because
  their fixture asserts a precondition the skeleton cannot satisfy or
  unwraps a value it never sets (rows 16, 28, 42, 44, 74, 79, 95, 103);
  four rows predicted red were vacuously green (rows 9, 67, 73, 97). The
  six default-value guards matched.
- **Green.** 531 passed / 5 skipped / 0 failed — exactly pre-slice
  519 − 5 + 17 (AC5).
- **Baseline merge.** `main` gained two commits while the slice was open
  (the HarmoniaCore-Swift repin to `1ccbbbfa`, whose tree is identical to
  the previous pin, and neutral example paths) and was merged into the
  branch before the red phase; the suite re-measured at 519 / 5 / 0 on the
  merged tree, so the AC5 baseline is unchanged. The HC 5-area audit read
  the pinned revision's tree directly: Ports (8), Adapters (9), Services
  (`PlaybackService`, `DefaultPlaybackService`), Models (5), and
  `CoreError` (6 cases) match `architecture.md` §2 and §5 — no HC-side
  change to surface.
- **Warning re-measurement** used clean builds of the pre-slice and
  post-slice trees with an identical counting method: only the seven
  deleted files' rows disappear; every other file measures the same
  before and after (AC6).
- `AppState.replayGainMode` (the Slice 16 get + set forwarder) has no
  internal reader left once `applyReplayGainVolume` reads the store; it
  is not in this slice's Scope and stays for the facade clean-up
  (plan §7.5).
- BL-19A-02 stays open until the manual check AC7(i) is run.

### Public API shape

```swift
@MainActor
protocol PlaylistContext: AnyObject {
    var playlists: [Playlist] { get set }
    var activePlaylistIndex: Int { get set }
    var selectedTrackIDs: Set<Track.ID> { get }
}

extension AppState: PlaylistContext {}

@MainActor @Observable
final class PlaybackController {

    // Transport state
    var currentTrack: Track?                      // didSet → subject + onCurrentTrackChanged
    var playbackState: PlaybackState = .idle      // didSet → subject
    var playingPlaylistID: Playlist.ID?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    // Persisted — hp.volume via saveVolume(); hp.repeatMode / hp.isShuffled in didSet
    var volume: Float = 1.0
    var repeatMode: RepeatMode = .off
    var isShuffled: ShuffleMode = .off

    // Shuffle queue (read by the PlaylistView popover)
    var shuffleQueue: [Track.ID] = []
    var shuffleQueueIndex: Int = 0

    // Not observed
    @ObservationIgnored var pendingSeekTime: TimeInterval = 0
    @ObservationIgnored var lastPlayedTrackID: Track.ID?
    @ObservationIgnored var pollingTask: Task<Void, Never>?
    @ObservationIgnored private(set) var wasPlayingBeforeSleep = false

    // Dependencies
    let playbackService: PlaybackService
    @ObservationIgnored weak var playlistContext: (any PlaylistContext)?   // assigned by the root

    // Root-wired notifications
    @ObservationIgnored var onCurrentTrackChanged: ((Track?) -> Void)?
    @ObservationIgnored var onSeekCompleted: ((TimeInterval) -> Void)?

    // Now Playing bridge
    var currentTrackPublisher: AnyPublisher<Track?, Never> { get }
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }

    init(playbackService: PlaybackService,
         alertCenter: AlertCenter,
         settingsStore: SettingsStore,
         userDefaults: UserDefaults)

    // Transport
    func play() async
    func pause() async
    func stop() async
    func seek(to seconds: TimeInterval) async
    func setVolume(_ volume: Float) async
    func play(trackID: Track.ID) async
    func cycleRepeatMode()
    func toggleShuffle()
    func buildShuffleQueue(startingWith startID: Track.ID? = nil)

    // Navigation (PlaybackController+Navigation.swift)
    func playNextTrack() async
    func playPreviousTrack() async
    func trackDidFinishPlaying() async

    // ReplayGain / errors
    func applyReplayGainVolume(for explicitTrack: Track? = nil, requiresActivePlayback: Bool = false) async
    func mapToPlaybackError(_ error: Error) -> PlaybackError
    func makeErrorDetail(code: PlaybackError, track: Track?) -> String
    /// `.error` → `.stopped`; no-op in any other state.
    func recoverFromError()

    // Sleep / wake
    func handleSystemWillSleep()
    func handleSystemDidWake() async

    // Persistence
    /// Writes `hp.volume`; called by the composition root at terminate.
    func saveVolume()

    nonisolated deinit {}
}

extension Track {
    /// "title - artist", title, artist, or the file name of `originalPath`.
    var displayName: String { get }
}

// AlertCenter addition
@ObservationIgnored var onErrorCleared: (() -> Void)?   // called at the end of clearLastError()
```

### Implementation notes

- Red-phase skeleton precedent: 9-L / 13-A / 14-A / 16-A.
- `weak var playlistContext` is the transitional form (Constraints): a
  store that AppState constructs during its own `init` cannot take `self`
  as an argument. Every context-dependent method starts with
  `guard let context = playlistContext else { return }`; BL-19A-01
  removes the guards.
- Ownership stays acyclic: AppState → controller (strong) → context
  (weak); AppState → coordinator (strong) → controller (strong, via the
  action closures and publishers); controller → coordinator only through
  `onSeekCompleted`, which captures the coordinator weakly.
- `@Observable` `didSet` runs for assignments made after `self` is fully
  initialised (Slice 16 amendment); the controller's init restores the
  three keys first, so restore neither re-persists nor notifies. Rows 92,
  93, 102, 103 pin both sides.
- The ReplayGain closure keeps today's asynchronous hop (`Task {
  @MainActor in … }`), so the two retargeted mode-switch rows keep their
  timing assumptions.
- C1 keeps `PlaylistView` correct: its body reads reach the controller
  through the computed forwarders, so Observation registers the store
  property even for a view still on `@EnvironmentObject`.
- Whether `HarmoniaPlayerCommands` re-evaluates its body when an
  `@Observable` property read through the focused `appState` changes has
  no authoritative source; AC7(i) verifies it manually and BL-19A-02
  names the fallback.
- Token discipline: the moved code gets clean doc comments (the
  `seek(to:)` and `startPolling` comments carry stale slice tokens
  today); rewritten view headers drop stale narrative; untouched regions
  keep their tokens for the slice that moves them.
  `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` on added lines before the
  commit.
- Doc obligations at green (skill Doc Update Table, full line-by-line
  read): `api_reference.md` (new types; AppState property / method / init
  changes; `nowPlayingCoordinator` no longer an IUO; persistence-key table
  ownership; `Track.displayName`; `AlertCenter.onErrorCleared`),
  `module_boundary.md` (new state-owning type; file list),
  `development_guide.md` (project structure, wiring example, deinit
  inventory seven → eight), `implementation_guide_swift.md` (examples
  showing transport calls, sleep/wake, or AppState init),
  `architecture.md` (AppState file list → HC 5-area audit: Ports,
  Adapters, Services, Models, Errors read from the HarmoniaCore checkout
  at the pinned SHA).
