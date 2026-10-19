# Slice 16 Micro-slices Specification

## Purpose

Fifth stage of the v1.1.0 AppState decomposition refactor program (design
authority: `appstate_refactor_plan.md`). Extracts the third
`@MainActor @Observable` feature store — `SettingsStore` — behind the
AppState strangler facade, following the structural templates of Slice 13
(facade forwarders for members with surviving internal readers) and
Slice 14 (no forwarder where no reader survives). This is the first
extraction that owns persistence keys (plan §6.1 persistence split) and
the first to replace AppState Combine sinks with a store-side `didSet`
and an upward-notification closure wired by the composition root
(plan §5, constraint C6).

## Slice 16 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 16-A | Extract `SettingsStore` + persistence split + `@Environment` view migration + test migration | — | ✅ |

### Goals

- Program plan §3 rows 14–18 (`allowDuplicateTracks`, `selectedLanguage`,
  `replayGainMode`, `viewPreferences`, `isProUnlocked`) plus
  `featureFlags`, `languageBundle`, `purchasePro()`, and
  `refreshEntitlements()` live in `SettingsStore`, which also takes
  ownership of `iapManager` and the three settings persistence keys.
- Each settings key is persisted by the store itself on change; the
  AppState `$replayGainMode` (×2) and `$selectedLanguage` Combine sinks are
  removed.
- A `replayGainMode` change reaches AppState's
  `applyReplayGainVolume(requiresActivePlayback:)` through the
  `onReplayGainModeChanged` closure wired by the composition root.
- `showPaywallIfNeeded()`'s tier check moves to `SettingsStore`; paywall
  presentation reaches `AlertCenter` through the `onPaywallRequested`
  closure wired by the composition root (BL-13A-02 resolved).
- `SettingsView` and `PaywallView` observe `SettingsStore` via
  `@Environment(SettingsStore.self)` and no longer depend on AppState.
- Tests whose real SUT is the settings state move to `SettingsStoreTests`
  (unit-test-core Rule 1 placement).

### Out of Scope

- `$repeatMode` / `$isShuffled` persistence sinks, the formal
  `$currentTrack` sink replacement, and the `eqEnabled` mirror deletion →
  PlaybackController stage (plan §5).
- Moving the `onReplayGainModeChanged` target from AppState to
  PlaybackController → PlaybackController stage (plan §5).
- Migrating the other `languageBundle` readers (`L()` helpers in
  `ContentView`, `PlayerView`, `LyricsPanel`, `PlaylistView`,
  `MiniPlayerView`, `FileInfoView`, `EQView`, and
  `HarmoniaPlayerCommands`) → each view's own extraction stage; the
  forwarder is removed by the last of them or at the language-mode
  close-out. `languageBundle` is fixed for the process lifetime, so
  reading it through the forwarder has no invalidation cost.
- Migrating the `isProUnlocked` view readers in `PlaylistView` and
  `MiniPlayerView` → PlaylistCollection / PlaybackController stages.
- Pro gating as an application service (dedicated gate type,
  per-edition Strategy, command/query split of `showPaywallIfNeeded`) →
  BL-16A-01, decided in the Free/Pro isolation discussion that follows
  this slice.
- Enabling any Pro feature — the paywall stays hidden; commented-out Pro
  call sites (`HarmoniaPlayerCommands`, `AppState+Playback`,
  `AppState+Navigation`, `HarmoniaPlayerApp`) are left untouched.
- BL-13A-01 → PlaylistCollection stage (unchanged target).
- `architecture.md` §6.2 DI excerpt drift (it already lists the lyrics
  dependencies on AppState; after this slice it also still shows
  `iapManager` and a local `featureFlags` on AppState) → deferred to the
  language-mode close-out stage's final doc realignment (plan §7.5).
  Not touched here → HC 5-area audit not triggered.
- The duplicated `"hp.selectedLanguage"` literal in
  `HarmoniaPlayerApp.init` (AppleLanguages bootstrap, runs before
  AppState exists) → unchanged.
- Any change to `EQCoordinator` / `NowPlayingCoordinator` → not in the
  program at all (plan §0).

### Constraints

- Program constraints C1–C6 (plan §4) govern the observation mechanics;
  every scene hosting a migrated view must inject the store or the app
  crashes at first read (C3 — audit result: main window + Settings).
