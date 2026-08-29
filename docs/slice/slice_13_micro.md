# Slice 13 Micro-slices Specification

## Purpose

Third stage of the v1.1.0 AppState decomposition refactor program (design
authority: `appstate_refactor_plan.md`). Extracts the first
`@MainActor @Observable` feature store — `AlertCenter` — behind the
AppState strangler facade. Alert state is the smallest store, has no
persistence and no service dependencies, so this slice proves the
program's strangler protocol (plan §6.0) end-to-end and serves as the
structural template for the later store extractions.

## Slice 13 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 13-A | Extract `AlertCenter` + `@Environment` view migration + test migration | — | ✅ |

### Goals

- All 11 alert/paywall/file-info state properties live in `AlertCenter`;
  AppState re-exposes them only as facade forwarders.
- Views reading alert state observe `AlertCenter` via
  `@Environment(AlertCenter.self)`, no longer re-rendering on unrelated
  AppState changes.
- Tests whose real SUT is the alert state move to `AlertCenterTests`
  (unit-test-core Rule 1 placement), with zero net loss of coverage.

### Out of Scope

- `private(set)` tightening of store properties → PlaylistCollection
  stage (last external writer moves there); tracked as BL-13A-01.
- `showPaywallIfNeeded()` final seam (tier check placement) →
  SettingsStore stage, when `isProUnlocked` moves; tracked as BL-13A-02.
- Moving the `playbackState .error → .stopped` transition out of the
  facade → PlaybackController stage.
- Any change to `EQCoordinator` / `NowPlayingCoordinator` → not in the
  program at all (plan §0).

### Constraints

- Program constraints C1–C5 (plan §4) govern the observation mechanics:
  facade forwarding keeps `@EnvironmentObject` views correct (C1/C5);
  every scene hosting a migrated view must inject the store or the app
  crashes at first read (C3); bindings use `@Bindable` (C4).
- New store code builds warning-free under the Slice 12 baseline; this
  slice retires the baseline warnings of the code it moves (plan §6.0
  step 5).
- TDD red-green: red commit lands the failing tests against an
  intentionally-unwired skeleton (the 9-L precedent); "是請執行" gates
  the green phase.

### Dependencies

- Slice 12 (baseline must exist for the warning-clearing obligation).

---

## Slice 13-A: Extract AlertCenter ✅

### Goal

Move the 11 alert-surface properties (program plan §3 rows 1–11) and
their presentation methods out of AppState into a dedicated
`@MainActor @Observable` store, with facade delegation keeping every
un-migrated call site and test compiling unchanged.

### Scope (FROZEN as of spec commit)

**New store** `Shared/Models/AlertCenter.swift` — see Public API shape.
Deliberate choices frozen with it:

- Properties stay plain `var`: un-migrated call sites in
  `AppState+Playback/+Navigation/+Playlist/+M3U8` keep writing through
  the facade's forwarding setters until later stages move them.
- Tier logic does NOT enter AlertCenter: `showPaywallIfNeeded()` stays a
  facade method (checks `isProUnlocked`, calls `presentPaywall()`).
- `clearLastError()`'s `playbackState .error → .stopped` transition stays
  in the AppState facade.
- `showFileInfo(trackID:)` lookup (needs `playlist`) stays in the facade;
  the store carries only the request state.

**AppState changes:**

- `let alertCenter: AlertCenter`, constructed first in `init` (no deps).
- The 11 `@Published` properties are deleted; same-named facade computed
  properties (get + set → `alertCenter`) replace them.
- Facade methods `clearLastError()`, `showFileInfo(trackID:)`,
  `showPaywallIfNeeded()` delegate as above.

**View changes:**

| File | Change |
| --- | --- |
| `HarmoniaPlayerApp.swift` | every scene whose subtree reads alert state adds `.environment(appState.alertCenter)` (audit all five scenes at execution per C3) |
| `ContentView.swift` | `@Environment(AlertCenter.self)`; `@Bindable` bindings replace `$appState.showPaywall` / `$appState.showFileNotFoundAlert`; the four alert `Binding(get:set:)` closures and `.onChange(of: fileInfoTrack)` retarget the store |
| `PaywallView.swift` | writes `alertCenter.paywallDismissedThisSession` via `@Environment(AlertCenter.self)` |
| `PlaylistView.swift` | import-skip warning reads `alertCenter.skippedImportURLs` |
| `HarmoniaPlayerCommands.swift` | reaches the store via the focused `appState.alertCenter` path (Commands receive no environment; plan §6.0) |

