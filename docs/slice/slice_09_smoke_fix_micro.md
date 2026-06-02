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
| 9-U | Pause marquee at both ends | Free | ⬜ |
| 9-V | EQ persistence (named-only) + button tint live update | Free | ⬜ |

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
next launch; an unresolvable name loads as "—" + flat → phantom impossible.

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
Order: **9-S → 9-T (Part A) → 9-U → 9-V.**