- Dependency direction stays as plan §2 declares:
  `SettingsStore ← iapManager, userDefaults`. The store holds no
  reference to AlertCenter or AppState; lateral and upward effects go
  through closures wired by the composition root (plan §2/§5, the
  `NowPlayingCoordinator` precedent).
- Behaviour is preserved, including existing quirks: `languageBundle`
  resolves `"en"` when `hp.selectedLanguage` has never been written while
  `selectedLanguage` defaults to `"system"`; a `replayGainMode`
  assignment notifies even when the value is unchanged (today's
  `@Published` sink semantics).
- New store code builds warning-free under the Slice 12 baseline; this
  slice retires the baseline rows of the code it moves and re-measures
  every file it touches (plan §6.0 step 5).
- TDD red-green: the failing tests run against an intentionally-unwired
  skeleton (the 9-L precedent) and the red set is reported uncommitted;
  "是請執行" gates the green phase; red, green, and docs land as one
  atomic code commit.

### Dependencies

- Slice 13 (AlertCenter — paywall presentation target; facade-forwarder
  template) and Slice 14 (no-forwarder template).
- Slice 12 (baseline must exist for the warning-clearing obligation).

---

## Slice 16-A: Extract SettingsStore ✅

### Goal

Move the settings, tier, and localization surface out of AppState into a
dedicated `@MainActor @Observable` store that persists its own keys,
notify ReplayGain changes and paywall requests through root-wired
closures, migrate the two settings views, and keep facade forwarders
only for members that still have internal readers.

### Scope (FROZEN as of spec commit)

**New store** `Shared/Models/SettingsStore.swift` — see Public API shape.
Deliberate choices frozen with it:

- **Persistence split (plan §6.1).** The store owns the keys
  `hp.allowDuplicateTracks`, `hp.selectedLanguage`, `hp.replayGainMode`.
  `init` restores them from the injected `UserDefaults` (assignments
  inside `init` do not run `didSet`, so restore neither re-persists nor
  notifies); each property's `didSet` writes its own key. The store has
  no save method: every key is already persisted at change time, so the
  root's `willTerminate` save has nothing to delegate for this store.
  One observable difference, accepted: `allowDuplicateTracks` had no
  change sink and was written only by `saveState()`; it now persists at
  change time like the other two keys.
- **`languageBundle`** is resolved once in `init` from the persisted
  `hp.selectedLanguage` (`?? "en"`; `"system"` or a missing `.lproj` →
  `Bundle.main`) — the logic moves unchanged from AppState init Step 9.
- **Tier state.** `isProUnlocked` and `featureFlags` are
  `private(set)`, initialised from `iapManager` and refreshed by
  `purchasePro()` / `refreshEntitlements()` exactly as AppState does
  today. `featureFlags` changing after launch does not rebuild services
  (unchanged behaviour).
- **`onReplayGainModeChanged: ((ReplayGainMode) -> Void)?`** — called
  from `replayGainMode`'s `didSet` after persisting. `@ObservationIgnored`.
- **`showPaywallIfNeeded()`** — the tier check moves here (the policy
  lives with the data it reads). When `isProUnlocked == false` it calls
  `onPaywallRequested` and returns `true`; otherwise returns `false`
  without calling it. Signature and `@discardableResult` unchanged.
  `onPaywallRequested: (() -> Void)?` is `@ObservationIgnored`. This is
  the BL-13A-02 seam decision: tier policy in `SettingsStore`,
  presentation in `AlertCenter`, joined by a root-wired closure — no
  store-to-store dependency.
- `iapManager` and `userDefaults` are `private let`.

**AppState changes:**

- `let settingsStore: SettingsStore`, constructed right after
  `alertCenter` (Step 0b) from the injected `iapManager` and
  `userDefaults`; Step 3 builds `CoreFactory` from
  `settingsStore.featureFlags`.
- Deleted: `private let iapManager`, `private(set) var featureFlags`, the
  five `@Published` properties of rows 14–18, `let languageBundle`,
  `purchasePro()`, `refreshEntitlements()`, init Step 6 (Pro unlock
  exposure) and Step 9 (bundle resolution), the `$replayGainMode` →
  `applyReplayGainVolume` sink (Step 11), and the `$replayGainMode` /
  `$selectedLanguage` → `saveState()` sinks (Step 12). The
  `PersistenceKey` entries `allowDuplicates`, `selectedLanguage`,
  `replayGainMode` move to the store; `saveState()` / `restoreState()`
  stop writing / reading them. The `$repeatMode` / `$isShuffled` sinks
  stay.
