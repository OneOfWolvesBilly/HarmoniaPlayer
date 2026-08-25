# Slice 11 Micro-slices Specification

## Purpose

HarmoniaPlayer v1.0.0 has no recovery path for a system sleep/wake cycle.
When the Mac sleeps (lid close) and wakes, playback never resumes, yet
`AppState.playbackState` remains `.playing` — so the window, the Control
Center widget and the lock screen all report playing while no audio is
produced, and the track never advances.

The underlying audio-pipeline defect is a HarmoniaCore concern and is
specified in HarmoniaCore's own documents (see Dependencies). This slice
covers the HarmoniaPlayer half: observing the sleep/wake cycle, deciding to
resume, and making `AppState` reflect every state its playback service can
reach so the UI can never again disagree with actual playback.

It ships as the v1.0.1 patch release, ahead of the v1.1.0 AppState
decomposition program, so that the program's later `PlaybackController`
extraction moves already-correct behaviour rather than carrying this defect
through five store extractions.

## Slice 11 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 11-A | Sleep/wake auto-resume policy + polling state reflection + SPM pin bump | Free | ✅ |

### Goals

- After the Mac wakes, playback resumes automatically at the position where
  it was interrupted, without user action.
- `AppState.playbackState` reflects every state the playback service can
  reach, not only `.stopped`.
- The Now Playing surface stays consistent with actual playback with no
  change to `NowPlayingCoordinator` or `MPNowPlayingAdapter`.

### Out of Scope

- **Every HarmoniaCore-side change.** The audio pipeline's invalidation
  detection and recovery is specified and implemented in the HarmoniaCore
  repository under its own `docs/specs/` structure. This document states
  only the behavioural contract HarmoniaPlayer depends on (see
  Dependencies); it does not specify HarmoniaCore's ports, adapters,
  services, files or tests.
- Continuing playback *while* the lid is closed — this is macOS system
  sleep, not application-controllable; the requirement is withdrawn, no
  destination.
- A user preference to disable auto-resume → BL-11A-01, v1.1.0 candidate
  backlog.
- The v1.1.0 AppState decomposition program → Slices 12, 13 and later
  stages, unchanged by this slice.

### Constraints

- **C1** — HarmoniaPlayer owns the wake trigger. HarmoniaCore targets
  macOS 13 **and iOS 16**, so `NSWorkspace` cannot live there; observing
  the sleep/wake cycle is by necessity application-side work.
- **C2** — HarmoniaPlayer writes no resume sequence of its own. Recovery of
  the audio pipeline is entirely a HarmoniaCore responsibility, reached
  through the existing `play()` call.
- **C3** — TDD red-green; "是請執行" gates the green phase.

### Dependencies

Requires a HarmoniaCore revision satisfying this behavioural contract:

- **HC-1** — When the audio output can no longer render, the playback
  service leaves `.playing` and reports `.paused`, retaining the position
  at which playback was interrupted.
- **HC-2** — A subsequent `play()` resumes audio from that retained
  position, with no additional call required from the caller.

Which HarmoniaCore design delivers HC-1 and HC-2 — port shape, adapter
behaviour, engine lifecycle — is specified in HarmoniaCore's
`docs/specs/`, and is deliberately not restated here. HarmoniaPlayer codes
against the observable contract only.

**Satisfied by** HarmoniaCore-Swift
`b4624987ab91a4c6a1cccc8c6285030f67510840`, verified against HC-1 and HC-2
before this slice's red phase.

One consequence of that revision is observable to HarmoniaPlayer and is
recorded here so it is not mistaken for a defect or optimised around:

- **HC-3** — the output is rebuilt and the decoder re-seeked on **every**
  `play()`, not only after an invalidation, because some invalidations
  cannot be detected. Resume cost therefore applies to ordinary
  pause → play as well as to post-wake resume. This is HarmoniaCore's
  decision; HarmoniaPlayer must not add state to avoid it, and must not
  treat the extra work as a bug to route around.

The satisfying revision must be merged and pushed before this slice's red
phase begins, because the pin bump is part of its scope.

---

## Slice 11-A: Sleep/Wake Auto-Resume and Polling Reflection ✅

