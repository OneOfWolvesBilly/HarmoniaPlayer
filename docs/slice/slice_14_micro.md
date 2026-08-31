# Slice 14 Micro-slices Specification

## Purpose

Fourth stage of the v1.1.0 AppState decomposition refactor program (design
authority: `appstate_refactor_plan.md`). Extracts the second
`@MainActor @Observable` feature store — `LyricsStore` — behind the
AppState strangler facade, following the structural template proven by
Slice 13 (AlertCenter). The lyrics surface has two properties, two owned
service dependencies, and no internal writers outside the code this slice
moves, so it is also the first extraction whose facade surface is removed
in the same slice (plan §6.0 step 7).

## Slice 14 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 14-A | Extract `LyricsStore` + `@Environment` view migration + test migration | — | ✅ |

### Goals

- `showLyrics` and `lyricsResolution` (program plan §3 rows 12–13) live in
  `LyricsStore`, which also takes ownership of `lyricsService` and
  `lyricsPreferenceStore`.
- Views reading lyrics state (ContentView, PlayerView lyrics button,
  LyricsPanel) observe `LyricsStore` via `@Environment(LyricsStore.self)`,
  no longer re-rendering on unrelated AppState changes.
- Tests whose real SUT is the lyrics state move to `LyricsStoreTests`
  (unit-test-core Rule 1 placement), with zero net loss of coverage.
- No lyrics facade surface survives the slice: every internal reader
  migrates here, so per plan §6.0 step 7 this slice is the removal slice
  for rows 12–13 — AppState ends holding only `let lyricsStore` and the
  retargeted `$currentTrack` sink.

### Out of Scope

- Formal replacement of the `$currentTrack` Combine sink with the
  `onCurrentTrackChanged` closure → PlaybackController stage (plan §5).
  This slice only retargets the existing sink body to
  `lyricsStore.updateResolution(for:)`.
- `architecture.md` §6.2 DI code excerpt still shows `lyricsService` /
  `lyricsPreferenceStore` as AppState stored properties after this slice —
  known drift, deferred to the language-mode close-out stage's final doc
  realignment (plan §7.5, where the HC 5-area audit runs once). Not
  touched here → HC 5-area audit not triggered.
- Lyrics write-back / editing (creating `.lrc` or karaoke-format files;
  lyrics expansion backlog) → future slices add methods on `LyricsStore`
  directly; no facade involvement.
- BL-13A-01, BL-13A-02 → unchanged targets (PlaylistCollection /
  SettingsStore stages).
- Any change to `EQCoordinator` / `NowPlayingCoordinator` → not in the
  program at all (plan §0).

### Constraints

- Program constraints C1–C5 (plan §4) govern the observation mechanics;
  every scene hosting a migrated view must inject the store or the app
  crashes at first read (C3 — audit result: main window only).
- The store never reads current-track state: every track-dependent method
  takes the track explicitly; callers (the facade sink, the views) supply
  `currentTrack`. This keeps the store free of playback coupling until the
  PlaybackController stage.
- New store code builds warning-free under the Slice 12 baseline; this
  slice re-measures the files it touches (plan §6.0 step 5).
- TDD red-green: red commit lands the failing tests against an
  intentionally-unwired skeleton (the 9-L precedent); "是請執行" gates
  the green phase.

### Dependencies

- Slice 13 (structural template; AlertCenter store + view-migration
  precedent).
- Slice 12 (baseline must exist for the warning-clearing obligation).

---

## Slice 14-A: Extract LyricsStore ✅

### Goal

Move the two lyrics-surface properties, the two lyrics service
dependencies, and the six lyrics methods out of AppState into a dedicated
`@MainActor @Observable` store, migrate every reader in the same slice,
and delete the AppState lyrics surface outright — no facade forwarders
remain.

### Scope (FROZEN as of spec commit)

**New store** `Shared/Models/LyricsStore.swift` — see Public API shape.
Deliberate choices frozen with it:

- All track-dependent methods (`recheckLyrics` / `setLyricsSource` /
  `setLyricsLanguage` / `setLyricsEncoding` / `updateResolution`) take the
  track explicitly. File-state check finding folded into the freeze: in
  today's AppState all four action methods read `currentTrack`, not just
  the resolution update — the parameter therefore moves to every one of
  them, and plan §7.1's "current-track access stays with the caller" is
  honoured store-wide.
