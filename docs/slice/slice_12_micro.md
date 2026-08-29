# Slice 12 Micro-slices Specification

## Purpose

Second stage of the v1.1.0 AppState decomposition refactor program
(design authority: `appstate_refactor_plan.md`, language-mode plan §6.3).
Surfaces all Swift-6-level concurrency diagnostics as warnings **now**,
so the store-extraction slices burn the debt down scope-by-scope instead
of hitting one cliff at the final language-mode flip. Program constraint
C8 (verified): `SWIFT_STRICT_CONCURRENCY = complete` under the Swift 5
language mode produces warnings, never errors.

## Slice 12 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 12-A | Enable complete strict-concurrency checking + record warning baseline | — | ✅ |

### Goals

- Swift-6-level concurrency diagnostics visible on every build of the
  app, test, and UITest targets.
- A committed per-file warning baseline that later program stages
  subtract from, reaching zero at the language-mode close-out stage.

### Out of Scope

- Fixing any surfaced warning → the store-extraction stages (each clears
  the warnings of the code it moves) and the language-mode close-out
  stage (residuals).
- Switching `SWIFT_VERSION` to 6.0 → the program's close-out stage.

### Constraints

- Build-settings-only change; no source file is touched.
- `SWIFT_VERSION = 5.0` target overrides stay in place.

### Dependencies

- Slice 10 (program order; keeps cleanup and settings changes in
  separate, reviewable slices).

---

## Slice 12-A: Enable Complete Checking + Record Baseline ✅

### Goal

Turn on `SWIFT_STRICT_CONCURRENCY = complete` for all three targets and
freeze the resulting warning inventory as the program's burn-down
baseline.

### Scope (FROZEN as of spec commit)

- `HarmoniaPlayer.xcodeproj/project.pbxproj`: add
  `SWIFT_STRICT_CONCURRENCY = complete;` to all six target-level build
  configurations (app, tests, UITests × Debug/Release).
- Build once; record the warning inventory in the Baseline table below
  (file → warning count → dominant diagnostic kind).
- `docs/development_guide.md` line-4 build-setting summary gains the
  strict-concurrency note (the same sentence flips at the close-out
  stage).

### Acceptance Criteria

1. AC1: `project.pbxproj` contains exactly six
   `SWIFT_STRICT_CONCURRENCY = complete;` entries, one per target-level
   configuration.
2. AC2: the six `SWIFT_VERSION = 5.0` target overrides are unchanged.
3. AC3: the build succeeds with zero **errors** (warnings expected). An
   error means constraint C8 was violated → stop and re-investigate
   before any further step.
4. AC4: full ⌘U suite green; test count unchanged.
5. AC5: the Baseline table below is filled in and committed.
6. AC6: `development_guide.md` line 4 mentions complete
   strict-concurrency checking.

### Out of Scope

- Warning fixes → store-extraction stages + close-out stage (see
  slice-level Out of Scope).

### Deferred Backlog

None.

### Files

- Build settings: `App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj/project.pbxproj`
- Docs: `docs/development_guide.md`, `docs/slice/slice_12_micro.md`
  (baseline table)

### TDD matrix

No new tests — build-settings-only change; no behavior a test could
exercise. Verification is AC1–AC6.

### Baseline (filled at execution)

Recorded 2026-08-26 from a full Debug build of all three targets
(deduplicated diagnostics; app 32 + tests 466 + UITests 50 = 548 total).
The `appintentsmetadataprocessor` "No AppIntents.framework dependency
found" build-log line is pre-existing toolchain output, not a Swift
diagnostic, and is excluded.

**Slice 13-A re-measurement (2026-08-29).** The AlertCenter extraction
moved the 11 alert-surface `@Published` properties and their presentation
methods out of `AppState.swift`, which carries no row in this baseline —
the moved code had zero baseline warnings, so no rows retire. Every file
the slice touched was rebuilt and re-measured: `AlertCenter.swift`,
`AlertCenterTests.swift`, `AppState.swift`, `ContentView.swift`,
`PaywallView.swift`, and `HarmoniaPlayerCommands.swift` build with zero
warnings; `PlaylistView.swift` (16), `HarmoniaPlayerApp.swift` (14), and
`AppStateTests.swift` (2) keep their baseline counts and dominant kinds
unchanged. The tables below therefore stand as recorded.

**App target — 32**

| File | Warnings | Dominant kind |
| --- | --- | --- |
| `HarmoniaPlayer/Shared/Views/PlaylistView.swift` | 16 | non-Sendable `KeyPath<Track, _>` crossing actor boundary (16/16) |
| `HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift` | 14 | main-actor API referenced from nonisolated / Sendable-closure context (14/14) |
| `HarmoniaPlayer/macOS/Free/AppDelegate.swift` | 2 | main-actor API referenced from nonisolated / Sendable-closure context (2/2) |