### Goal

Trigger recovery at the moment the system wakes, resume playback
automatically at the interrupted position, and make `AppState`'s polling
loop reflect every state the playback service can reach so the UI and the
Now Playing surface can never disagree with actual playback again.

### Scope (FROZEN as of spec commit)

**SPM pin**

- `App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj/project.pbxproj` — the
  `XCRemoteSwiftPackageReference "HarmoniaCore-Swift"` revision moves from
  `0246e1e7dfa1ea90b2e94d004dd8a72305a63b00` to
  `b4624987ab91a4c6a1cccc8c6285030f67510840`.
- `Package.resolved` — regenerated to match.

**Version**

- `MARKETING_VERSION` moves from `1.0.0` to `1.0.1` in every build
  configuration that declares it; `CURRENT_PROJECT_VERSION` increments.

**Sleep/wake observation**

- `AppState` gains `private(set) var wasPlayingBeforeSleep: Bool = false`
  and two methods:
  - `handleSystemWillSleep()` — records
    `wasPlayingBeforeSleep = (playbackState == .playing)`.
  - `handleSystemDidWake()` — when `wasPlayingBeforeSleep` is true, clears
    the flag and calls `play()`; otherwise does nothing beyond clearing.
- `AppDelegate` registers observers for
  `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification`
  on `NSWorkspace.shared.notificationCenter`, forwarding to those two
  methods through a weak `AppState` reference assigned by
  `HarmoniaPlayerApp` — the injection pattern already used for
  `openWindow`.
- Both notifications are observed rather than inferring wake from the
  polling loop: the ordering of `didWake` against the 0.25s polling tick is
  undefined, so the pre-sleep state is captured deterministically before
  sleep instead.

**Polling reflection**

- `AppState.startPolling()` currently reacts only to `.stopped`. It gains
  handling for the remaining states the service can reach while the app
  still believes it is playing:
  - service `.paused` while `playbackState == .playing` → set
    `playbackState = .paused` and stop polling.
  - service `.error(e)` while `playbackState == .playing` → set
    `playbackState = .error(e)`, set `lastError`, and stop polling.
- `.stopped` handling and the `.loading` (drain) exemption are unchanged.

**Docs**

- `docs/api_reference.md` — new `AppState` members.
- `docs/architecture.md` — HarmoniaCore five-area audit, reflecting
  whatever surface the satisfying HarmoniaCore revision actually exposes.
- `docs/module_boundary.md` — record that the sleep/wake trigger is
  application-side by necessity (C1) while pipeline recovery is
  HarmoniaCore-side.
- `docs/development_guide.md` — SPM pin revision.
- `docs/user_guide.md` — documented behaviour: playback resumes
  automatically after the Mac wakes.
- `docs/slice/HarmoniaPlayer_development_plan.md` — tick the 11-A row
  ⬜→✅. The section, table and the v1.0.1 version target were added by the
  spec commit that opened this slice.

### Acceptance Criteria

1. AC1: `project.pbxproj` and `Package.resolved` both name
   `b4624987ab91a4c6a1cccc8c6285030f67510840` and no other revision.
2. AC2: `MARKETING_VERSION` is `1.0.1` in every configuration that declares
   it; no configuration still declares `1.0.0`.
3. AC3: `handleSystemWillSleep()` sets `wasPlayingBeforeSleep` to true when
   and only when `playbackState == .playing`.
4. AC4: `handleSystemDidWake()` calls `play()` when `wasPlayingBeforeSleep`
   is true, and does not call it when false.
5. AC5: `handleSystemDidWake()` leaves `wasPlayingBeforeSleep` false
   afterwards in both branches.
6. AC6: With the service reporting `.paused` and `playbackState == .playing`,
   one polling tick sets `playbackState == .paused` and cancels
   `pollingTask`.
7. AC7: With the service reporting `.error`, one polling tick sets
   `playbackState` to the mapped error and populates `lastError`.
8. AC8: No file under `App/` references a HarmoniaCore type outside the
   three Integration Layer files already permitted to `import HarmoniaCore`.