- New wiring step (after every stored property is initialised, before
  the NowPlaying coordinator step):
  `settingsStore.onReplayGainModeChanged` →
  `Task { @MainActor in await applyReplayGainVolume(requiresActivePlayback: true) }`
  (`[weak self]`), and `settingsStore.onPaywallRequested` →
  `alertCenter.presentPaywall()`.
- **Facade verdicts, per member** (plan §6.0 step 7 applied member by
  member, by surviving internal/view readers after this slice):

  | Member | Surviving reader | Facade |
  | --- | --- | --- |
  | `allowDuplicateTracks` | `AppState+Playlist` `load(urls:)` duplicate check | get + set forwarder |
  | `replayGainMode` | `AppState+Playback` `applyReplayGainVolume`; `AppStateReplayGainTests` writes | get + set forwarder |
  | `isProUnlocked` | `PlaylistView` (×3) and `MiniPlayerView` (×1) format-gating strikethrough | get-only forwarder (was `private(set)`) |
  | `languageBundle` | `L()` in 7 views + `HarmoniaPlayerCommands` | get-only forwarder |
  | `showPaywallIfNeeded()` | the `appState.showPaywallIfNeeded()` entry point used by the commented-out Pro call sites | method forwarder → `settingsStore.showPaywallIfNeeded()` |
  | `featureFlags` | none (commented-out lines only) | none — tests read `settingsStore.featureFlags` |
  | `viewPreferences` | none (no view reads it) | none |
  | `selectedLanguage` | `SettingsView` only (migrated) | none |
  | `purchasePro()` / `refreshEntitlements()` | `PaywallView` only (migrated) | none |

- `@Published` count drops by exactly 5 (rows 14–18).

**View changes:**

| File | Change |
| --- | --- |
| `HarmoniaPlayerApp.swift` | main window scene adds `.environment(appState.settingsStore)` (PaywallView is presented as a sheet from ContentView); Settings scene adds `.environment(appState.settingsStore)` and drops `.environmentObject(appState)` (no reader remains in its subtree). C3 audit result: the Mini Player, Equalizer, and File Info subtrees read settings state only through the facade forwarders and take no injection |
| `SettingsView.swift` | `@Environment(SettingsStore.self)` + `@Bindable` for the duplicates toggle, ReplayGain picker, and language picker; `.onChange(of:)` and `L()` read the store; `@EnvironmentObject appState` removed; header rewritten |
| `PaywallView.swift` | `@Environment(SettingsStore.self)`; `isProUnlocked` reads, `purchasePro()`, `refreshEntitlements()`, and `L()` retarget the store; `@EnvironmentObject appState` removed; header rewritten |

Other source touched: `AppState+Playback.swift` (the
`applyReplayGainVolume` doc comment's `$replayGainMode` sink narrative
becomes the closure), `ViewPreferences.swift` (doc comments naming
`AppState.viewPreferences` / `appState.viewPreferences` retarget the
store).

### Acceptance Criteria

1. AC1: `Shared/Models/SettingsStore.swift` exists as
   `@MainActor @Observable final class` with the members of the Public
   API shape, including `nonisolated deinit {}`.
2. AC2: `grep -c "@Published" AppState.swift` drops by exactly 5;
   `grep -n '\$replayGainMode\|\$selectedLanguage' AppState.swift` has no
   match; the `$repeatMode` / `$isShuffled` sinks are still present;
   `iapManager`, `featureFlags`, `purchasePro`, `refreshEntitlements`,
   `viewPreferences`, `selectedLanguage` appear in `AppState.swift` only
   as `settingsStore` construction / wiring lines and doc text.
3. AC3: every TDD-matrix test passes in the file its Test File Decision
   names; `AppSettingsTests.swift` no longer exists.
4. AC4: full ⌘U suite green; final unit-test count = pre-slice count
   + 11 (12 new rows − 1 deleted row; moved rows change file, never
   disappear). UITests unchanged (9). Pre-slice count re-measured at
   spec time on the 6ee1a90 tree: 507 passed / 5 skipped / 0 failed
   (+ 9 UITests) → target 518 passed / 5 skipped.