### Acceptance Criteria

1. AC1: `Shared/Models/AlertCenter.swift` exists as
   `@MainActor @Observable final class` with the 11 properties and 4
   methods of the Public API shape, including `nonisolated deinit {}`.
2. AC2: `grep -c "@Published" AppState.swift` drops by exactly 11, and
   none of the 11 property names appears with `@Published` anywhere.
3. AC3: every TDD-matrix test passes in the file its Test File Decision
   names.
4. AC4: full ⌘U suite green; final test count = pre-slice count + new
   AlertCenter tests (moved rows change file, never disappear).
5. AC5: the Slice 12 baseline table's warning rows for the moved code are
   retired (updated table committed with this slice).
6. AC6 (manual, binary): each of the six flows below behaves as before —
   (a) duplicate drop → already-in-playlist alert, OK clears; (b) `.xyz`
   drop → unsupported-format alert; (c) missing file played →
   file-not-found alert auto-dismisses after 3 s + strikethrough row;
   (d) M3U8 import with missing file → import-skip warning from both the
   File menu and the tab context menu; (e) File Info opens from context
   menu and reopens for the same track; (f) Mini Player, EQ window, and
   Settings scenes all open without a missing-injection crash.

### Out of Scope

- See slice-level Out of Scope (BL-13A-01, BL-13A-02, playbackState
  transition move, coordinator changes).

### Deferred Backlog

1. BL-13A-01 — tighten AlertCenter setters to `private(set)` once the
   last external writer moves; target: PlaylistCollection stage.
2. BL-13A-02 — decide `showPaywallIfNeeded()`'s final seam (facade vs
   SettingsStore vs caller-side); target: SettingsStore stage.

### Files

- HarmoniaPlayer Application Layer:
  - add `Shared/Models/AlertCenter.swift`
  - modify `Shared/Models/AppState.swift`
  - `Shared/Models/AppState+Playback.swift` / `+Navigation.swift` /
    `+Playlist.swift` / `+M3U8.swift`: no expected change (facade keeps
    them compiling); touched only if the compiler disagrees
- UI: modify `ContentView.swift`, `PaywallView.swift`,
  `PlaylistView.swift`, `HarmoniaPlayerApp.swift`,
  `HarmoniaPlayerCommands.swift`
- Tests: add `SharedTests/AlertCenterTests.swift`; modify
  `AppStateTests.swift`, `AppStateErrorHandlingTests.swift`,
  `AppStateFileInfoTests.swift`, `IAPManagerTests.swift`
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change needed
  (execution amendment: the project uses
  `PBXFileSystemSynchronizedRootGroup`, so new `.swift` files under the
  synchronized roots join their targets automatically; the 9-L file
  additions likewise left the pbxproj untouched)

### TDD matrix

| Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- |
| `testInitialState_AllSurfacesCleared` | fresh `AlertCenter` | read all 11 properties | all nil / false / empty | New `AlertCenterTests.swift` |
| `testClearLastError_ClearsErrorSurface` | error surface populated (5 fields) | `clearLastError()` | `lastError`, `lastErrorDetail`, `failedTrackName`, `showFileNotFoundAlert`, `skippedInaccessibleNames` cleared | New `AlertCenterTests.swift` |
| `testClearLastError_KeepsBatchSkipLists` | 3 batch-skip lists populated | `clearLastError()` | `skippedDuplicateURLs` / `skippedImportURLs` / `skippedUnsupportedURLs` unchanged | New `AlertCenterTests.swift` |
| `testPresentFileInfo_SetsRequest` | a `Track` | `presentFileInfo(track)` | `fileInfoTrack == track` | New `AlertCenterTests.swift` |
| `testClearFileInfoRequest_Resets` | `fileInfoTrack` set | `clearFileInfoRequest()` | `fileInfoTrack == nil` | New `AlertCenterTests.swift` |
| `testPresentPaywall_SetsFlag` | fresh store | `presentPaywall()` | `showPaywall == true`; `paywallDismissedThisSession` still `false` | New `AlertCenterTests.swift` |
| `testShowPaywallIfNeeded_Free_PresentsAndReturnsTrue` | AppState with `MockIAPManager(isProUnlocked: false)` | `showPaywallIfNeeded()` | returns `true`; `alertCenter.showPaywall == true` | Move from `IAPManagerTests.swift` → `AppStateTests.swift` (placement fix) |
| `testShowPaywallIfNeeded_Pro_NoopReturnsFalse` | `MockIAPManager(isProUnlocked: true)` | `showPaywallIfNeeded()` | returns `false`; `showPaywall` stays `false` | Move from `IAPManagerTests.swift` → `AppStateTests.swift` (placement fix) |
| `testClearLastError_ErrorState_BecomesStopped` | `playbackState == .error(…)` | `AppState.clearLastError()` | `playbackState == .stopped` + store surface cleared | Extend `AppStateErrorHandlingTests.swift` |
| `testShowFileInfo_SetsAlertCenterTrack` | track in active playlist | `showFileInfo(trackID:)` | `alertCenter.fileInfoTrack` is that track | Extend `AppStateFileInfoTests.swift` (existing rows retarget the store) |
| `testShowFileInfo_UnknownID_NoOp` | ID not in playlist | `showFileInfo(trackID:)` | `fileInfoTrack` unchanged | Extend `AppStateFileInfoTests.swift` |
| (regression, no new test) | inaccessible track | `play(trackID:)` | file-not-found surface raised through the facade — existing rows in `AppStateErrorHandlingTests` / `AppStatePlaybackTrackTests` stay green unchanged | Existing files, unchanged |

Red phase: rows 2–6 fail against the intentionally-unwired skeleton;
rows 7–11 fail against the not-yet-delegating facade. Rows 1 and 12 are
green-from-start guards.

Execution amendment (agreed before red): rows 3, 8, and 11 are negative
guards that pass vacuously against the honest empty-body skeleton — the
observed red set is rows 2, 4, 5, 6, 7, 9, 10 (7 failures), with rows 1,
3, 8, 11, 12 green from the start. Forcing all ten rows red would have
required a deliberately-wrong skeleton body, against the 9-L
intentionally-unwired precedent.

### Public API shape

```swift
@MainActor @Observable
final class AlertCenter {

    // Playback-error surface
    var lastError: PlaybackError?
    var lastErrorDetail: String?
    var failedTrackName: String?
    var showFileNotFoundAlert = false
    var skippedInaccessibleNames: [String] = []

    // Batch-operation surfaces
    var skippedDuplicateURLs: [URL] = []
    var skippedImportURLs: [URL] = []
    var skippedUnsupportedURLs: [URL] = []

    // File Info window request (one-shot; ContentView clears after opening)
    var fileInfoTrack: Track?

    // Paywall
    var showPaywall = false
    var paywallDismissedThisSession = false

    /// Clears the playback-error surface (error, detail, failed name,
    /// file-not-found flag, inaccessible-skip list). Batch-operation
    /// lists are cleared by their own alerts' dismiss buttons, not here.
    func clearLastError()

    /// Presents the File Info window request for the given track.
    func presentFileInfo(_ track: Track)

    /// Clears the one-shot File Info request after the window opens.
    func clearFileInfoRequest()

    /// Presents the Pro paywall sheet.
    func presentPaywall()

    nonisolated deinit {}
}
```

### Implementation notes

- Red-phase skeleton precedent: 9-L (`NowPlayingCoordinator` landed with
  its wiring intentionally absent; tests defined the contract).
- C1 is what makes the facade observable-correct: a body reading
  `appState.showPaywall` reaches `alertCenter.showPaywall` through the
  computed forwarder, so Observation registers the store property even
  for views still on `@EnvironmentObject`.
- Doc obligations at green (skill Doc Update Table): `api_reference.md`
  (AppState property/init changes + new type), `module_boundary.md` (new
  state-owning type), `development_guide.md` (project structure),
  `implementation_guide_swift.md` (if examples show alert properties).
  `architecture.md` untouched → HC 5-area audit not triggered.