9. AC9: All pre-existing `HarmoniaPlayerTests` pass; no test is deleted
   without its assertion being reproduced elsewhere.
10. AC10: content added or modified by this slice carries no forbidden
    token — `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` over the slice's
    `.swift` diff hunks returns no forbidden match. Pre-existing tokens
    elsewhere in the touched files are out of this slice's scope: those
    files belong to the refactor set that Slice 10 deferred to the
    decomposition program, and they are cleaned there.
11. AC11: Every doc listed under Scope → Docs has been read in full and
    cross-checked against source, not grep-patched.

### Out of Scope

- Any HarmoniaCore source, spec or test change → HarmoniaCore repository.
- A user preference to disable auto-resume → BL-11A-01.
- Changes to `NowPlayingCoordinator` — the `playbackState` publisher
  already propagates every fix in this sub-slice to the Now Playing
  surface.

### Deferred Backlog

1. `BL-11A-01` — Settings toggle for "resume playback after the Mac wakes".
   Target: v1.1.0 candidate backlog, numbered when opened.

### Files

**Application Layer**
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState+Playback.swift` (modify)

**macOS**
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/AppDelegate.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift` (modify)

**Project**
- `App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj/project.pbxproj` (modify)
- `Package.resolved` (modify)

**Tests**
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePlaybackStateTests.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePollingTests.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/FakeInfrastructure/FakeCoreProvider.swift` —
  home of `FakePlaybackService`; no change needed (see TDD matrix)

**Docs** — as listed under Scope → Docs.

### TDD matrix

| Test | Given | When | Then | Test File Decision |
|---|---|---|---|---|
| `testWillSleepRecordsPlayingState` | `playbackState == .playing` | `handleSystemWillSleep()` | `wasPlayingBeforeSleep == true` | Extend `AppStatePlaybackStateTests.swift` |
| `testWillSleepRecordsFalseWhenPaused` | `playbackState == .paused` | `handleSystemWillSleep()` | `wasPlayingBeforeSleep == false` | Extend `AppStatePlaybackStateTests.swift` |
| `testDidWakeResumesWhenWasPlaying` | `wasPlayingBeforeSleep == true` | `handleSystemDidWake()` | fake service recorded `play()` | Extend `AppStatePlaybackStateTests.swift` |
| `testDidWakeDoesNotResumeWhenWasPaused` | `wasPlayingBeforeSleep == false` | `handleSystemDidWake()` | no `play()` recorded | Extend `AppStatePlaybackStateTests.swift` |
| `testDidWakeClearsFlag` | `wasPlayingBeforeSleep == true` | `handleSystemDidWake()` | flag is false | Extend `AppStatePlaybackStateTests.swift` |
| `testPollingReflectsServicePaused` | app `.playing`, service `.paused` | one polling tick | `playbackState == .paused`, polling cancelled | Extend `AppStatePollingTests.swift` |
| `testPollingReflectsServiceError` | app `.playing`, service `.error` | one polling tick | `playbackState == .error`, `lastError` set | Extend `AppStatePollingTests.swift` |
| `testPollingStillDetectsStopped` | app `.playing`, service `.stopped` | one polling tick | existing completion behaviour unchanged | Extend `AppStatePollingTests.swift` |
| `FakePlaybackService.state` is already a settable `var`, so `.paused` / `.error` can be staged directly | — | — | — | Already satisfied — no change to `FakeCoreProvider.swift` |

### Implementation notes

- `handleSystemDidWake()` calls the existing `play()`; no resume sequence is
  written in HarmoniaPlayer (C2). Re-preparation of the audio pipeline
  happens inside HarmoniaCore per HC-2, which is why the satisfying
  revision must be pinned before this sub-slice's red phase. Per HC-3 no
  "did we sleep?" state needs to reach HarmoniaCore — `play()` alone is
  sufficient.
- `AppState.playbackState` is `@Published` and `NowPlayingCoordinator`
  subscribes to it, so the polling fix propagates to Control Center and the
  lock screen with no change in either coordinator.
- The manual behaviour check is the primary verification for this slice:
  play a track, close the lid, reopen and log in — audio must resume from
  the interrupted position, with the window and Control Center both showing
  playing.
