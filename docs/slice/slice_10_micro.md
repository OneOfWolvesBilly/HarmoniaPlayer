# Slice 10 Micro-slices Specification

## Purpose

First stage of the v1.1.0 AppState decomposition refactor program (design
authority: `appstate_refactor_plan.md`). The harmonia-dev-workflow skill
forbids slice identifiers, version-roadmap labels, and forward-looking
commentary in `.swift` files and mandates a dedicated retroactive cleanup
slice **before** the refactor begins. This slice performs that cleanup on
every Swift source the refactor will **not** touch, so no file is cleaned
twice.

## Slice 10 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 10-A | HarmoniaPlayer token cleanup (44 files) | — | ✅ |
| 10-B | HarmoniaCore token cleanup (1 file) | — | ✅ |

### Goals

- Every in-scope `.swift` file passes the skill's token self-check with
  only allowed matches remaining.
- Zero behavior change; the full test suite stays green with an unchanged
  test count.

### Out of Scope

- `AppState.swift` + its 4 extensions, the 12 injection-migrating UI
  files, and the test-migration set (all 21 `AppState*Tests` +
  `AppSettingsTests`, `IntegrationTests`, `IAPManagerTests`,
  `MiniPlayerViewTests`) → cleaned inside the refactor stages that
  reorganize them (Slice 12 and later program stages).
