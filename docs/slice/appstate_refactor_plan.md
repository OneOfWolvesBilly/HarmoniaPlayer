# AppState Decomposition Refactor — Program Plan (總綱)

## 0. Purpose, slicing discipline, and version attribution

This program decomposes the 2,398-line `AppState` god object into five
`@MainActor @Observable` feature stores behind a strangler facade, migrates
the view layer from whole-object `@EnvironmentObject` subscription to
per-store `@Environment` injection, and finishes by switching the app and
test targets from the Swift 5 language mode to Swift 6.

- **This document is a program-level design authority, not a slice.** Each
  stage below is its own slice with its own spec file, because each is a
  distinct concern. This is the corrective to Slice 9's failure mode:
  slice 9 bundled UI-flow conformance, lyrics, EQ, Now Playing, sandboxing,
  and ship preparation into one ever-growing slice. One slice = one
  concern; a slice whose scope grows a second concern is split, not
  extended.
- **Numbering.** A slice receives its number when it opens, taking the
  next free number at that moment. The former "Slice 10 = Pro tier"
  reservation in `HarmoniaPlayer_development_plan.md` is removed — the Pro
  tier slice will be numbered when it opens. Stages of this program that
  are already opened and numbered:

  | Stage | Slice | Spec |
  | --- | --- | --- |
  | Token cleanup | **10** | `slice_10_micro.md` |
  | Strict-concurrency warning baseline | **12** | `slice_12_micro.md` |
  | Extract AlertCenter | **13** | `slice_13_micro.md` |
  | Extract LyricsStore | **14** | `slice_14_micro.md` |
  | Extract SettingsStore | — (numbered at open) | §7.2 scope freeze |
  | Extract PlaybackController | — | §7.3 scope freeze |
  | Extract PlaylistCollection (incl. M3U8) | — | §7.4 scope freeze |
  | Swift 6 language-mode switch + close-out | — | §7.5 scope freeze |

  Execution order is the table order, strictly sequential. Stores are
  extracted small → large so the strangler mechanics are proven on the
  cheapest store first.
- **Version attribution: v1.1.0** (Chen's decision — this program is the
  core of the v1.1.0 Free minor). The older v2.0.0 labels in the
  development plan and the harmonia-dev-workflow skill were stale records,
  corrected together with this section. The v1.1.0 Free minor also
  carries candidate slices outside this program (window-menu declarative
  semantics, lyrics expansion backlog, …), numbered when they open.