- `recheckLyrics(for:)` stays on the store per the plan §7.1 method list
  as the user-intent entry point; it delegates to `updateResolution(for:)`.
- `lyricsService` and `lyricsPreferenceStore` are exposed as internal
  `let`s (same visibility they had on AppState); `LyricsPanel.reload()`
  reaches them through the store.
- The private `persistedEncoding(for:)` helper moves into the store
  unchanged.
- **No facade forwarders.** After this slice's view and test migration,
  the lyrics surface has zero internal readers (verified: no `AppState+*`
  extension, no Commands, no UITest, no other view or test touches it), so
  per plan §6.0 step 7 the facade surface for rows 12–13 is removed in
  this same slice instead of being created dead. This is an agreed
  deviation from the 13-A template shape, whose forwarders exist because
  alert state still has un-migrated writers.

**AppState changes:**

- `let lyricsStore: LyricsStore`, constructed in `init` right after the
  services it depends on exist (Step 4); receives the factory-made
  `lyricsService` and the injected-or-default `lyricsPreferenceStore`.
  The `lyricsPreferenceStore:` init parameter stays (tests inject it).
- The 2 lyrics `@Published` properties, the 6 lyrics methods
  (`toggleLyrics`, `recheckLyrics`, `setLyricsSource`,
  `setLyricsLanguage`, `setLyricsEncoding`, `updateLyricsResolution`), the
  private `persistedEncoding(for:)` helper, and the two dependency `let`s
  are deleted — not forwarded.
- Init Step 13: the `$currentTrack` sink body retargets to
  `lyricsStore.updateResolution(for: track)`. The sink itself and
  `@Published currentTrack` stay untouched until the PlaybackController
  stage (plan §5).

**View changes:**

| File | Change |
| --- | --- |
| `HarmoniaPlayerApp.swift` | main window scene adds `.environment(appState.lyricsStore)`; C3 audit result: the Mini Player, Equalizer, File Info, and Settings scene subtrees read no lyrics state and take no injection |
| `ContentView.swift` | `@Environment(LyricsStore.self)`; the lyrics-column condition reads `lyricsStore.showLyrics` (`currentTrack` still via `appState`) — file-state check finding folded into the freeze: plan §7.1's view list omitted this reader |
| `PlayerView.swift` | `@Environment(LyricsStore.self)`; the lyrics button icon reads `lyricsStore.showLyrics` and its action calls `lyricsStore.toggleLyrics()`; the disabled state still reads `appState.currentTrack` |
| `LyricsPanel.swift` | `@Environment(LyricsStore.self)`; resolution reads, the source/language/encoding pickers, and the Recheck button retarget the store, passing `appState.currentTrack` explicitly; `reload()` reads `lyricsService` / `lyricsPreferenceStore` via the store; keeps `@EnvironmentObject appState` for `currentTrack` and `languageBundle` |

### Acceptance Criteria

1. AC1: `Shared/Models/LyricsStore.swift` exists as
   `@MainActor @Observable final class` with the 2 properties, 2 owned
   dependencies, and 6 methods of the Public API shape, including
   `nonisolated deinit {}`.
2. AC2: `grep -c "@Published" AppState.swift` drops by exactly 2, and
   `grep -n "showLyrics\|lyricsResolution\|toggleLyrics\|setLyrics\|recheckLyrics\|updateLyricsResolution\|lyricsService\|lyricsPreferenceStore" AppState.swift`
   matches only the `lyricsStore` construction lines and the retargeted
   sink body.
3. AC3: every TDD-matrix test passes in the file its Test File Decision
   names; `AppStateLyricsTests.swift` no longer exists.
4. AC4: full ⌘U suite green; final test count = pre-slice count + 3 new
   LyricsStore tests (moved rows change file, never disappear).
5. AC5: the Slice 12 baseline carries no rows for the moved code (verified
   at spec time: `AppState.swift`, `AppStateLyricsTests.swift`,
   `LyricsPanel.swift`, `PlayerView.swift`, `ContentView.swift` all absent
   from the tables) → a Slice 14-A re-measurement note is recorded in
   `slice_12_micro.md` instead of row retirement; every touched file
   rebuilds warning-free except `HarmoniaPlayerApp.swift`, which keeps its
   baseline count (14) and dominant kind.