- Token sweeps over `.md` docs → not a violation; specs and plans are
  where slice/version history belongs (skill "Where development history
  belongs" table).
- The `v0.1 frozen` **commented-out Pro-gate code blocks** in
  AppState/IntegrationTests/FormatGating → their fate is the Pro tier
  slice's Restore Checklist (`slice_pro_micro_draft.md` Prerequisite 1);
  those files are excluded here anyway.

### Constraints

- Comment/doc-comment edits only; no executable statement may change.
  - **Exception (execution finding, 2026-08-13):** three XCTAssert
    failure-message string literals carry slice tokens
    (`LyricsServiceTests` 1 line, `TrackTests` 2 lines). A failure
    message renders only in test-failure output and changes no runtime
    or test-pass/fail behaviour, but the skill forbids slice IDs in
    string literals too — so these three lines are rewritten, and AC3's
    comment-only inspection treats these message-string-only hunks as
    allowed. No other executable line may change.
- Allowed matches stay: format names (`ID3v2.3`, `ID3v2.4`) and
  programmatic version semantics (`Track.metadataVersion` value docs, EQ
  schema `version` field docs) — minus any slice IDs riding on those
  lines.
- HC commit message must not reference HP slice numbers or tiers (skill
  Commit Format).

### Dependencies

- None. This is the program's first stage; Slices 11 and 12 depend on it.

---

## Slice 10-A: HarmoniaPlayer Token Cleanup ✅

### Goal

Remove forbidden development-history tokens from the 44 HarmoniaPlayer
Swift files outside the refactor's touch set, rewriting comments to
present-tense current behavior.

### Scope (FROZEN as of spec commit)

Scan command per file:

```
grep -rinE "slice [0-9]|[^a-z0-9]9-[a-z]{1,2}[^a-z0-9]|v[0-9]+\.[0-9]" <file>
```

Triage: allowed matches (Constraints above) stay; every other match is
rewritten to current behavior or deleted. `v0.1 frozen` / `Planned for
v0.2` / `Extension point (v0.15)` comments keep only the current-state
half if any is still needed (e.g. `// Pro UI hidden.`).

In-scope files (44):

| Area | Files |
| --- | --- |
| Models (8) | `Track.swift`, `CoreFeatureFlags.swift`, `LyricsPreference.swift`, `LyricsResolution.swift`, `PlaybackState.swift`, `NowPlayingCoordinator.swift`, `EQBandState.swift`, `EQPresets.swift` |
| Services (11) | `CoreFactory.swift`, `CoreServiceProviding.swift`, `HarmoniaCoreProvider.swift`, `LyricsService.swift`, `LyricsPreferenceStore.swift`, `EQService.swift`, `EQSchemaMigrator.swift`, `EQPersistenceStore.swift`, `MPNowPlayingAdapter.swift`, `NowPlayingService.swift`, `TagReaderService.swift` |
| Test fakes (4) | `FakeCoreProvider.swift`, `FakeFileOriginService.swift`, `FakeNowPlayingService.swift`, `FakeTagReaderService.swift` |
| Tests (20) | `CoreFactoryTests`, `EQCoordinatorTests`, `EQPersistenceStoreTests`, `EQPresetsTests`, `EQSchemaMigratorTests`, `EQServiceTests`, `EncodingDetectionTests`, `FakePlaybackServiceTests`, `FakeTagReaderServiceTests`, `FilePlaylistStoreTests`, `LRCStripTests`, `LyricsPreferenceStoreTests`, `LyricsServiceTests`, `NowPlayingCoordinatorTests`, `PlaybackErrorTests`, `PlaybackStateTests`, `PlaylistTests`, `SiblingFilePresenterTests`, `TrackTests`, `ViewPreferencesTests` |
| UITests (1) | `HarmoniaPlayerUITests.swift` |

### Acceptance Criteria

1. AC1: the scan command over all 44 files returns only allowed matches
   (format names, programmatic version semantics without slice IDs).
2. AC2: full ⌘U suite green; `func test` count unchanged from the
   pre-slice count recorded at execution.
3. AC3: `git diff` for this sub-slice touches only comment/doc-comment
   lines (inspection: no diff hunk changes an executable line), except
   the three XCTAssert failure-message string literals listed in
   Constraints, whose hunks change message text only.
4. AC4: app launches and plays one track (smoke check).

### Out of Scope

- Everything listed in the slice-level Out of Scope (refactor-touched
  files) → Slice 12 and later program stages.

### Deferred Backlog

None.

### Files

- HarmoniaPlayer Application Layer / Models: the 8 model files above
- HarmoniaPlayer Services / Integration Layer: the 11 service files above
- Tests: the 4 fakes + 20 test files + 1 UITest file above

### TDD matrix

No new tests — comment-only edits have no behavior a test could exercise.
Verification is AC1–AC4 (scan clean, suite green with unchanged count,
comment-only diff, smoke check).

---

## Slice 10-B: HarmoniaCore Token Cleanup ✅

### Goal

Remove HP-tier/roadmap commentary from the single HarmoniaCore file that
carries forbidden tokens; HC doc comments must describe current adapter
behavior with no HP-version vocabulary.

### Scope (FROZEN as of spec commit)

`apple-swift/Sources/HarmoniaCore/Adapters/AVMetadataTagReaderAdapter.swift`:

- `/// **Extension point (v0.15):** …` → describe the extension point
  without the version label.
- `/// - v0.1 Free: MP3, AAC LC, …` / `/// - v0.2 Pro: FLAC` and the
  related tier-flow sentence → rewrite as a current-behavior list of
  formats this adapter handles (HP tier vocabulary is doubly forbidden in
  HC).
- `ID3v2.3` / `ID3v2.4` / `TDRC` / `TYER` frame-name references stay
  (format names, allowed).

### Acceptance Criteria

1. AC1: the 10-A scan command over this file returns only format-name
   matches.
2. AC2: HarmoniaCore test suite (`swift test` in `apple-swift/`) green,
   count unchanged.
3. AC3: the HC diff touches only comment/doc-comment lines.

### Out of Scope

- Any other HC file → none carry forbidden tokens (verified at spec
  time); if execution finds one, stop and amend this spec first.

### Deferred Backlog

None.

### Files

- HarmoniaCore: `Sources/HarmoniaCore/Adapters/AVMetadataTagReaderAdapter.swift`

### TDD matrix

No new tests — comment-only edits; verification is AC1–AC3.