- **Out of scope.** HarmoniaCore (hexagonal architecture is clean; only
  Slice 10 touches one HC file's doc comments). `EQCoordinator` and
  `NowPlayingCoordinator` keep their current design; they are wired, not
  rewritten.

## 1. Problem

- `AppState` = 2,398 lines across 5 files (`AppState.swift` 998,
  `+Playlist` 586, `+Playback` 401, `+Navigation` 301, `+M3U8` 112),
  31 `@Published` properties, ~55 methods, 10 held services/dependencies.
- 10+ views subscribe the whole object via `@EnvironmentObject`.
  `ObservableObject` invalidation is object-level: `currentTime` ticking 4×
  per second re-evaluates every subscribed view body.
- UI-surface state (`showFileNotFoundAlert`, `fileInfoTrack`, `showPaywall`,
  `skipped*`) is interleaved with domain state (`playlists`,
  `playbackState`) in one type.
- Existing correct precedents: `EQCoordinator` (state-owning coordinator
  outside AppState), `NowPlayingCoordinator` (closure/publisher-injected
  coordinator with no AppState reference).

## 2. Target architecture

```
HarmoniaPlayerApp
  └─ AppState (composition root: construction + wiring only)
       ├─ AlertCenter          @MainActor @Observable
       ├─ LyricsStore          @MainActor @Observable
       ├─ SettingsStore        @MainActor @Observable
       ├─ PlaybackController   @MainActor @Observable
       ├─ PlaylistCollection   @MainActor @Observable
       ├─ EQCoordinator        (unchanged, ObservableObject)
       └─ NowPlayingCoordinator (unchanged, publisher-injected)

Views: @Environment(StoreType.self) per store actually read.
EQView/EQWindow keep @EnvironmentObject EQCoordinator (unchanged design).
```

Store dependency direction (construction order in the composition root):

```
AlertCenter ← (no store deps)
LyricsStore ← lyricsService, lyricsPreferenceStore
SettingsStore ← iapManager, userDefaults
PlaybackController ← playbackService, AlertCenter, SettingsStore, PlaylistContext
PlaylistCollection ← tagReaderService, fileDropService, playlistStore,
                     undoManager, AlertCenter, SettingsStore
```

Cycles are forbidden. Upward/lateral notifications (e.g. playlist mutation →
playback reaction) use closures wired by the composition root, following the
`NowPlayingCoordinator` injection precedent (§5).

## 3. `@Published` → store mapping (31 properties)

| # | AppState property | Destination | Notes |
| --- | --- | --- | --- |
| 1 | `lastError` | AlertCenter | |
| 2 | `lastErrorDetail` | AlertCenter | |
| 3 | `failedTrackName` | AlertCenter | |
| 4 | `showFileNotFoundAlert` | AlertCenter | view binding via `@Bindable` |
| 5 | `skippedInaccessibleNames` | AlertCenter | |
| 6 | `skippedDuplicateURLs` | AlertCenter | |
| 7 | `skippedImportURLs` | AlertCenter | |
| 8 | `skippedUnsupportedURLs` | AlertCenter | |
| 9 | `fileInfoTrack` | AlertCenter | ContentView `.onChange` + clear |
| 10 | `showPaywall` | AlertCenter | sheet binding via `@Bindable` |
| 11 | `paywallDismissedThisSession` | AlertCenter | session-only, never persisted |
| 12 | `showLyrics` | LyricsStore | |
| 13 | `lyricsResolution` | LyricsStore | |
| 14 | `allowDuplicateTracks` | SettingsStore | persisted `hp.allowDuplicateTracks` |
| 15 | `selectedLanguage` | SettingsStore | persisted `hp.selectedLanguage` |
| 16 | `replayGainMode` | SettingsStore | persisted `hp.replayGainMode`; change-notify → PlaybackController (§5) |
| 17 | `viewPreferences` | SettingsStore | |
| 18 | `isProUnlocked` | SettingsStore | with `featureFlags`, `purchasePro()`, `refreshEntitlements()` |
| 19 | `playbackState` | PlaybackController | |
| 20 | `currentTrack` | PlaybackController | change-notify → LyricsStore + NowPlaying bridge (§5) |
| 21 | `currentTime` | PlaybackController | the object-level-invalidation hot spot; afterwards only views reading it re-render |
| 22 | `duration` | PlaybackController | |
| 23 | `playingPlaylistID` | PlaybackController | |
| 24 | `volume` | PlaybackController | persisted `hp.volume`; forwards to `PlaybackService` |
| 25 | `repeatMode` | PlaybackController | persisted `hp.repeatMode` |
| 26 | `isShuffled` | PlaybackController | persisted `hp.isShuffled` |
| 27 | `playlists` | PlaylistCollection | persisted via `PlaylistStore` |
| 28 | `activePlaylistIndex` | PlaylistCollection | persisted `hp.activePlaylistIndex` |
| 29 | `selectedTrackIDs` | PlaylistCollection | |
| 30 | `isPerformingBlockingOperation` | PlaylistCollection | |
| 31 | `eqEnabled` | **deleted** | mirror obsolete: PlayerView reads `EQCoordinator` directly via `@EnvironmentObject` (PlaybackController stage, where PlayerView is already being migrated); the `$isEnabled` sink in AppState init is removed with it |

Non-published mutable state:

| AppState member | Destination |
| --- | --- |
| `pendingSeekTime`, `shuffleQueue`, `shuffleQueueIndex`, `lastPlayedTrackID`, `pollingTask` | PlaybackController (`@ObservationIgnored` where no view reads them) |
| `cancellables` | dissolves — each Combine sink is replaced per §5 in the slice that owns it |
| `featureFlags` | SettingsStore |
| `languageBundle` | SettingsStore (`let`) |
| `undoManager` | PlaylistCollection |
| `displayName(for:)` | `Track` extension (PlaybackController stage) — pure formatting, used by playback error paths and views |
| `freeFormats` / `proOnlyFormats` / `allowedFormats` / `saveBatchSize` | PlaylistCollection (static) |

Service/dependency ownership after the PlaylistCollection stage:

| Dependency | Owner |
| --- | --- |
| `playbackService` | PlaybackController |
| `tagReaderService`, `fileDropService`, `playlistStore` | PlaylistCollection |
| `lyricsService`, `lyricsPreferenceStore` | LyricsStore |
| `iapManager`, `userDefaults` (settings keys) | SettingsStore |
| `eqCoordinator`, `nowPlayingCoordinator` | AppState (composition root) |

## 4. Store concurrency design

Every store is:

```swift
@MainActor @Observable
final class <Store> {
    nonisolated deinit {}   // project-wide Xcode 26 beta workaround (dev guide §9.1/§9.6)
}
```

- Explicit `@MainActor` even though the app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — documentation parity with
  AppState/EQCoordinator, and the test target does **not** set default
  MainActor isolation, so explicitness keeps test-side reasoning identical.
- Stores are reference types isolated to the main actor and are **not**
  `Sendable`; the Sendable surface stays where it is today — the value
  models crossing actor boundaries (`Track`, `Playlist`, `PlaybackState`,
  `PlaybackError`, `ViewPreferences`, `CoreFeatureFlags`).
- Async work inside stores follows the existing AppState pattern
  (`Task { @MainActor in … }`, awaited service calls); no store spawns
  detached tasks.
- New store code is written Swift-6-ready: it must build **warning-free**
  under the Slice 12 `SWIFT_STRICT_CONCURRENCY = complete` baseline, and
  each extraction slice clears the baseline warnings of the code it moves.

### Observation-migration behavioral constraints (verified)

The following external-behavior facts were verified via web research before
this plan was frozen (source log: `appstate_refactor_plan_draft.md`, not
committed). They are design constraints, not assumptions:

- **C1** `@Observable` gives property-level dependency tracking: a view
  re-evaluates only when a property its `body` actually read changes. This
  holds through indirection — a facade computed property forwarding to a
  store property still registers the store property's access during body
  evaluation. This is what makes the strangler facade observable-correct.
- **C2** Observation, `@Environment(Type.self)`, and `@Bindable` require
  macOS 14+; deployment target 15.6 satisfies them.
- **C3** `@Environment(Type.self)` as a non-optional crashes at first read
  if nothing was injected via `.environment(_:)`. Every scene that hosts a
  migrated view MUST inject the store; the optional form exists but is NOT
  used — a missing injection is a wiring bug and must crash in development,
  not silently no-op.
- **C4** `@Bindable` provides `$store.property` bindings for
  `.sheet(isPresented:)` / `.alert(isPresented:)` / pickers, replacing
  `$appState.property` (`@EnvironmentObject` projected bindings).
- **C5** `ObservableObject` and `@Observable` coexist in one app and in one
  view; SwiftUI runs both invalidation mechanisms during the same body
  evaluation. Per-store migration therefore never requires a big-bang view
  rewrite: un-migrated views keep `@EnvironmentObject var appState` and
  keep working while migrated views use `@Environment(Store.self)`.
- **C6** `@Observable` classes have **no** `$property` Combine publishers.
  Every `$property` sink or publisher hand-off in AppState init must be
  replaced in the slice that migrates the property (§5).
- **C7** `@MainActor @Observable` is the recommended Swift 6 posture for
  UI-facing state (Apple DTS); no known macro/actor incompatibility. The
  app target's existing `SWIFT_APPROACHABLE_CONCURRENCY = YES` +
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + Swift 5 mode matches the
  Xcode 26 recommended migration posture, which Slice 12 and the final
  language-mode slice build on.
- **C8** `SWIFT_STRICT_CONCURRENCY = complete` under the Swift 5 language
  mode surfaces Swift-6-level diagnostics as **warnings**, not errors —
  Slice 12 cannot break the build.

## 5. Combine replacement map

AppState init currently owns six `$property` sinks plus two publisher
hand-offs; `@Observable` removes the `$` publishers (C6). Replacements,
scheduled with the stage that migrates each property:

| Current Combine usage | Replacement | Stage |
| --- | --- | --- |
| `$replayGainMode` → `applyReplayGainVolume` sink | `SettingsStore.replayGainMode` `didSet` → `onReplayGainModeChanged` closure, wired by root to PlaybackController | SettingsStore (closure lands) / PlaybackController (target moves) |
| `$replayGainMode` / `$selectedLanguage` → `saveState()` sinks | store `didSet` persists its own key directly | SettingsStore |
| `$repeatMode` / `$isShuffled` → `saveState()` sinks | PlaybackController `didSet` persists its own keys | PlaybackController |
| `$currentTrack` → `updateLyricsResolution` sink | PlaybackController `currentTrack` `didSet` → `onCurrentTrackChanged` closure, wired by root to `LyricsStore.updateResolution(for:)` | PlaybackController |
| `eqCoordinator.$isEnabled` → `eqEnabled` mirror sink | deleted with the mirror (mapping row 31) | PlaybackController |
| `$currentTrack` / `$playbackState` `AnyPublisher` handed to `NowPlayingCoordinator` | PlaybackController keeps two private `CurrentValueSubject`s fed from `didSet` and exposes `AnyPublisher`s; root passes them to the (unchanged) `NowPlayingCoordinator` init | PlaybackController |

`NowPlayingCoordinator` and `EQCoordinator` source files stay untouched
throughout.

## 6. Shared mechanics

### 6.0 Strangler-facade protocol (applies to every extraction slice)

Each extraction slice performs, in order, all green at every step:

1. **Red**: new `<Store>Tests.swift` lands with the store's contract tests
   failing (store skeleton exists; behavior intentionally unwired — the
   9-L red-phase precedent).
2. **Green**: store implemented; AppState constructs it (`let <store>`),
   deletes the migrated `@Published` properties, and re-exposes them as
   **facade computed properties** (get+set forwarding to the store) plus
   facade method delegation, so every un-migrated internal call site and
   test compiles unchanged.
3. **Views**: views whose body reads migrated state switch to
   `@Environment(Store.self)` (+ `@Bindable` where bindings are needed) in
   the same slice; scenes gain the `.environment(…)` injection (C3 audit
   across all five scenes: main window, Mini Player, EQ window, File Info
   window, Settings).
4. **Tests migrate**: existing tests whose real SUT is the store move into
   `<Store>Tests.swift` (placement fix per unit-test-core Rule 1); tests
   exercising cross-store orchestration stay on AppState and keep passing
   through the facade. The slice's TDD matrix lists every moved test.
5. **Concurrency**: the moved code builds warning-free under the Slice 12
   baseline; the slice records which baseline warnings it retired.
6. **Docs**: per the Doc Update Table (AppState init/property changes →
   `api_reference.md`, `implementation_guide_swift.md`; new type →
   `api_reference.md`, `module_boundary.md`, `development_guide.md`
   structure).
7. Facade removal for a given property/method happens in the **last** slice
   that still has internal readers of it; whatever facade surface survives
   the PlaylistCollection stage is deleted in the language-mode close-out
   slice (target: AppState ends as construction + wiring only).

View-injection end state (HarmoniaPlayerApp, per scene; grows one line per
extraction stage):

```swift
ContentView()
    .environmentObject(appState)                    // shrinks per stage; removed at close-out if no reader remains
    .environment(appState.alertCenter)
    .environment(appState.lyricsStore)
    .environment(appState.settingsStore)
    .environment(appState.playbackController)
    .environment(appState.playlistCollection)
    .environmentObject(appState.eqCoordinator)      // replaces the eqEnabled mirror
```

- A view declares `@Environment(Store.self)` only for stores its body
  actually reads — the whole point is shrinking each view's invalidation
  surface.
- `HarmoniaPlayerCommands` is not a scene subtree receiving environment; it
  keeps reaching state via its focused `appState` and dotted paths
  (`appState.alertCenter.…`). Commands migrate off facade properties in the
  same slice as the property, but stay on the `appState.<store>` path.

### 6.1 Persistence split

`saveState()`/`restoreState()` decompose along store lines; each store owns
its `PersistenceKey`s and persists on change (`didSet`), preserving today's
change-time persistence behavior. The composition root keeps one
`saveAll()` called from `willTerminateNotification`, delegating to each
store. Restore order at init: SettingsStore → PlaylistCollection (incl.
accessibility re-check + `refreshMetadataIfNeeded`) → PlaybackController
(volume/repeat/shuffle). Key-to-store table:

| Key | Store |
| --- | --- |
| playlists (FilePlaylistStore) + legacy `hp.playlists` migration | PlaylistCollection |
| `hp.activePlaylistIndex` | PlaylistCollection |
| `hp.allowDuplicateTracks`, `hp.selectedLanguage`, `hp.replayGainMode` | SettingsStore |
| `hp.volume`, `hp.repeatMode`, `hp.isShuffled` | PlaybackController |
| EQ keys | EQPersistenceStore (unchanged) |
| lyrics preference keys | LyricsPreferenceStore (unchanged) |

### 6.2 Test migration map

~500 existing tests. Per-store moves happen inside each extraction slice
(§6.0 step 4), keeping the suite green at every commit. Expected final
placement of today's 21 `AppState*Tests` files + known misplaced tests:

| Existing file | Destination (stage) |
| --- | --- |
| `AppStateTests` (init/wiring rows) | stays (composition-root contract) |
| `AppStateTests` (error/preference initial-state rows) | AlertCenterTests / SettingsStoreTests |
| `AppStateErrorHandlingTests`, `AppStateFileInfoTests` | split: pure alert-state rows → AlertCenterTests (Slice 13); load/play flow rows → PlaybackControllerTests / PlaylistCollectionTests |
| `IAPManagerTests`' `showPaywallIfNeeded` rows (misplaced) | AppStateTests via facade (Slice 13); final home decided at the SettingsStore stage |
| `AppStateLyricsTests` | LyricsStoreTests |
| `AppSettingsTests`, `AppStateVolumeTests` (settings rows) | SettingsStoreTests / PlaybackControllerTests (volume) |
| `AppStatePlayback*`, `AppStatePolling`, `AppStateReplayGain`, `AppStateShuffle`, `AppStateNavigationTests`, `AppStateTrackSelectionTests` | PlaybackControllerTests family |
| `AppStatePlayerlist`, `AppStateMultiPlaylist`, `AppStateDragReorder`, `AppStateUndo`, `AppStateFormatGating`, `AppStateMetadataTests`, `AppStatePersistenceTests` (playlist rows) | PlaylistCollectionTests family |
| `IntegrationTests` | stays on AppState (cross-store flows are its SUT) |

Splitting a store's test file by behavioral category
(`PlaybackControllerTransportTests`, …) is allowed per unit-test-core;
splitting by slice is not.

### 6.3 Language-mode three-stage plan

1. **Slice 12**: `SWIFT_STRICT_CONCURRENCY = complete` on app + test +
   UITest targets, Swift 5 mode kept → warning baseline recorded in
   `slice_12_micro.md`.
2. **Extraction stages**: new store code warning-free; each slice retires
   the baseline warnings of the code it moves.
3. **Close-out slice**: remove the per-target `SWIFT_VERSION = 5.0`
   overrides (project level 6.0 takes effect), remove the now-redundant
   `SWIFT_STRICT_CONCURRENCY` lines, fix any residual diagnostics, realign
   docs. Language-mode flip is its own slice and never shares a commit with
   store extraction.

## 7. Scope freezes for unopened stages

Numbered and fully specified (own `slice_NN_micro.md`, structural template =
`slice_13_micro.md`) when each opens.

### 7.1 LyricsStore
`showLyrics`, `lyricsResolution`; owns `lyricsService` +
`lyricsPreferenceStore`; methods `toggleLyrics` / `recheckLyrics` /
`setLyricsSource` / `setLyricsLanguage` / `setLyricsEncoding` /
`updateResolution(for:)` — every track-dependent method takes the track
explicitly (current-track access stays with the caller). Views:
ContentView lyrics-column condition, LyricsPanel, PlayerView lyrics
button. Tests: `AppStateLyricsTests` → `LyricsStoreTests`.

### 7.2 SettingsStore
Mapping rows 14–18 + `featureFlags`, `languageBundle`, `purchasePro()`,
`refreshEntitlements()`; owns `iapManager` + its persistence keys;
`onReplayGainModeChanged` closure (§5). Views: SettingsView, PaywallView
purchase path. Decides the final `showPaywallIfNeeded` seam. Tests:
`AppSettingsTests` + settings rows elsewhere → `SettingsStoreTests`.

### 7.3 PlaybackController
Mapping rows 19–26 + all non-published playback state + transport /
navigation / polling / ReplayGain / error-mapping methods;
`PlaylistContext` transitional protocol (implemented by AppState until the
PlaylistCollection stage); NowPlaying publisher bridge +
`onCurrentTrackChanged` (§5); deletes `eqEnabled` mirror; `displayName` →
`Track` extension; PlayerView + MiniPlayerView + ContentView transport
migration. Largest test move (§6.2).

### 7.4 PlaylistCollection
Mapping rows 27–30 + playlist/tab/undo/M3U8/persistence/metadata-refresh
methods + format statics; `PlaylistContext` moves here; PlaylistView +
Commands migration; facade shrinks to construction + wiring + any
straggler.

### 7.5 Swift 6 language-mode switch + close-out
Remove `SWIFT_VERSION = 5.0` overrides and `SWIFT_STRICT_CONCURRENCY`
lines; zero-warning gate against the Slice 12 baseline; delete residual
facade surface; final doc realignment (`development_guide.md` language
narrative, `README.md`, `architecture.md` — the latter triggers the HC
5-area audit). Exit criterion closes the program.
