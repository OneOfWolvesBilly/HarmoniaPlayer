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
| 12-A | Enable complete strict-concurrency checking + record warning baseline | — | ⬜ |

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

## Slice 12-A: Enable Complete Checking + Record Baseline ⬜

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

| File | Warnings | Dominant kind |
| --- | --- | --- |
| _(recorded at execution)_ | | |
