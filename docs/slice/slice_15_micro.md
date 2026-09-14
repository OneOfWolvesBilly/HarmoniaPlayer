# Slice 15 Micro-slices Specification

## Purpose

First slice off the v1.1.0 lyrics expansion backlog (registered in
`appstate_refactor_plan.md` §0 and the 9-J deferred list). Adds
drag-and-drop lyrics attachment: dropping a `.lrc` file onto the
now-playing surface installs it as the current track's sidecar and shows
it immediately, without interrupting playback. Replaces today's manual
flow (place a correctly-named file beside the audio, then press Recheck)
for the common case.

This slice is outside the AppState decomposition refactor program; it
builds on the Slice 14 `LyricsStore` (new behavior lands as store
methods; no AppState surface is touched).

## Slice 15 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 15-A | Drag-and-drop `.lrc` attach (copy-to-sidecar) + confirm/error surfaces | Free | ⬜ |

### Goals

- Dropping a `.lrc` onto PlayerView or LyricsPanel while a track is
  loaded copies it to the track's primary sidecar position
  (`<dir>/<name>.lrc`) via a Related-Items coordinated write, persists
  the preference (`source: .lrc`, `encoding: "auto"`), refreshes the
  resolution, and opens the lyrics panel — playback never pauses.
- A track that already resolves a `.lrc` source gets a replace
  confirmation before anything is written.
- Failures (e.g. read-only volume) surface as a user-visible alert; no
  partial state is persisted.

### Decisions frozen with the user (2026-09-13)

- Persistence approach: **copy-to-sidecar** (approach B). The dropped
  file is read once under the drop's own sandbox grant and copied next
  to the audio file, so everything downstream is the existing sidecar
  machinery — no schema change, no bookmarks. `LyricsPreference.customPath`
  stays reserved (a future no-copy variant would use it).
- Drop targets: PlayerView (now-playing panel) and LyricsPanel, same
  handler (Q1). Playlist-area drops of `.lrc` stay ignored (out of scope).
- Attach target is `currentTrack`; no track loaded → drop rejected (Q2).
- Existing `.lrc` source → confirmation alert before replacing (Q3).
- On attach, the persisted encoding resets to `"auto"` (re-detect) (Q4).
- Accepted extension: `.lrc` only (Q5; `.txt` etc. stay on the 9-J
  deferred list).
- Copy failure → alert with a localized message; nothing persisted (Q6).

### Out of Scope

- `NSOpenPanel` custom file selection and the no-copy `customPath` path
  (9-J deferred item; a separate slice when opened).
- Alternative extensions (`.txt`), alternative sidecar filenames,
  SYLT/TXXX, synchronized scrolling — all stay on the 9-J deferred list.
- Accepting `.lrc` drops on the playlist area (`FileDropService`
  untouched).
- Lyrics editing / write-back of embedded tags.
- Any AppState change beyond none-at-all: the feature is store + views.

### Constraints

- Verified external behavior (web research 2026-09-13, sources in the
  session log; per-claim summary):
  - `dropDestination(for: URL.self)` receives Finder file drags on
    macOS (same Transferable/URL mechanics as the existing
    `AudioFileItem` import path).
  - A dropped file's sandbox extension is granted automatically and
    lives for the process session — the one-time source read needs no
    bookmark.
  - Writing a related item is the documented Related-Items pattern
    (`NSFilePresenter.primaryPresentedItemURL` + `NSIsRelatedItemType`
    + coordinated write); the already-declared `CFBundleTypeRole =
    Editor` for `.lrc` is the role the write case requires, and the app
    already has `ENABLE_USER_SELECTED_FILES = readwrite`.
- No cross-store dependency: the confirm/error surfaces live on
  `LyricsStore` itself, keeping the program plan's dependency graph
  (`LyricsStore ← lyricsService, lyricsPreferenceStore`) unchanged —
  AlertCenter is NOT wired in.
- New code builds warning-free under the Slice 12 baseline; touched
  baseline files keep their counts.
- TDD red-green: red commit lands failing tests against an
  intentionally-unwired skeleton; "是請執行" gates the green phase.

