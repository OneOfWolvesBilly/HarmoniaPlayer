# Slice 09 Smoke-Fix Micro Spec

## 0. Purpose and relationship to `slice_09_micro.md`

Remediation fixes found during the v1.0.0 Free pre-submission smoke test,
after slice 9-R closed.

- `slice_09_micro.md` stays the frozen design authority for slices **9-A … 9-R**.
- This file is the numbering authority for slices **9-S onward**.

Classification principle (why these are separate slices, not folded):
- **Rename / configuration consequences** (e.g. the 9-R `TEST_HOST`, scheme,
  module-name and import updates) are *not* bugs; they are downstream effects of
  a deliberate change and fold into that change's chore commit.
- **Behaviour bugs** found in smoke test are independent logical defects; each
  gets its own slice, spec, and red-phase test.

## 1. Slice summary (authority for 9-S+)

| Slice | Title | Tier | Status |
| --- | --- | --- | --- |
| 9-S | Persist repeat and shuffle mode on change | Free | ✅ |
| 9-T | Resolve natural completion against the playing playlist | Free | ✅ |
| 9-U | Pause marquee at both ends | Free | ✅ |
| 9-V | EQ persistence (named-only) + load fallback to Flat + button tint live update | Free | ⬜ |
| 9-W | Move playlist persistence to an Application Support file + exclude artwork/lyrics (root-fix `hp.playlists` overflow) | Free | ⬜ |
| 9-X | Remove all selected tracks via the multi-select context menu | Free | ⬜ |
| 9-Y | Add New / Import to the per-tab playlist context menu | Free | ⬜ |
| 9-Z | Manual drag-to-reorder for the playlist Table | Free | ⬜ |

Deferred (not a slice): **#5** untracked natural-completion `Task` — see §5.
Withdrawn: the original 9-T Part B (mini-player browse-only switch) — see 9-T.

---

## Slice 9-S: Persist repeat and shuffle mode on change

### Problem
`repeatMode` / `isShuffled` reach disk only when `saveState()` is called by an
unrelated event (a playlist mutation, or `willTerminateNotification`). Toggling
repeat/shuffle does not itself persist, so a value saved earlier (e.g. `.one`)
survives a later change and the app relaunches with a stale mode.

### Root cause
The init persistence pipeline subscribes only `$replayGainMode` and
`$selectedLanguage` to `saveState()`. `$repeatMode` and `$isShuffled` have no
change-time subscription.

### Fix
Add two change-time sinks beside the existing ones in the init pipeline:
```swift
$repeatMode
    .dropFirst()
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.saveState() }
    .store(in: &cancellables)

$isShuffled
    .dropFirst()
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.saveState() }
    .store(in: &cancellables)
```
`saveState()` / `restoreState()` encoding is already correct; no change there.

### TDD matrix
| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| S1 | Changing `repeatMode` persists immediately (round-trips via a fresh `restoreState()`) | `AppState` | Extend `AppStatePersistenceTests.swift` |
| S2 | Changing `isShuffled` persists immediately | `AppState` | Extend `AppStatePersistenceTests.swift` |

`AppState.init` accepts an injectable `UserDefaults`; tests use a private suite.

### Files
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Models/AppState.swift` | Add `$repeatMode` and `$isShuffled` persist sinks in the init pipeline |

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-s)` | persist repeat and shuffle mode on change |

Doc updates: none (keys already exist; no public API / boundary / shortcut change).

---

## Slice 9-T: Resolve natural completion against the playing playlist

### Part A — natural completion resolves the playing playlist (#2) — SHIPPED
**Problem.** Playing in Playlist 2 while Playlist 1 is selected, the last track
finishes and nothing clears: now-playing art/title and the tab speaker icon
stay; status shows "Stopped".

**Root cause.** `trackDidFinishPlaying()` looks up the finished track in
`playlists[activePlaylistIndex]` (browsed) in all branches (`.off`, `.all`,
`.one`). When browse ≠ play the lookup fails and the method early-returns before
`stop()` / `currentTrack = nil`.

**Fix.** Resolve the playing index from `playingPlaylistID` once at the top and
use it throughout instead of `activePlaylistIndex`:
```swift
guard let lastID = lastPlayedTrackID,
      let playingIndex = playlists.firstIndex(where: { $0.id == playingPlaylistID })
else { await stop(); currentTrack = nil; return }
```
Scope is **natural completion only**. Transport (`playNextTrack` /
`playPreviousTrack`) keeps operating on `activePlaylistIndex` by existing
design; transport semantics are deferred to the v0.2 coordinator refactor.

### Part B — mini player playlist menu switches browse only (#4) — WITHDRAWN

**Withdrawn after smoke testing.** #4 was a misdiagnosis. The mini player's
playlist switcher force-playing the selected playlist
(`switchMiniPlayerPlaylist` = `stop()` + `play(first)`) is the **intended v1.0
behaviour**: the mini player has no persistent track list in its primary
surface, so switching the playlist menu must do something visible — play it. A
browse-only switch would be a no-op there. Browse ≠ play in the mini player
belongs with the mini-player track-list / playing-queue preview, deferred to
**v1.1.0**.