6. AC6 (manual, binary): each of the seven flows below behaves as before —
   (a) lyrics toggle button shows/hides the panel column; disabled when no
   track is loaded; (b) source picker switches Embedded ↔ .lrc on a track
   with both, and the choice survives switching away and back to the
   track; (c) language picker appears for multi-variant USLT and the
   chosen variant persists; (d) encoding menu appears for .lrc, a chosen
   charset persists, and "Auto" re-detects; (e) no-lyrics placeholder
   shows the Recheck button, and Recheck picks up a sidecar `.lrc` dropped
   in after the track was loaded, without re-loading the track;
   (f) switching tracks updates the panel content and re-applies the new
   track's persisted preference; (g) main window, Mini Player, Equalizer,
   File Info, and Settings scenes all open without a missing-injection
   crash.

### Out of Scope

- See slice-level Out of Scope (sink formal replacement, architecture.md
  drift, write-back futures, BL-13A-01/-02, coordinator changes).

### Deferred Backlog

None new.

### Files

- HarmoniaPlayer Application Layer:
  - add `Shared/Models/LyricsStore.swift`
  - modify `Shared/Models/AppState.swift`
  - `Shared/Models/AppState+Playback.swift` / `+Navigation.swift` /
    `+Playlist.swift` / `+M3U8.swift`: no expected change (verified: no
    lyrics references); touched only if the compiler disagrees
- UI: modify `ContentView.swift`, `PlayerView.swift`, `LyricsPanel.swift`,
  `HarmoniaPlayerApp.swift`
- Tests: add `SharedTests/LyricsStoreTests.swift`; delete
  `SharedTests/AppStateLyricsTests.swift` (rows move; the red commit
  performs the move per the 13-A precedent). `StubLyricsService` lives in
  `FakeInfrastructure/FakeCoreProvider.swift` and is unaffected.
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change needed
  (`PBXFileSystemSynchronizedRootGroup`, 13-A execution amendment)
- Docs at green: `api_reference.md`, `module_boundary.md`,
  `development_guide.md`, `implementation_guide_swift.md`
- Docs at close-out: `slice_12_micro.md` (re-measurement note), this spec
  (status ticks), `HarmoniaPlayer_development_plan.md` (slice table tick)

### TDD matrix

| Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- |
| `testInitialState_Defaults` | fresh `LyricsStore` | read both properties | `showLyrics == false`, `lyricsResolution == nil` | Move from `AppStateLyricsTests.swift` → New `LyricsStoreTests.swift` |
| `testToggleLyrics_FlipsVisibility` | fresh store | `toggleLyrics()` twice | `true` after first, `false` after second | Move → `LyricsStoreTests.swift` |
| `testUpdateResolution_NonNilTrack_QueriesServiceAndStores` | stub returns embedded resolution | `updateResolution(for: track)` | service queried once with the track; resolution stored | Move → `LyricsStoreTests.swift` |
| `testUpdateResolution_NilTrack_ClearsResolution` | resolution previously set | `updateResolution(for: nil)` | `lyricsResolution == nil` | Move → `LyricsStoreTests.swift` |
| `testUpdateResolution_NoLyrics_HasAnyFalse` | stub returns `.none` | `updateResolution(for: track)` | `hasAny == false` | Move → `LyricsStoreTests.swift` |
| `testUpdateResolution_AppliesPersistedLanguage` | multi-language stub; persisted pref says `"chi"` | `updateResolution(for: track)` | `currentLanguage == "chi"` | Move → `LyricsStoreTests.swift` |
| `testSetLyricsLanguage_UpdatesResolutionAndPersists` | embedded multi-language resolution loaded | `setLyricsLanguage("chi", for: track)` | resolution reflects `"chi"`; pref persisted | Move → `LyricsStoreTests.swift` |
| `testSetLyricsEncoding_PersistsValue` | resolution loaded | `setLyricsEncoding("big5", for: track)` | persisted pref encoding is `"big5"` | Move → `LyricsStoreTests.swift` |
| `testSetLyricsSource_SwitchesSourceAndPersists` | resolution with both sources available, current `.embedded` | `setLyricsSource(.lrc, for: track)` | `currentSource == .lrc`; pref persisted with source `.lrc` | New `LyricsStoreTests.swift` |
| `testSetLyricsSource_UnavailableSource_NoOp` | resolution with `availableSources == [.embedded]` | `setLyricsSource(.lrc, for: track)` | resolution unchanged; nothing persisted | New `LyricsStoreTests.swift` |
| `testRecheckLyrics_RequeriesService` | stub returns embedded resolution | `recheckLyrics(for: track)` | service queried once; resolution stored | New `LyricsStoreTests.swift` |
| (regression, no new test) | tracks with embedded/sidecar lyrics | existing service-level flows | `LyricsServiceTests` / `LyricsPreferenceStoreTests` / `EncodingDetectionTests` / `LRCStripTests` rows stay green unchanged (services change owner, not behaviour) | Existing files, unchanged |

