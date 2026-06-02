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
| 9-S | Persist repeat and shuffle mode on change | Free | ⬜ |
| 9-T | Decouple browse from playback | Free | ⬜ |
| 9-U | Pause marquee at both ends | Free | ⬜ |

Deferred (not a slice): **#5** untracked natural-completion `Task` — see §5.

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

## Slice 9-T: Decouple browse from playback

Two independent defects sharing one theme — the playlist being *browsed* must
not be conflated with the playlist that is *playing*. Shipped as two commits.

### Part A — natural completion resolves the playing playlist (#2)
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

### Part B — mini player playlist menu switches browse only (#4)
**Problem.** The mini player playlist menu force-changes the playing track when
the user only meant to switch which playlist they are looking at.

**Root cause.** `switchMiniPlayerPlaylist(to:)` does `stop()` + `play(first)`,
diverging from the main window's `switchPlaylist(to:)`, which only sets
`activePlaylistIndex` (+ clears selection / undo).

**Fix.** Route the mini player menu through the existing `switchPlaylist(to:)`
and delete `switchMiniPlayerPlaylist(to:)`. The switcher then behaves identically
to the main-window playlist tabs.

> Depends on Part A: once browsing no longer force-plays, browse ≠ play becomes
> reachable, and Part A guarantees natural completion still follows the playing
> playlist.

### TDD matrix
| # | Behaviour under test | SUT | Test File Decision |
| --- | --- | --- | --- |
| T1 | Last track of the *playing* playlist finishing (while a *different* playlist is selected) stops and clears `currentTrack` | `AppState` | Extend `AppStateNavigationTests.swift` |
| T2 | Repeat-one on the playing playlist replays even when a different playlist is selected | `AppState` | Extend `AppStateNavigationTests.swift` |
| T3 | Switching the browsed playlist does not stop or change the currently playing track | `AppState` | Extend `AppStateMultiPlaylistTests.swift` |

Removed: assertions of `switchMiniPlayerPlaylist`'s force-play behaviour (in
`MiniPlayerViewTests.swift` / `AppStateMultiPlaylistTests.swift`) are deleted
with the method.

### Files
| Status | File | Change |
| --- | --- | --- |
| Modify | `Shared/Models/AppState+Navigation.swift` | `trackDidFinishPlaying()` uses the playing-playlist index; delete `switchMiniPlayerPlaylist(to:)` |
| Modify | `macOS/Free/Views/MiniPlayerView.swift` | Playlist menu calls `switchPlaylist(to:)` |
| Modify | `docs/user_guide.md` | Note: the mini player playlist menu switches the browsed playlist only; playback continues |

### Commit plan
| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-t)` | resolve natural completion against the playing playlist |
| 2 | `fix(slice 9-t)` | switch mini player playlist menu without changing playback |

Commit 2 carries the `user_guide.md` update (9-L single-commit ship standard).

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
Marquee timing is a SwiftUI `Task.sleep` animation with no meaningful headless
assertion (same situation as the 9-R lyrics-button visibility change, which used
manual smoke). Verification is **manual smoke** (below). If review prefers a unit
test, the loop schedule can be extracted into a pure helper and asserted to
include a tail pause equal to `marqueePause` — decide at review.

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

## 5. Deferred — #5 untracked natural-completion `Task`

`startPolling()` fires `Task { await self.trackDidFinishPlaying() }` as an
untracked, detached task that `stopPolling()` cannot cancel. This is the
structural reason a manual playlist switch (`stop()` + `play()`) can race with
in-flight completion handling.

The observed symptom (repeat-one stuck at 0:00 after a mini player playlist
switch) is expected to disappear once **9-T Part B** removes the switcher's
`stop()` + `play()`. Decision: **do not harden #5 now.** After 9-T, re-run the
repro:
- resolved → log #5 as a latent structural defect for a post-ship slice;
- still failing → harden #5 (track the completion task so `stop()` / `play()`
  can cancel it) as a follow-up slice.

---

## 6. Workflow

Spec frozen and committed first. Then per slice: red (failing tests) →
`是請執行` → green (minimum code) + doc updates in the same commit → commit.
Order: **9-S → 9-T → re-test the #5 repro → 9-U.**