5. AC5: `slice_12_micro.md` baseline — the `AppSettingsTests.swift` row
   (14) retires with the file (the first retired baseline row) and the
   test-target total drops accordingly; `AppStateTests.swift` (2),
   `AppStatePersistenceTests.swift` (20), and
   `AppStateReplayGainTests.swift` (20) are re-measured and their rows
   updated if the counts change; `HarmoniaPlayerApp.swift` keeps its 14;
   `SettingsStore.swift`, `SettingsStoreTests.swift`, and every other
   touched file without a row build with zero warnings. Table update +
   Slice 16-A re-measurement note land with the close-out.
6. AC6 (manual, binary): each flow behaves as before —
   (a) Settings → "Allow duplicate tracks" on → dropping an
   already-listed file adds it; off → it is skipped with the duplicate
   alert; the setting survives a relaunch;
   (b) ReplayGain picker switched Off → Track while a tagged track plays
   changes the volume immediately, without restarting the track; switched
   while stopped, nothing is heard until play; the mode survives a
   relaunch;
   (c) language picker → restart prompt → after "Restart Now" the UI and
   system menus are in the chosen language and the picker shows it;
   "Later" keeps the current language until the next launch;
   (d) localized strings are correct in the main window, Mini Player,
   Equalizer, File Info, Settings, and the menu bar (the forwarder path);
   (e) main window, Mini Player, Equalizer, File Info, and Settings
   scenes all open without a missing-injection crash — Settings first.
   The paywall has no reachable entry point while Pro UI is hidden; its
   purchase path is covered by the TDD matrix only.

### Out of Scope

- See slice-level Out of Scope.

### Deferred Backlog

1. BL-13A-02 — **resolved here**: tier check in
   `SettingsStore.showPaywallIfNeeded()`, presentation via the root-wired
   `onPaywallRequested` → `AlertCenter.presentPaywall()`; AppState keeps
   a method forwarder until the entry point's callers migrate.
2. BL-16A-01 — Pro gating as an application-layer service: a dedicated
   gate type depending on an entitlement port and a presentation port
   (the `onPaywallRequested` closure lifts into it), per-edition Strategy
   for Free vs Pro builds, and a command/query split of today's
   `showPaywallIfNeeded() -> Bool`; callers (Commands upgrade menu,
   playback format gating) bind to it. Target: the Free/Pro isolation
   discussion that follows this slice.

### Files

- HarmoniaPlayer Application Layer:
  - add `Shared/Models/SettingsStore.swift`
  - modify `Shared/Models/AppState.swift`
  - modify `Shared/Models/AppState+Playback.swift` (doc comment only)
  - modify `Shared/Models/ViewPreferences.swift` (doc comments only)
  - `Shared/Models/AppState+Playlist.swift` / `+Navigation.swift` /
    `+M3U8.swift`: no expected change (forwarders keep them compiling);
    touched only if the compiler disagrees
- UI: modify `SettingsView.swift`, `PaywallView.swift`,
  `HarmoniaPlayerApp.swift`