`#5`'s stuck symptom (repeat-one stuck at 0:00) was **already resolved by Part A**
(the natural-completion fix), not by any change to the switcher — so there was
no remaining reason to touch `switchMiniPlayerPlaylist`. The Part B working-tree
changes were reverted (`git checkout HEAD --`); `switchMiniPlayerPlaylist(to:)`
and its tests remain as shipped (8-B / 9-K).

### TDD matrix (Part A)
| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| T1 | Last track of the *playing* playlist finishing (while a *different* playlist is selected) stops and clears `currentTrack` | `AppState` | Extend `AppStateNavigationTests.swift` |
| T2 | Repeat-one on the playing playlist replays even when a different playlist is selected | `AppState` | Extend `AppStateNavigationTests.swift` |

### Files (Part A)
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Models/AppState+Navigation.swift` | `trackDidFinishPlaying()` resolves the playing-playlist index from `playingPlaylistID` |

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-t)` | resolve natural completion against the playing playlist |

---

## Slice 9-U: Pause marquee at both ends

**Problem.** The mini player title/artist marquee pauses only at the start; at
the end it snaps back instantly (hard-coded 200 ms), so the last characters are
not readable.

**Fix.** In `MarqueeText.runLoop()`, pause `marqueePause` seconds at the **end**
of the scroll (before the reset), replacing the hard-coded 200 ms tail wait.
Head pause unchanged; both ends then use the same `marqueePause`.

**Out of scope:** making a *speed* change perceptible while dragging (the loop
restarts on every slider step). Deferred to v0.2.

### TDD
Marquee timing is a SwiftUI `Task.sleep` animation loop with no meaningful
headless assertion (same situation as the 9-R lyrics-button visibility change,
which used manual smoke). **Verification for v1.0 is manual smoke only** (below).
Extracting the loop schedule into a pure helper and asserting a tail pause equal
to `marqueePause` is **deferred to the v1.1.0 test cleanup / rewrite slice**, not
treated as a missing test here.

### Files
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Views/MarqueeText.swift` | Add end-of-scroll pause (`marqueePause`) before reset |

### Manual verification
1. Mini player, a track whose title is longer than the window → title scrolls.
2. It pauses at the start, scrolls, **pauses at the end**, then returns.
3. Increasing Pause Duration lengthens the pause at **both** ends.

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-u)` | pause marquee at both ends before looping |

---

## Slice 9-V: EQ persistence (named-only) + button tint live update

Two EQ defects found during v1.0.0 ship-prep smoke testing. Both are
HarmoniaPlayer-layer only; HarmoniaCore is untouched. EQ is global in v1.0
(no per-track storage — that is a v1.1.0 item), so `isEnabled` is a valid global
signal and the button tint stays bound to it (blue = enabled, not window-open).

### Part A — named-only persistence + load validation (EQ-1)

**Problem.**
- *Phantom selection:* the picker shows a blank / non-existent preset. `EQView`'s
  picker renders the "—" sentinel only when `currentPresetName == nil`; a
  persisted non-nil name that resolves to no built-in / custom preset has no tag.
- *Unsaved curve resurrected:* an unsaved ("—") curve is persisted and restored
  next launch. Only a resolvable named preset should persist; "—" is transient.

**Root cause.**
- `EQPersistenceStore.save` writes `bandGains` / `preamp` unconditionally, so the
  "—" curve is persisted.
- `readState` reads `currentPresetName` and `customPresets` independently;
  `customPresets` decodes under `try?` (failure → `[]`) while the name survives.
  Identity migration (1→1) does not repair it. `EQCoordinator.init` assigns the
  loaded name straight through with no resolve check.

**Fix (`EQCoordinator`).**
- `init` — after assigning the loaded `state`, **before** pushing to the service,
  resolve `currentPresetName` via `preset(named:)`:
  - resolves → keep the name; set `bandGains` / `preamp` from that preset
    (picker label always matches the live curve);
  - `nil` or unresolvable → `currentPresetName = nil`,
    `bandGains = EQPersistedState.defaults.bandGains`,
    `preamp = EQPersistedState.defaults.preamp`.
  Push `self.*` (the corrected values) to the service, not the raw `state.*`.
- `persist()` — when `currentPresetName == nil`, persist `bandGains` / `preamp`
  as the flat defaults (the unsaved curve is never written); otherwise persist
  the live values. `isEnabled` and `customPresets` persist unchanged in both
  cases.

Net: a named preset persists and restores; "—" is session-live but loads flat
next launch; an unresolvable name loads as "—" + flat → phantom impossible. (Part C below
revises this fallback to resolve to the built-in "Flat" preset instead of `nil`.)

### Part B — toolbar tint updates when the enabled state changes (EQ-2)

**Problem.** Toggling Enable in `EQView` does not change the main `PlayerView`
EQ-button tint live. (Launch tint is correct — it reflects the persisted
`isEnabled`.)

**Root cause.** `PlayerView` observes `appState` but reads the nested
`appState.eqCoordinator.isEnabled`. Toggling fires `eqCoordinator`'s
`objectWillChange`, not `appState`'s, so `PlayerView` does not re-render.