**Test target — 466**

| File | Warnings | Dominant kind |
| --- | --- | --- |
| `HarmoniaPlayerTests/SharedTests/PlaylistTests.swift` | 51 | main-actor isolation violation (45/51) |
| `HarmoniaPlayerTests/SharedTests/LyricsServiceTests.swift` | 45 | main-actor isolation violation (45/45) |
| `HarmoniaPlayerTests/SharedTests/CoreFeatureFlagsTests.swift` | 44 | main-actor isolation violation (44/44) |
| `HarmoniaPlayerTests/SharedTests/CoreFactoryTests.swift` | 34 | main-actor isolation violation (23/34) |
| `HarmoniaPlayerTests/SharedTests/AppStateReplayGainTests.swift` | 20 | main-actor isolation violation (8/20) |
| `HarmoniaPlayerTests/SharedTests/AppStatePersistenceTests.swift` | 20 | main-actor isolation violation (8/20) |
| `HarmoniaPlayerTests/SharedTests/FileOriginServiceTests.swift` | 18 | sending non-Sendable value across isolation (9/18) |
| `HarmoniaPlayerTests/SharedTests/LyricsPreferenceStoreTests.swift` | 17 | main-actor isolation violation (16/17) |
| `HarmoniaPlayerTests/SharedTests/EQCoordinatorTests.swift` | 17 | main-actor isolation violation (7/17) |
| `HarmoniaPlayerTests/SharedTests/AppStateVolumeTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/AppStateTrackSelectionTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/AppStatePollingTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/AppStatePlaybackTrackTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/AppStatePlaybackStateTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/AppStatePlaybackControlTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/AppSettingsTests.swift` | 14 | main-actor isolation violation (6/14) |
| `HarmoniaPlayerTests/SharedTests/EncodingDetectionTests.swift` | 12 | main-actor isolation violation (12/12) |
| `HarmoniaPlayerTests/SharedTests/EQServiceTests.swift` | 12 | main-actor isolation violation (7/12) |
| `HarmoniaPlayerTests/SharedTests/LRCStripTests.swift` | 11 | main-actor isolation violation (11/11) |
| `HarmoniaPlayerTests/SharedTests/EQPresetsTests.swift` | 11 | main-actor isolation violation (11/11) |
| `HarmoniaPlayerTests/SharedTests/EQSchemaMigratorTests.swift` | 10 | main-actor isolation violation (10/10) |
| `HarmoniaPlayerTests/SharedTests/EQPersistenceStoreTests.swift` | 10 | main-actor isolation violation (10/10) |
| `HarmoniaPlayerTests/SharedTests/AppStateFormatGatingTests.swift` | 8 | main-actor isolation violation (3/8) |
| `HarmoniaPlayerTests/SharedTests/FileDropServiceTests.swift` | 7 | main-actor isolation violation (7/7) |
| `HarmoniaPlayerTests/SharedTests/SiblingFilePresenterTests.swift` | 5 | main-actor isolation violation (5/5) |
| `HarmoniaPlayerTests/SharedTests/ErrorReportServiceTests.swift` | 4 | main-actor isolation violation (4/4) |
| `HarmoniaPlayerTests/SharedTests/RepeatModeTests.swift` | 2 | main-actor isolation violation (2/2) |
| `HarmoniaPlayerTests/SharedTests/MiniPlayerViewTests.swift` | 2 | main-actor isolation violation (2/2) |
| `HarmoniaPlayerTests/SharedTests/M3U8ServiceTests.swift` | 2 | main-actor isolation violation (2/2) |
| `HarmoniaPlayerTests/SharedTests/AppStateUndoTests.swift` | 2 | main-actor isolation violation (2/2) |
| `HarmoniaPlayerTests/SharedTests/AppStateTests.swift` | 2 | main-actor isolation violation (2/2) |
| `HarmoniaPlayerTests/FakeInfrastructure/FakeNowPlayingService.swift` | 1 | default initializer both nonisolated and main-actor-isolated (1/1) |
| `HarmoniaPlayerTests/FakeInfrastructure/FakeCoreProvider.swift` | 1 | main-actor default value in nonisolated context (1/1) |

**UITest target — 50**

| File | Warnings | Dominant kind |
| --- | --- | --- |
| `HarmoniaPlayerUITests/HarmoniaPlayerUITests.swift` | 50 | main-actor isolation violation (49/50) |