- Tests:
  - add `SharedTests/SettingsStoreTests.swift`
  - delete `SharedTests/AppSettingsTests.swift` (rows move)
  - modify `AppStateTests.swift`, `AppStatePlayerlistTests.swift`,
    `AppStatePersistenceTests.swift`, `AppStateReplayGainTests.swift`,
    `IAPManagerTests.swift`
  - modify `FakeInfrastructure/MockIAPManager.swift` (add
    `entitlementAfterRefresh: Bool?` — when set, `refreshEntitlements()`
    applies it to `isProUnlocked`; `nil` keeps today's record-only stub)
  - the test moves are made in the red phase and land with the single
    code commit
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change needed
  (`PBXFileSystemSynchronizedRootGroup`, 13-A execution amendment)
- Docs at green: `api_reference.md`, `module_boundary.md`,
  `development_guide.md`, `implementation_guide_swift.md`
- Docs at close-out: `slice_12_micro.md` (retired row + re-measurement
  note), this spec (status ticks), `HarmoniaPlayer_development_plan.md`
  (slice table tick)

### TDD matrix

`SettingsStoreTests` builds the SUT directly as
`SettingsStore(iapManager: MockIAPManager(…), userDefaults: testDefaults)`
with an isolated suite; relaunch is simulated by constructing a second
store on the same suite. Moved rows drop their `testAppState_` prefix and
no longer construct an AppState.

| # | Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- | --- |
| 1 | `testAllowDuplicateTracks_DefaultIsFalse` | empty defaults | init | `allowDuplicateTracks == false` | Move from `AppSettingsTests.swift` → New `SettingsStoreTests.swift` |
| 2 | `testViewPreferences_DefaultMatchesDefaultPreferences` | empty defaults | init | `viewPreferences == .defaultPreferences` | Move from `AppStateTests.swift` (`testAppState_InitialViewPreferences_MatchesDefault`) → `SettingsStoreTests.swift` |
| 3 | `testReplayGainMode_DefaultIsOff` | empty defaults | init | `replayGainMode == .off` | Move from `AppStateReplayGainTests.swift` → `SettingsStoreTests.swift` |
| 4 | `testAllowDuplicateTracks_SurvivesRelaunch` | store 1 | set `allowDuplicateTracks = true`; build store 2 on the same suite | store 2 reads `true` | Move from `AppStatePersistenceTests.swift` (`testSaveAndRestore_AllowDuplicates_Survives`; no `saveState()` call) → `SettingsStoreTests.swift` |
| 5 | `testReplayGainMode_PersistsOnChange` | fresh store | set `.album` | suite's `hp.replayGainMode == "album"` with no save call | Move from `AppStatePersistenceTests.swift` (`testReplayGainMode_AutoSaves_ViaCombineSink`) → `SettingsStoreTests.swift` |
| 6 | `testReplayGainMode_SurvivesRelaunch` | store 1 set `.album` | build store 2 | store 2 reads `.album` | Move from `AppStateReplayGainTests.swift` (`testReplayGainMode_Persisted`) → `SettingsStoreTests.swift` |
| 7 | `testInit_FreeIAP_TierIsFree` | `MockIAPManager(isProUnlocked: false)` | init | `isProUnlocked == false`; `featureFlags.supportsFLAC/DSD == false` | Move from `AppStateTests.swift` (`testFeatureFlags_ConsistentWithIAP_Free`) → `SettingsStoreTests.swift` |
| 8 | `testInit_ProIAP_TierIsPro` | `MockIAPManager(isProUnlocked: true)` | init | `isProUnlocked == true`; `featureFlags.supportsFLAC/DSD == true` | Move from `AppStateTests.swift` (`testFeatureFlags_ConsistentWithIAP_Pro`) → `SettingsStoreTests.swift` |
| 9 | `testPurchasePro_Success_UnlocksProAndUpdatesFlags` | Free mock, `purchaseResult = .success` | `purchasePro()` | purchase called once; `isProUnlocked == true`; `featureFlags.supportsFLAC == true` | Move from `IAPManagerTests.swift` (`testPurchasePro_UpdatesFeatureFlags`) → `SettingsStoreTests.swift` |
| 10 | `testSelectedLanguage_PersistsOnChange` | fresh store | set `"ja"` | suite's `hp.selectedLanguage == "ja"` | New `SettingsStoreTests.swift` |
| 11 | `testInit_RestoresPersistedSettings` | suite pre-seeded: duplicates `true`, language `"zh-Hant"`, ReplayGain `"track"` | init | the three properties read back the seeded values | New `SettingsStoreTests.swift` |
| 12 | `testInit_InvalidReplayGainRaw_KeepsOff` | suite `hp.replayGainMode = "bogus"` | init | `replayGainMode == .off` | New `SettingsStoreTests.swift` |
| 13 | `testReplayGainModeChange_NotifiesClosure` | closure recorder assigned | set `.track` | closure called once with `.track` | New `SettingsStoreTests.swift` |
| 14 | `testPurchasePro_Failure_ThrowsAndStaysFree` | Free mock, default `.failure(.notAvailable)` | `purchasePro()` | throws; `isProUnlocked == false`; `featureFlags.supportsFLAC == false` | New `SettingsStoreTests.swift` |
| 15 | `testRefreshEntitlements_RereadsIAPState` | Free mock, `entitlementAfterRefresh = true` | `refreshEntitlements()` | refresh called once; `isProUnlocked == true`; `featureFlags.supportsFLAC == true` | New `SettingsStoreTests.swift` (+ `MockIAPManager.swift` extension) |
| 16 | `testLanguageBundle_PersistedLanguage_ResolvesLproj` | suite language `"ja"` | init | `languageBundle.bundleURL.lastPathComponent == "ja.lproj"` | New `SettingsStoreTests.swift` |
| 17 | `testLanguageBundle_NoPersistedLanguage_ResolvesEnglish` | empty suite | init | `languageBundle.bundleURL.lastPathComponent == "en.lproj"` | New `SettingsStoreTests.swift` |
| 18 | `testLanguageBundle_System_UsesMainBundle` | suite language `"system"` | init | `languageBundle == .main` | New `SettingsStoreTests.swift` |
| 19 | `testShowPaywallIfNeeded_Free_RequestsAndReturnsTrue` | Free mock, request recorder | `showPaywallIfNeeded()` | returns `true`; `onPaywallRequested` called once | New `SettingsStoreTests.swift` |
| 20 | `testShowPaywallIfNeeded_Pro_NoRequestReturnsFalse` | Pro mock, request recorder | `showPaywallIfNeeded()` | returns `false`; recorder not called | New `SettingsStoreTests.swift` |
| 21 | `testInit_SettingsStoreRestoresFromInjectedDefaults` | suite pre-seeded `hp.replayGainMode = "album"` | `AppState(…, userDefaults: suite)` | `appState.settingsStore.replayGainMode == .album` (root passes its `UserDefaults` to the store) | Extend `AppStateTests.swift` |
| 22 | `testLoad_DuplicateURL_DefaultBehaviour_IsSkipped` | default settings | `load` same URL twice | 1 track; 1 skipped duplicate | Move from `AppSettingsTests.swift` → Extend `AppStatePlayerlistTests.swift` (SUT is `load(urls:)`) |
| 23 | `testLoad_DuplicateURL_WhenAllowed_IsAdded` | `allowDuplicateTracks = true` (forwarder) | `load` same URL twice | 2 tracks; no skipped duplicate | Move from `AppSettingsTests.swift` → Extend `AppStatePlayerlistTests.swift` |
| 24 | `testShowPaywallIfNeeded_Free_PresentsAndReturnsTrue` / `…_Pro_NoopReturnsFalse` | AppState Free / Pro | `appState.showPaywallIfNeeded()` | unchanged assertions on the return value and `alertCenter.showPaywall` — end-to-end guard for the forwarder + `onPaywallRequested` root wiring | Existing `AppStateTests.swift`, unchanged (final home of the rows moved from `IAPManagerTests` in Slice 13) |
| 25 | (regression, no new test) | playing / stopped track | switch `replayGainMode` | `testReplayGain_ModeSwitch_DuringPlayback_AppliesImmediately` / `…_WhenStopped_DoesNotCallSetVolume` stay green unchanged — end-to-end guard for the `onReplayGainModeChanged` root wiring | Existing `AppStateReplayGainTests.swift`, unchanged |

Deleted: `AppStateTests.testAppState_ViewPreferences_IsMutable` — it
asserts only that a stored `var` is writable (unit-test-core Smell 2);
it has no counterpart in `SettingsStoreTests`.

Retargeted at green (no row change): `AppStateTests`
`testInit_FreeUser_WiresDependenciesCorrectly` /
`testInit_ProUser_WiresDependenciesCorrectly` read
`appState.settingsStore.featureFlags` once the AppState `featureFlags`
member is deleted; their `isProUnlocked` reads stay on the forwarder.

Count: rows 10–21 are new (12); one row is deleted → net +11 (AC4).

Red phase — the skeleton holds every property at its default
(`isProUnlocked == false`, Free `featureFlags`, `languageBundle ==
.main`), runs no `didSet` logic, restores nothing, and has empty method
bodies (`showPaywallIfNeeded()` returns `false`); AppState constructs it
but keeps its own settings members until green:

- Expected red (14): rows 4, 5, 6, 8, 9, 10, 11, 13, 14, 15, 16, 17, 19, 21.
- Green from the start (4): rows 1, 2, 3, 7 — default-value guards.
- Negative guards, vacuously green against the honest empty skeleton (3):
  rows 12, 18, 20 (13-A amendment precedent — forcing them red would
  need a deliberately-wrong skeleton body).
- Green throughout (moved / existing AppState rows): 22–25.

Execution amendments (recorded at close-out):

- The observed red set matched the prediction row for row (14 red,
  4 green-from-start, 3 negative guards). Green: 518 passed / 5 skipped /
  0 failed, exactly pre-slice + 11; UITests 9 green.
- The `init`-restore claim holds only with an ordering constraint,
  verified empirically: on an `@Observable` class an `init` assignment
  made after every stored property is initialised runs the setter and
  its `didSet`; only assignments made while `self` is still being
  initialised go through the macro's init accessors and skip observers.
  `SettingsStore.init` therefore performs the three restore assignments
  first, before the stored properties that have no default, and documents
  the constraint in its doc comment.
- Warning re-measurement used a clean build of the pre-slice tree with an
  identical counting method; the touched baseline files measure the same
  before and after, so AC5 is met by the `AppSettingsTests.swift` row
  retirement alone.

### Public API shape

```swift
@MainActor @Observable
final class SettingsStore {

    // Persisted settings — each didSet writes its own key
    var allowDuplicateTracks = false          // hp.allowDuplicateTracks
    var selectedLanguage = "system"           // hp.selectedLanguage
    var replayGainMode: ReplayGainMode = .off // hp.replayGainMode; notifies

    // In-memory UI layout preferences (not persisted)
    var viewPreferences: ViewPreferences = .defaultPreferences

    // Tier state derived from the IAP manager
    private(set) var isProUnlocked: Bool
    private(set) var featureFlags: CoreFeatureFlags

    // UI string bundle, fixed at launch from the persisted language
    let languageBundle: Bundle

    // Root-wired notifications
    @ObservationIgnored var onReplayGainModeChanged: ((ReplayGainMode) -> Void)?
    @ObservationIgnored var onPaywallRequested: (() -> Void)?

    init(iapManager: IAPManager, userDefaults: UserDefaults)

    /// Runs the Pro purchase flow; refreshes `isProUnlocked` and
    /// `featureFlags` on success. Throws `IAPError` on failure or
    /// cancellation.
    func purchasePro() async throws

    /// Re-verifies entitlements with the IAP manager, then refreshes
    /// `isProUnlocked` and `featureFlags`.
    func refreshEntitlements() async

    /// Free tier: requests the paywall via `onPaywallRequested` and
    /// returns `true`. Pro tier: returns `false` without requesting.
    @discardableResult
    func showPaywallIfNeeded() -> Bool

    nonisolated deinit {}
}
```

### Implementation notes

- Red-phase skeleton precedent: 9-L / 13-A / 14-A.
- `didSet` on `@Observable` stored properties is supported by the macro;
  `init` assignments go through the macro's init accessors and do not run
  observers — restore therefore neither re-persists nor fires
  `onReplayGainModeChanged`. Row 11 plus rows 4 and 6 pin the restore
  side; row 13 pins the notify side.
- The ReplayGain closure keeps today's asynchronous hop
  (`Task { @MainActor in … }`), so the existing mode-switch rows (row 25)
  keep their timing assumptions.
- C1 keeps un-migrated views correct: a body reading
  `appState.isProUnlocked` reaches `settingsStore.isProUnlocked` through
  the computed forwarder, so Observation registers the store property
  even for views still on `@EnvironmentObject`.
- Token discipline: the moved sections get clean doc comments; the
  rewritten `SettingsView` / `PaywallView` headers and the
  `AppState+Playback` ReplayGain doc comment drop stale narrative;
  untouched regions keep their existing tokens for the slice that moves
  them. `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` on added lines before
  each commit.
- Doc obligations at green (skill Doc Update Table, full line-by-line
  read): `api_reference.md` (new type; AppState property/method/init
  changes; persistence-key table ownership), `module_boundary.md` (new
  state-owning type), `development_guide.md` (project structure, wiring
  example, deinit inventory six → seven), `implementation_guide_swift.md`
  (examples showing settings properties, `purchasePro`, or AppState
  init). `architecture.md` untouched → HC 5-area audit not triggered
  (drift recorded in Out of Scope).