### Dependencies

- Slice 14 (`LyricsStore` exists; methods land there).
- Slice 9-M Related-Items infrastructure (`SiblingFilePresenter`,
  `.lrc` `CFBundleDocumentTypes` declaration).

---

## Slice 15-A: Drag-and-drop `.lrc` attach ⬜

### Goal

Let the user drag a `.lrc` file from Finder onto the now-playing surface
to attach it to the current track — copied to the sidecar position,
persisted, displayed immediately, playback untouched.

### Scope (FROZEN as of spec commit)

**`LyricsService` protocol + `DefaultLyricsService`:**

- New protocol method `installSidecar(from sourceURL: URL, for track:
  Track) throws` — reads the dropped file's bytes (the drop grant covers
  the read) and writes them to the primary sidecar position
  `<dir>/<name>.lrc` via a coordinated write
  (`NSFileCoordinator.coordinate(writingItemAt:options:.forReplacing)`)
  with a `SiblingFilePresenter` whose primary is `track.url` — the write
  twin of the existing `resolveContent` read path. Overwrites an
  existing destination. Guard: when `sourceURL` already IS the
  destination (the user drags the current sidecar onto the app), the
  method is a no-op — never a self-copy that could truncate the file.
- File-system access stays encapsulated in the service (design rule: no
  FileManager calls in stores or views).

**`LyricsStore` additions (see Public API shape):**

- `attachLyricsFile(_:for:) -> Bool` — the drop entry point. Rejects a
  nil track or a non-`.lrc` extension (returns `false`, nothing else
  happens). When the current resolution already offers `.lrc`, stages a
  `PendingLyricsAttach` and returns `true` (confirmation flow); otherwise
  installs immediately.
- `confirmPendingAttach()` / `cancelPendingAttach()` — resolve the
  staged replacement.