**Fix.**
- `AppState` — add `@Published private(set) var eqEnabled: Bool`. In `init`, set
  `eqEnabled = eqCoordinator.isEnabled` after `eqCoordinator` is assigned, and add
  a sink in the published-state pipeline:
  ```swift
  eqCoordinator.$isEnabled
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.eqEnabled = $0 }
      .store(in: &cancellables)
  ```
  `eqCoordinator.isEnabled` stays the source of truth; `eqEnabled` is a read-only
  UI mirror (keeps Views → AppState).
- `PlayerView` — bind the EQ button tint to `appState.eqEnabled`
  (was `appState.eqCoordinator.isEnabled`). Semantics unchanged: blue = enabled.

### Part C — load fallback resolves to the Flat preset (EQ-3)

**Problem (UX, not a defect).** Part A's load fallback resolves an unsaved
("—") or unresolvable persisted state to `currentPresetName = nil` + a flat
curve. On relaunch the state reads "EQ enabled, curve flat, picker shows —".
Because the first built-in preset "Flat" *is* an all-zero curve, this landing
is audibly identical to Flat yet the picker claims nothing is selected — the
"why is it on and flat with nothing chosen" mismatch reported in smoke testing.

**Decision.** Land the fallback on the built-in **"Flat"** preset instead of
`nil`. The curve is unchanged (still all-zero); only `currentPresetName` moves
from `nil` to `"Flat"`, so the picker shows Flat and the "—" sentinel no longer
appears at launch. `isEnabled` is **not** touched — enable and preset selection
are independent dimensions (matching reference players, where the EQ on/off
switch is independent of the chosen curve), so the user's on/off intent is
preserved.

**Fix (`EQCoordinator.init`).** In the fallback branch (persisted name is `nil`
or does not resolve), set `currentPresetName = "Flat"` and take the curve from
`preset(named: "Flat")` (bands clamped, preamp clamped). If "Flat" is somehow
absent from the built-ins (defensive; it ships in `EQPresets.builtin`), fall
back to the prior `nil` + flat-defaults path so init never traps. `init` does
**not** write the store — the resolved "Flat" lands in UserDefaults on the next
mutator, so the no-persist-on-init invariant is unchanged. `EQView` and
`persist()` need no change: `currentPresetName == "Flat"` selects the built-in
tag (the "—" sentinel renders only when the name is `nil`), and `persist()`'s
non-nil branch writes the live (flat) curve.

**Tests (Part C).** Revises two Part A expectations and adds one:

| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| V1′ | Constructing with an unresolvable persisted name → `currentPresetName == "Flat"`, bands/preamp flat (rename `…ResetsToCustomFlat` → `…ResolvesToFlatPreset`; supersedes Part A's `== nil`) | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |
| V4′ | After a custom edit, a fresh coordinator over the same store loads flat + `currentPresetName == "Flat"` (supersedes Part A's `== nil`) | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |
| V7 | Constructing with no persisted preset name (name absent) → `currentPresetName == "Flat"`, bands/preamp flat | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |

V2 (valid name restores its curve), V3 (custom edit persists flat bands), and
V5 / V6 (Part B) are unaffected.

**Files (Part C).**

| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Models/EQCoordinator.swift` | init fallback branch resolves to "Flat" instead of nil |
| Modify | `HarmoniaPlayerTests/SharedTests/EQCoordinatorTests.swift` | revise V1 / V4 expectations to "Flat"; add V7 |
| Modify | `docs/api_reference.md` | §5.8 — load fallback resolves to the built-in Flat preset (not nil) |

**Commit (Part C).**

| Order | Type / Scope | Subject |
| --- | --- | --- |
| 3 | `fix(slice 9-v)` | resolve unsaved or unresolvable eq state to the flat preset on load |

**Non-goals / deferred (Part C).**
- v1.1.0: on a normal quit (⌘Q) with an unsaved custom curve, prompt to save it
  as a preset — save → reloadable named preset; decline → Flat. An abnormal
  termination (no prompt path) falls back to this Part C load-time Flat
  resolution. Tracked for v1.1.0; not in v1.0.
- `init` gains no new persist side effect — the resolved name lands on the next
  mutator, not during construction.

### TDD matrix
| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| V1 | Constructing with an unresolvable persisted preset name (name set, no matching built-in / custom) → `currentPresetName == nil`, bands/preamp flat | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |
| V2 | Constructing with a valid built-in name restores that preset's curve and keeps the name | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |
| V3 | After a custom edit ("—"), the persisted band data is flat (the unsaved curve is not written) | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |
| V4 | After a custom edit, a fresh coordinator over the same store loads flat + `currentPresetName == nil` | `EQCoordinator` | Extend `EQCoordinatorTests.swift` |
| V5 | `appState.eqEnabled` initial value matches `eqCoordinator.isEnabled` | `AppState` | Extend `AppStateTests.swift` |
| V6 | Toggling `eqCoordinator.setEnabled(_:)` updates `appState.eqEnabled` | `AppState` | Extend `AppStateTests.swift` |

`EQCoordinatorTests` injects `UserDefaults(suiteName:)` via
`EQPersistenceStore(defaults:)`; V1 / V3 / V4 seed the suite before constructing.

### Files
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Models/EQCoordinator.swift` | init load validation + flat-on-nil persist |
| Modify | `Shared/Models/AppState.swift` | add `eqEnabled` mirror + `$isEnabled` sink |
| Modify | `Shared/Views/PlayerView.swift` | bind EQ button tint to `appState.eqEnabled` |

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-v)` | persist eq state only for named presets and clear unresolvable names on load |
| 2 | `fix(slice 9-v)` | reflect eq enabled changes on the toolbar button |

### Doc updates
- `api_reference.md` — EQ schema / persistence note: named-only persistence +
  load validation; add `eqEnabled` to the AppState published-property table.
- No `module_boundary.md` / `architecture.md` change (no new type / boundary; EQ
  stays global; `eqEnabled` is an AppState mirror).

### Non-goals
- Per-track EQ (v1.1.0).
- Changing tint semantics (blue = `isEnabled`, not window-open).
- Changing `isEnabled` persistence (already persisted; untouched).
- Bumping `eqCurrentSchemaVersion` or removing the `hp.eq.bands` / `hp.eq.preamp`
  keys.

---

## Slice 9-W: Move playlist persistence to a file and exclude artwork/lyrics

Playlist persistence overflows the UserDefaults value-size limit, and the limit
itself is the root constraint. HarmoniaPlayer-layer only; HarmoniaCore untouched.
Two parts: **Part A** excludes the only large per-track payloads (artwork,
lyrics) from the encoded `Track`; **Part B** moves the playlists blob off
UserDefaults into an Application Support file, so the ~4 MB single-value limit no
longer applies at any library size.

### Problem

`hp.playlists` reaches ~6.75 MB, over the NSUserDefaults ~4 MB value-size limit;
writes past the limit fail silently, so playlists — and every other setting
written in the same `saveState` pass (EQ, language, repeat/shuffle) — can fail to
persist. Excluding artwork (Part A) fixes the *current* size, but `accessBookmark`
(~1–2 KB/track) plus metadata still accumulate ~1.5–2.5 KB/track, so a large
library (~2–3k tracks) would breach the same limit again. The limit is the root
cause; only moving off UserDefaults (Part B) removes it for good at any size.

### Part A — exclude artwork and lyrics from the encoded Track

**Root cause.** `Track.encode(to:)` writes `artworkData` (cover-image binary,
tens to hundreds of KB each) and `lyrics` (full text). These are the bulk of the
per-track size; the other 28 fields (incl. `accessBookmark`) total a few KB.

**Fix.**
1. `Track.encode(to:)` — stop writing `artworkData` (line 232) and `lyrics`
   (line 256). The other 28 fields, incl. `accessBookmark` (the security-scoped
   bookmark that is the only credential for reaching the file after relaunch),
   are unchanged.
2. `Track.init(from:)` — both already `decodeIfPresent` → `nil` when absent;
   verified invariant, no edit.
3. `AppState.refreshMetadataIfNeeded()` — widen the candidate condition with
   `|| track.artworkData == nil` (still gated on `isAccessible`); add
   `playlists[pi].tracks[ti].artworkData = refreshed.artworkData` (and `lyrics`)
   to the merge, so the existing background re-read restores artwork after launch.
4. Display sites (`MiniPlayerView` / `FileInfoView` / `PlayerView` /
   `MPNowPlayingAdapter`) unchanged; the grey placeholder shows briefly until the
   re-read lands.

### Part B — move playlists to an Application Support file

**Root cause.** `saveState` writes the whole `[Playlist]` JSON into the
UserDefaults key `hp.playlists` (line 699), subject to the ~4 MB single-value
limit. A file has no such per-value limit.

**Fix.**
1. New `PlaylistStore` protocol + `FilePlaylistStore` in `Shared/Services/`
   (`import Foundation` only), mirroring the existing `EQPersistenceStore` /
   `LyricsPreferenceStore` injected-store pattern. It is a *storage service*, not
   a new data model — `Track` / `Playlist` are unchanged.
   - `func save(_ playlists: [Playlist]) throws` — `JSONEncoder` → **atomic** write
     to `Application Support/playlists.json` (the sandbox container's Application
     Support directory, via `FileManager.url(for: .applicationSupportDirectory…)`).
   - `func load() throws -> [Playlist]?` — read + `JSONDecoder`; missing file →
     `nil`; corrupt file → throws.
2. `AppState.init` — inject `playlistStore: PlaylistStore? = nil`, defaulting to
   `FilePlaylistStore()` built inside the `@MainActor` init body. The parameter
   must be optional, **not** `= FilePlaylistStore()`: a `@MainActor` initializer
   cannot be called from the nonisolated default-argument context (same
   constraint as `undoManager`).
3. `saveState` — replace `userDefaults.set(data, forKey: .playlists)` (line 699)
   with `try? playlistStore.save(playlists)`. `activePlaylistIndex`, `sortKey`,
   and the other small keys stay in UserDefaults.
4. `restoreState` — load playlists from `playlistStore.load()` instead of
   `hp.playlists`; a `nil` or thrown result (missing / corrupt) is treated as
   empty playlists (logged, no crash).
5. **Migration (one-shot).** In `restoreState`, if `playlistStore.load()` returns
   `nil` (no file yet) but `userDefaults` still holds `hp.playlists`, decode the
   legacy blob once and use it; the next `saveState` writes the new file (artwork
   excluded by Part A) and the old `hp.playlists` key is removed to reclaim the
   space. Thereafter the file is authoritative.

`Track` core fields, bookmark handling, and `restoreState`'s accessibility check
are unchanged.

### TDD matrix

| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| W1 | `encode(to:)` output contains no `artworkData` key | `Track` | Extend `TrackTests.swift` |
| W2 | `encode(to:)` output contains no `lyrics` key | `Track` | Extend `TrackTests.swift` |
| W3 | encode → decode preserves the metadata fields and `accessBookmark` (bookmark round-trip survives) | `Track` | Extend `TrackTests.swift` |
| W4 | Decoding a payload with no `artworkData` / `lyrics` keys yields `nil` for both | `Track` | Extend `TrackTests.swift` |
| W5 | `refreshMetadataIfNeeded()` includes an accessible track whose `artworkData == nil` and fills its artwork from the re-read | `AppState` | Extend `AppStateTests.swift` |
| W6 | `FilePlaylistStore` save → load round-trips a `[Playlist]` (file written, decoded equal) | `FilePlaylistStore` | New `FilePlaylistStoreTests.swift` |
| W7 | `load()` returns `nil` when no file exists; throws on a corrupt file | `FilePlaylistStore` | New `FilePlaylistStoreTests.swift` |
| W8 | `saveState` writes playlists via the store and does **not** write the `hp.playlists` UserDefaults key | `AppState` | Extend `AppStatePersistenceTests.swift` |
| W9 | `restoreState` loads playlists from the store | `AppState` | Extend `AppStatePersistenceTests.swift` |
| W10 | Migration: no file + legacy `hp.playlists` present → playlists restored, then file written and `hp.playlists` key cleared | `AppState` | Extend `AppStatePersistenceTests.swift` |

W3 note: `accessBookmark` comes from `url.bookmarkData(.withSecurityScope)`, which
needs a real file and may not yield a security-scoped bookmark in the unsandboxed
test host; the test seeds a temp file and asserts the bookmark `encode` produces
survives the decode (round-trip), not a specific scope. W6–W10 inject a temp
directory (`FilePlaylistStore`) and a fake `PlaylistStore` + `UserDefaults(suiteName:)`
(`AppState`).

**Test isolation (critical, do before wiring the store).** Once `AppState`
defaults `playlistStore` to the real `FilePlaylistStore()`, every test that
constructs an `AppState` without injecting a store shares the same real
`playlists.json` and cross-contaminates — one test's saved playlists are
restored by the next. So before `saveState` / `restoreState` are switched to the
store, every `AppState`-constructing test (~24 files) must inject its own
`FakePlaylistStore()`, mirroring how each already injects an isolated
`UserDefaults(suiteName:)`. Per-test injection is mandatory: a unique temp
directory per init breaks relaunch round-trips, and a shared temp re-introduces
contamination, so neither can replace it.

### Files

| Status | File | Change |
| --- | --- | --- |
| New | `Shared/Services/PlaylistStore.swift` | `PlaylistStore` protocol + `FilePlaylistStore` |
| Modify | `Shared/Models/Track.swift` | `encode(to:)` drops `artworkData` + `lyrics` |
| Modify | `Shared/Models/AppState.swift` | inject `playlistStore`; `saveState` / `restoreState` use the store; one-shot migration; `refreshMetadataIfNeeded` artwork merge |
| New | `HarmoniaPlayerTests/SharedTests/FilePlaylistStoreTests.swift` | W6–W7 |
| Modify | `HarmoniaPlayerTests/SharedTests/TrackTests.swift` | W1–W4 |
| New | `HarmoniaPlayerTests/FakeInfrastructure/FakePlaylistStore.swift` | in-memory `PlaylistStore` for test isolation |
| Modify | `HarmoniaPlayerTests/SharedTests/AppStateMetadataTests.swift` | W5 |
| Modify | `HarmoniaPlayerTests/SharedTests/AppStatePersistenceTests.swift` | W8–W10 |
| Modify | ~24 `AppState`-constructing test files | inject isolated `FakePlaylistStore()` |
| Modify | `docs/api_reference.md` | persistence section: playlists in an Application Support file; artwork/lyrics excluded; one-shot migration |

### Commit plan

| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-w)` | exclude artwork and lyrics from track persistence (Part A) |
| 2 | `fix(slice 9-w)` | add file-backed playlist store (Part B — store component) |
| 3 | `fix(slice 9-w)` | persist playlists in a file and migrate from user defaults (Part B — integration + test isolation) |

Part A first (shrinks the blob; artwork restored by the background re-read). Part B
is split: the `PlaylistStore` component and its unit tests land first, then the
`AppState` integration, one-shot migration, and per-test store isolation land
together. Each commit is independently green.

### Doc updates

- `api_reference.md` — persistence section: playlists persisted to an Application
  Support file (not the UserDefaults `hp.playlists` key); persisted `Track`
  excludes `artworkData` / `lyrics`, restored after launch by
  `refreshMetadataIfNeeded`; one-shot migration off the legacy key.
- No `module_boundary.md` change — the existing persistence stores
  (`EQPersistenceStore` / `LyricsPreferenceStore`) are not listed there either, so
  `PlaylistStore` follows suit.
- No `architecture.md` change (no HarmoniaCore surface, no new cross-repo boundary).

### Non-goals

- **Per-playlist files / binary format** (foobar2000 `.fpl` style) — a v1.1.0
  scale optimisation; v1.0 keeps a single JSON file.
- **Artwork lazy load** (read on display) — v1.1.0; this slice uses the background
  re-read, which re-reads each restored track's tags on launch (background,
  non-blocking).