Red phase: rows 2–9 and 11 fail against the intentionally-unwired
skeleton (9 failures). Row 1 is a green-from-start guard, and row 10 is a
negative guard that passes vacuously against the honest empty-body
skeleton (the 13-A amendment precedent — forcing it red would require a
deliberately-wrong skeleton body). Row 12 stays green throughout.

Execution amendment (recorded at close-out): the observed red set matched
the prediction row for row. AC4's "pre-slice count" was re-measured at the
spec commit as 493 passed / 5 skipped — the 494 figure recorded at the
13-A close-out overcounted by one — so the green suite's 496 passed /
5 skipped / 0 failed is exactly pre-slice + 3.

The moved rows drop their `testAppState_` prefix and the fixture no longer
constructs an AppState: the SUT is built directly as
`LyricsStore(lyricsService: stub, lyricsPreferenceStore:
DefaultLyricsPreferenceStore(userDefaults: testDefaults))`, and the track
is passed explicitly instead of through `sut.currentTrack`.

### Public API shape

```swift
@MainActor @Observable
final class LyricsStore {

    // Panel visibility
    var showLyrics = false

    // Availability + selected source/language for the caller-supplied
    // track; nil when no track is loaded
    var lyricsResolution: LyricsResolution?

    // Owned dependencies (moved from AppState)
    let lyricsService: LyricsService
    let lyricsPreferenceStore: LyricsPreferenceStore

    init(lyricsService: LyricsService,
         lyricsPreferenceStore: LyricsPreferenceStore)

    /// Toggles the lyrics panel visibility.
    func toggleLyrics()

    /// Re-runs lyrics availability detection for the given track — the
    /// user-intent entry point behind the panel's Recheck button.
    /// Delegates to `updateResolution(for:)`.
    func recheckLyrics(for track: Track?)

    /// Switches the active lyrics source (`.embedded` ↔ `.lrc`) for the
    /// given track. No-op when the source is unavailable. Persists the
    /// choice via `LyricsPreferenceStore`.
    func setLyricsSource(_ source: LyricsSource, for track: Track?)

    /// Selects a USLT language variant for the given track. No-op when
    /// the current source is not `.embedded`. Persists the choice.
    func setLyricsLanguage(_ languageCode: String?, for track: Track?)

    /// Sets the `.lrc` decoding charset for the given track. Persists
    /// the choice; `"auto"` triggers auto-detection on next read.
    func setLyricsEncoding(_ encoding: String, for track: Track?)

    /// Recomputes `lyricsResolution` for the given track, applying any
    /// persisted preference. `nil` clears the resolution.
    func updateResolution(for track: Track?)

    nonisolated deinit {}
}
```

### Implementation notes

- Red-phase skeleton precedent: 9-L / 13-A (store lands with properties
  at their defaults and empty method bodies; tests define the contract).
- C1 keeps LyricsPanel correct mid-migration: its body reads both
  `appState.currentTrack` (ObservableObject invalidation) and
  `lyricsStore` properties (Observation tracking) in the same body
  evaluation (C5).
- Token discipline: sections moved into the store get clean doc comments;
  the LyricsPanel header is rewritten where its narrative goes stale
  (`appState.showLyrics`), and tokens on rewritten lines are cleaned;
  untouched regions (e.g. PlayerView's EQ-button comment) keep their
  existing tokens for the slice that moves them.
- Doc obligations at green (skill Doc Update Table, full line-by-line
  read): `api_reference.md` (new type; AppState property/method/init
  changes), `module_boundary.md` (new state-owning type),
  `development_guide.md` (project structure, deinit inventory),
  `implementation_guide_swift.md` (examples showing lyrics properties or
  AppState init). `architecture.md` untouched → HC 5-area audit not
  triggered (drift recorded in Out of Scope).