- Private install path: `installSidecar` on the service → persist
  `LyricsPreference(source: .lrc, encoding: "auto", languageCode: nil)`
  → `updateResolution(for:)` → `showLyrics = true` (the "shows
  immediately" half of the feature). On a thrown error:
  `attachErrorKey` is set to the localized message key and nothing is
  persisted.
- `pendingAttach: PendingLyricsAttach?` and `attachErrorKey: String?`
  are the two new observable surfaces; both are cleared by their
  alerts' buttons.

**View changes:**

| File | Change |
| --- | --- |
| `PlayerView.swift` | `.dropDestination(for: URL.self)` on the panel root; handler passes each URL to `lyricsStore.attachLyricsFile(_:for: appState.currentTrack)` and returns whether any was accepted |
| `LyricsPanel.swift` | same `dropDestination`, same handler |
| `ContentView.swift` | hosts the two alerts (top-level like the existing alert stack, via `@Bindable` on the already-injected `LyricsStore`): replace-confirmation (`pendingAttach != nil` → Replace / Cancel) and attach-failure (`attachErrorKey != nil` → OK) |
| `en.lproj` / `zh-Hant.lproj` / `ja.lproj` `Localizable.strings` | new keys: `lyrics_attach_replace_title`, `lyrics_attach_replace_body`, `lyrics_attach_replace_confirm`, `lyrics_attach_failed_title`, `lyrics_attach_failed_body` |

No scene-injection change: every drop target and alert host already
receives `LyricsStore` from Slice 14 (main window scene only). No new
`.swift` files → no pbxproj change, no development_guide structure
change.

### Acceptance Criteria

1. AC1: `LyricsService` protocol carries `installSidecar(from:for:)`;
   `DefaultLyricsService` implements it as a coordinated sibling write;
   `LyricsStore` carries the two new surfaces and three new methods of
   the Public API shape.
2. AC2: every TDD-matrix test passes in the file its Test File Decision
   names.
3. AC3: full ⌘U suite green; final count = pre-slice count + new rows
   (pre-slice measured 496 passed / 5 skipped at the Slice 14 close).
4. AC4: touched files build warning-free; baseline files keep their
   Slice 12 counts (re-measurement note recorded at close-out).
5. AC5 (manual, binary): each flow below behaves as described —
   (a) while a track with no lyrics is PLAYING, drop a `.lrc` on the
   player panel: audio never stutters or stops, the lyrics panel opens
   by itself showing the content, and `<歌名>.lrc` now exists beside the
   audio file; (b) the same drop on an open LyricsPanel behaves
   identically; (c) a track that already shows `.lrc` lyrics → drop
   presents the replace confirmation; Replace swaps the content, Cancel
   changes nothing on disk or screen; (d) dropping a non-`.lrc` file or
   dropping with no track loaded is rejected (no alert, no effect);
   (e) after quitting and relaunching, the attached lyrics still
   resolve (sidecar persistence); (f) a track whose folder is not
   writable (e.g. a read-only volume) → drop shows the failure alert,
   playback continues, no preference is saved; (g) dragging the track's
   own current sidecar file onto the app leaves the file intact;
   (h) dropping a `.lrc` on the playlist area is still ignored.

### Out of Scope

- See slice-level Out of Scope.

### Deferred Backlog

None new (custom no-copy path already registered on the 9-J list).

### Files

- HarmoniaPlayer Application Layer: modify
  `Shared/Services/LyricsService.swift`, `Shared/Models/LyricsStore.swift`
- UI: modify `Shared/Views/PlayerView.swift`,
  `Shared/Views/LyricsPanel.swift`, `Shared/Views/ContentView.swift`,
  `en.lproj/Localizable.strings`, `zh-Hant.lproj/Localizable.strings`,
  `ja.lproj/Localizable.strings`
- Tests: extend `SharedTests/LyricsStoreTests.swift`,
  `SharedTests/LyricsServiceTests.swift`; modify
  `FakeInfrastructure/FakeCoreProvider.swift` (`FakeLyricsService` /
  `StubLyricsService` gain a recording, throwable `installSidecar`)
- Project: no pbxproj change (no new files)
- Docs at green: `api_reference.md` (§4.5 LyricsService, §5.12
  LyricsStore), `user_guide.md` (user-facing feature),
  `module_boundary.md` (§4.4 note: service owns the coordinated write)
- Docs at close-out: this spec (ticks), development plan (slice table),
  `slice_12_micro.md` (re-measurement note)

### TDD matrix

| Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- |
| `testAttachLyricsFile_NilTrack_Rejected` | fresh store | `attachLyricsFile(lrcURL, for: nil)` | returns `false`; no service install call; no pending | Extend `LyricsStoreTests.swift` |
| `testAttachLyricsFile_NonLrcExtension_Rejected` | a track | `attachLyricsFile(txtURL, for: track)` | returns `false`; no install; no pending | Extend `LyricsStoreTests.swift` |
| `testAttachLyricsFile_NoExistingLrc_InstallsAndShows` | resolution without `.lrc` | `attachLyricsFile(lrcURL, for: track)` | service `installSidecar` called once with (url, track); pref saved `source == .lrc`, `encoding == "auto"`; resolution re-queried; `showLyrics == true` | Extend `LyricsStoreTests.swift` |
| `testAttachLyricsFile_ExistingLrc_StagesPendingWithoutInstall` | resolution with `.lrc` available | `attachLyricsFile(lrcURL, for: track)` | returns `true`; `pendingAttach` set; NO install call | Extend `LyricsStoreTests.swift` |
| `testConfirmPendingAttach_InstallsAndClears` | `pendingAttach` staged | `confirmPendingAttach()` | install called once; pending `nil`; pref saved | Extend `LyricsStoreTests.swift` |
| `testCancelPendingAttach_ClearsWithoutInstall` | `pendingAttach` set directly | `cancelPendingAttach()` | pending `nil`; install never called | Extend `LyricsStoreTests.swift` |
| `testAttachLyricsFile_InstallThrows_SetsErrorAndPersistsNothing` | stub `installSidecar` throws | `attachLyricsFile(lrcURL, for: track)` | `attachErrorKey != nil`; no pref saved; `showLyrics` unchanged | Extend `LyricsStoreTests.swift` |
| `testInstallSidecar_CopiesToPrimarySidecarPosition` | temp dir with `song.mp3` + external `dropped.lrc` | `installSidecar(from:for:)` | `<dir>/song.lrc` exists with the source bytes | Extend `LyricsServiceTests.swift` |
| `testInstallSidecar_OverwritesExistingDestination` | destination `song.lrc` already present with old bytes | `installSidecar(from:for:)` | destination now holds the source bytes | Extend `LyricsServiceTests.swift` |
| `testInstallSidecar_SourceIsDestination_NoOp` | source URL == `<dir>/song.lrc` | `installSidecar(from:for:)` | no throw; file content unchanged (no self-truncation) | Extend `LyricsServiceTests.swift` |
| (regression, no new test) | Slice 14 rows | existing lyrics flows | all `LyricsStoreTests` / `LyricsServiceTests` Slice-14-era rows stay green unchanged | Existing files, unchanged |

Red-phase expectation: the store skeleton (empty bodies; `attachLyricsFile`
returns `false`) leaves rows 1–2 vacuously green (negative guards — the
13-A honesty precedent) and rows 3–5, 7 red; row 6 is red because the
skeleton's empty `cancelPendingAttach()` leaves the directly-set pending
in place. The service skeleton (empty `installSidecar` body) leaves rows
8–9 red and row 10 vacuously green (negative guard). Expected red set:
**rows 3, 4, 5, 6, 7, 8, 9 (7 failures); rows 1, 2, 10 are
green-from-start guards.** Row 11 stays green throughout.

### Public API shape

```swift
// LyricsService (protocol addition)

/// Copies the given lyrics file to the track's primary sidecar position
/// (`<dir>/<name>.lrc`) via a Related-Items coordinated write, replacing
/// any existing file there. No-op when the source already is that
/// destination. Throws on read or write failure.
func installSidecar(from sourceURL: URL, for track: Track) throws
```

```swift
// LyricsStore (additions)

/// A staged replace request: the user dropped a lyrics file onto a track
/// that already resolves a `.lrc` source, and must confirm the overwrite.
struct PendingLyricsAttach: Equatable {
    let sourceURL: URL
    let track: Track
}

var pendingAttach: PendingLyricsAttach?

/// Localization key for the attach-failure alert; `nil` when no failure
/// is pending. Cleared by the alert's OK button.
var attachErrorKey: String?

/// Drop entry point. Returns whether the drop was accepted (a `.lrc`
/// with a current track). Installs immediately, or stages
/// `pendingAttach` when the track already resolves a `.lrc` source.
@discardableResult
func attachLyricsFile(_ url: URL, for track: Track?) -> Bool

/// Performs the staged replacement, then clears `pendingAttach`.
func confirmPendingAttach()

/// Discards the staged replacement.
func cancelPendingAttach()
```

### Implementation notes

- Install success path (one place, used by both the direct and the
  confirmed flow): `try lyricsService.installSidecar(from:for:)` →
  `lyricsPreferenceStore.save(LyricsPreference(source: .lrc, encoding:
  "auto", languageCode: nil, customPath: nil), for: track)` →
  `updateResolution(for: track)` → `showLyrics = true`. Failure path:
  `attachErrorKey = "lyrics_attach_failed_body"`, nothing persisted.
- "Already has `.lrc`" is decided from the store's own
  `lyricsResolution?.availableSources` — no new detection API on the
  service.
- The dropped URL is only read inside `installSidecar`, during the drop
  interaction whose sandbox grant is still live; nothing about the
  source file is retained.
- Playback independence is structural: no store or service call in this
  slice touches `PlaybackService`.
- Views validate nothing beyond forwarding: acceptance is the store's
  `Bool` so the logic exists once.
- Doc obligations at green (Doc Update Table, full line-by-line read):
  `api_reference.md` (changed protocol + store API), `user_guide.md`
  (feature how-to incl. replace confirmation), `module_boundary.md`
  §4.4 (coordinated-write ownership note). `architecture.md` untouched
  → HC 5-area audit not triggered.