- **Moving the small keys** (`activePlaylistIndex`, EQ, language) off UserDefaults
  — they are tiny; only the large playlists blob moves.
- **Per-track stats** (`playCount` / `lastPlayedAt` / `rating`) — unused in v1.0,
  unaffected.

---

## Slice 9-X: Remove all selected tracks from the context menu

### Problem
Multi-selecting rows in the playlist Table and choosing "Remove from Playlist"
removes only one track. Multi-select removal is a v1.0.0 Free function and a
pre-submission blocker.

### Root cause
`PlaylistView.tableView`'s `.contextMenu(forSelectionType: Track.ID.self)`
wraps every action in `if let id = ids.first`, so Remove calls the single-track
`AppState.removeTrack(_:)` with only the first selected ID. `AppState` has no
batch-removal method.

### Fix
1. Add `AppState.removeTracks(_ ids: Set<Track.ID>)` (Application Layer,
   `AppState+Playlist.swift`): removes every existing ID in the set from
   `tracks` + `insertionOrder` in one pass; drops removed IDs from
   `shuffleQueue` and clamps `shuffleQueueIndex`; registers ONE undo (snapshot
   restore of tracks + insertionOrder + shuffle queue, with redo). No-op when
   `ids` is empty or matches nothing.
2. `PlaylistView`: the Remove button acts on the whole `ids` set
   (`removeTracks(ids)`; `selectedTrackIDs.subtract(ids)`). Play / Play Next /
   Get Info stay single-track (`ids.first`), unchanged.

### Decisions (frozen as of this spec commit)
- D1: a batch that includes the now-playing track STOPS playback
  (`playbackService.stop()`, `currentTrack = nil`, `currentTime = 0`,
  `playbackState = .stopped`) — mirrors the single-track behaviour proven by
  `testRemoveTrack_CurrentTrack_StopsPlayback`. Not "advance to next".
- D2: `removeTracks` is snapshot-based and independent of `removeTrack`'s
  per-track playback-continuation logic; `removeTrack(_:)` is unchanged.
- D3: undo restores tracks / insertionOrder / shuffle queue only, not playback
  (same as `removeTrack`'s undo).

### TDD matrix
| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| X1 | All selected removed → playlist empty | `AppState` | Extend `AppStatePlayerlistTests.swift` |
| X2 | Subset removed, remaining kept in order | `AppState` | Extend `AppStatePlayerlistTests.swift` |
| X3 | Empty set is a no-op | `AppState` | Extend `AppStatePlayerlistTests.swift` |
| X4 | Set including `currentTrack` stops playback | `AppState` | Extend `AppStatePlayerlistTests.swift` |
| X5 | Set excluding `currentTrack` keeps `currentTrack` | `AppState` | Extend `AppStatePlayerlistTests.swift` |
| X6 | One undo restores the whole batch | `AppState` | Extend `AppStateUndoTests.swift` |

### Out of scope
- Play / Play Next / Get Info stay single-track (`ids.first`).
- Multi-select drag → 9-Z.

### Files
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Models/AppState+Playlist.swift` | Add `removeTracks(_:)` |
| Modify | `Shared/Views/PlaylistView.swift` | Remove button acts on whole `ids`; subtract from selection |
| Modify | `HarmoniaPlayerTests/SharedTests/AppStatePlayerlistTests.swift` | Tests X1–X5 |
| Modify | `HarmoniaPlayerTests/SharedTests/AppStateUndoTests.swift` | Test X6 |
| Modify | `docs/api_reference.md` | Add `removeTracks(_:)` to playlist methods table |

### Manual verification
1. Load ≥3 tracks, multi-select 2+ rows, right-click → Remove from Playlist →
   all selected rows disappear; ⌘Z restores them all at once.
2. Multi-select including the playing track → Remove → playback stops.

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-x)` | remove all selected tracks via removeTracks |

---

## Slice 9-Y: Add New / Import to the per-tab playlist context menu

### Problem
Right-clicking a playlist tab shows only Rename / Export / Delete. New Playlist /
Import Playlist… live on the tab-bar empty-area `.contextMenu`, which fires only
when no tab is under the cursor. When tabs fill the horizontal ScrollView the
empty area is unreachable, so the right-click path to New / Import is lost (the
toolbar "+" still works, but the right-click path is inconsistent).

### Root cause
`PlaylistView.playlistTab(index:playlist:)`'s `.contextMenu` lists only Rename /
Export / Delete. New / Import are only on the separate `playlistTabBar`
`.contextMenu`, which child-tab hit testing suppresses whenever a tab is under
the cursor.

### Fix
Append a `Divider()` then two buttons to the per-tab `.contextMenu`, reusing the
exact tab-bar actions and the existing localized strings — no new logic, no new
strings:
- `Button(L("ctx_new_playlist"))` → `appState.newPlaylist(name: "")` then
  `NotificationCenter.default.post(name: .renameActivePlaylist, object: nil)`.
- `Button(L("ctx_import_playlist"))` → `importPlaylist()`.

### Out of scope
- De-duplicating the export/import logic shared between `HarmoniaPlayerCommands`
  and `PlaylistView` → accepted v1.0 tech debt, unchanged (no
  `PlaylistTransferController` here).
- The tab-bar empty-area `.contextMenu` stays as-is.

### TDD
Pure SwiftUI context-menu wiring with no headless assertion (same as 9-U). The
reused actions `newPlaylist(name:)` and `importPlaylist()` already have
model-level coverage; no new AppState behaviour. **Verification for v1.0 is
manual smoke only.**

### Files
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Views/PlaylistView.swift` | Append Divider + New Playlist + Import Playlist… to the per-tab `.contextMenu` |

### Manual verification
1. Fill the tab bar so tabs overflow the ScrollView (no empty area).
2. Right-click any tab → Rename / Export / Delete, a divider, then New Playlist /
   Import Playlist….
3. New Playlist creates a tab and enters rename; Import Playlist… opens the
   playlist picker — same as the toolbar "+" / menu-bar paths.

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-y)` | add new and import to the per-tab playlist context menu |

Doc updates: none (no public API / boundary / shortcut change; reuses documented actions).

---

## Slice 9-Z: Manual drag-to-reorder for the playlist Table

### Problem
Tracks in the playlist cannot be reordered by dragging. Drag-to-reorder is a
v1.0.0 Free function and a pre-submission blocker.

### Root cause
The playlist UI is a SwiftUI `Table`, which has no `.onMove`. The Table is built
with the value-collection initializer and exposes no per-row hook, so the
existing, tested `AppState.moveTrack(fromOffsets:toOffset:)` is never reached
from the UI (wiring lost in the List → Table migration). The only drop
destination on the Table is `dropDestination(for: AudioFileItem.self)` for
Finder file imports.

### Prerequisite Investigation (web_search 2026-06-10)
- `Table` has NO `.onMove` (List-only). Confirmed.
- Apple's current recommended drag/drop is the Transferable-based
  `.draggable(_:)` + `.dropDestination(for:action:)`. NSItemProvider-based
  `.onDrag` / `.itemProvider` have macOS 15.x regressions (item-provider load
  deferred to drop-exit; `.itemProvider` drag broke in 15.1) — Apple staff
  steer developers to the Transferable modifiers.
- Per-row drag/drop on a `Table` attaches to `TableRow` via the rows-builder
  initializer `Table(of:selection:sortOrder:columnCustomization:columns:rows:)`.
  `TableRow.draggable(_:)` and `TableRow.dropDestination(for:action:)` are
  macOS 14.0+ — available at the macOS 15.6 deployment target.
- There is still no first-class "move row" API on `Table`; reorder is
  hand-rolled from draggable + dropDestination.
- `dropDestination` inside list/table containers has historical macOS
  reliability caveats — treated as a verification risk (see Risk), not a design
  unknown.

**Amendment (verification 2026-06-14).** The original design used a custom
exported UTType for `PlaylistReorderItem`. On a `GENERATE_INFOPLIST_FILE = YES`
target the type could not be instantiated at drop time
(`Failed to instantiate a content type from NSPasteboardType(...)` →
`TransferableSupportError error 0`), and registering an Exported Type
Identifier did not reliably take effect. Per the Risk clause the custom-UTType
approach was stopped and replaced (this amendment) with a plain-text transfer
that needs no registration. See revised Fix step 1.

### Fix
1. New Transferable payload `PlaylistReorderItem` (Model layer) wrapping a single
   `Track.ID`, transferring it as plain text (the UUID string) via
   `ProxyRepresentation`. Plain text is a system-known content type, so NO custom
   UTType declaration / Info.plist registration is required. Distinctness from
   `AudioFileItem` is by representation kind: `AudioFileItem` transfers a file URL
   (Finder file drops → table-level destination), this transfers text (in-app row
   drags → row-level destination). A foreign text drop carrying a non-UUID string
   resolves to an id that matches no track; `moveTrack(id:before:)` treats an
   unknown id as a no-op, so such drops are harmless.
2. Convert `tableView` to the rows-builder form: `Table(of: Track.self,
   selection:, sortOrder:, columnCustomization:) { coreColumns; tagColumns;
   technicalColumns } rows: { ForEach(tracks) { track in TableRow(track)
   .draggable(PlaylistReorderItem(id: track.id))
   .dropDestination(for: PlaylistReorderItem.self) { items, _ in … } } }`.
   - Drop onto target row R inserts the dragged track before R.
   - A drop below the last row appends to the end.
3. New AppState UI-facing entrypoint (Application Layer, `AppState+Playlist.swift`)
   that owns the index math and delegates to the existing, tested
   `moveTrack(fromOffsets:toOffset:)`:
   `func moveTrack(id draggedID: Track.ID, before targetID: Track.ID?)`
   - Resolves `fromOffsets` from `draggedID` and `toOffset` from `targetID`
     (or `tracks.count` when `targetID == nil`), then calls
     `moveTrack(fromOffsets:toOffset:)` (undo / insertionOrder reuse).
   - GUARD: no-op when `playlists[activePlaylistIndex].sortKey != .none` (a column
     sort is active → manual reorder disabled). Model authority for the disable
     rule.
   - No-op when `draggedID == targetID` or `draggedID` not found.
4. `PlaylistView` attaches the reorder draggable/dropDestination only when
   `sortOrder.isEmpty` (UX layer of the same disable rule; defence-in-depth with
   the AppState guard). The View passes IDs only — no index math in the View
   (module boundary: AppState owns logic).

### Decisions (frozen as of this spec commit)
- D1: v1.0 reorder payload is a SINGLE `Track.ID` (drag the row under the
  cursor). Multi-select drag is DEFERRED to backlog `BL-9Z-02`.
- D2: manual reorder is DISABLED while a column sort is active
  (`sortKey != .none`); it re-enables after the user clears the sort.
- D3: AppState entrypoint is `moveTrack(id:before:)` (`nil` target = append).

### Risk (verification, not design)
- The custom-UTType registration risk is RESOLVED by the plain-text transfer
  (this amendment); no Info.plist registration is involved.
- Remaining: a Finder file drop landing on a row must still route to the
  table-level `AudioFileItem` import, not be swallowed by the row-level text
  drop. Verify by dropping an audio file onto an existing row (must add, not
  no-op). If a file drop is intercepted by the reorder destination, STOP and
  report per SDD discipline; do NOT improvise.
- `TableRow.dropDestination` reorder reliability on macOS 15.6 remains a
  general verification point.

### TDD matrix
| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| Z1 | `moveTrack(id:before:)` moves the dragged track before the target ([A,B,C], C before A → [C,A,B]) | `AppState` | Extend `AppStateDragReorderTests.swift` |
| Z2 | `moveTrack(id:before:nil)` appends the dragged track to the end | `AppState` | Extend `AppStateDragReorderTests.swift` |
| Z3 | After a move, `insertionOrder == tracks.map(\.id)` | `AppState` | Extend `AppStateDragReorderTests.swift` |
| Z4 | No-op when `sortKey != .none` (order unchanged) | `AppState` | Extend `AppStateDragReorderTests.swift` |
| Z5 | No-op when `draggedID == targetID` | `AppState` | Extend `AppStateDragReorderTests.swift` |
| Z6 | One undo restores the pre-move order | `AppState` | Extend `AppStateUndoTests.swift` |

The `TableRow` drag/drop gesture itself has no headless assertion (same precedent
as 9-U); the AppState entrypoint is fully unit-tested above and the gesture is
covered by manual smoke.

### Out of scope
- Reordering while a column sort is active → disabled (D2).
- Cross-playlist drag (drag a track between tabs) → backlog `BL-9Z-01`, v2.0.
- Multi-select drag → backlog `BL-9Z-02` (D1).

### Files
| Status | File | Change |
| --- | --- | --- |
| New | `Shared/Models/PlaylistReorderItem.swift` | Transferable payload (Track.ID as plain text; no custom UTType / registration) |
| Modify | `Shared/Models/AppState+Playlist.swift` | Add `moveTrack(id:before:)` + sortKey guard |
| Modify | `Shared/Views/PlaylistView.swift` | Rows-builder Table + per-row draggable/dropDestination; coexist with the AudioFileItem drop |
| Modify | `HarmoniaPlayerTests/SharedTests/AppStateDragReorderTests.swift` | Tests Z1–Z5 |
| Modify | `HarmoniaPlayerTests/SharedTests/AppStateUndoTests.swift` | Test Z6 |
| Modify | `docs/api_reference.md` | Add `moveTrack(id:before:)` + `PlaylistReorderItem` |
| Modify | `docs/module_boundary.md` | Note the reorder Transferable in the Model layer; View passes IDs only |
| Modify | `docs/development_guide.md` | New file in the project structure |

### Manual verification
1. Insertion order (no column sort): drag a row up/down → it lands at the drop
   position; the order persists across relaunch.
2. With a column sort active: dragging does nothing (reorder disabled); clear the
   sort → dragging works again.
3. Finder file drop still imports (the AudioFileItem drop is unaffected).

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-z)` | add the playlist reorder transferable payload |
| 2 | `fix(slice 9-z)` | wire table drag-to-reorder to moveTrack |

---

## 5. Deferred — #5 untracked natural-completion `Task`

`startPolling()` fires `Task { await self.trackDidFinishPlaying() }` as an
untracked, detached task that `stopPolling()` cannot cancel.

The observed symptom (repeat-one stuck at 0:00 after a mini player playlist
switch) was **resolved by 9-T Part A** — the stuck state was the
`trackDidFinishPlaying()` early-return, not the detached task. Re-tested after
Part A: the symptom no longer reproduces. The detached-task structural defect
nevertheless remains latent. Decision: **do not harden #5 for v1.0.** Log it as
a structural defect for a post-ship robustness slice (track the completion task
so `stop()` / `play()` can cancel it).

---

## 6. Workflow

Spec frozen and committed first. Then per slice: red (failing tests) →
`是請執行` → green (minimum code) + doc updates in the same commit → commit.
Order: **9-S → 9-T (Part A) → 9-U → 9-V → 9-W → 9-X → 9-Y → 9-Z.**