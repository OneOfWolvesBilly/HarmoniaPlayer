# Slice 04 Micro-slices Specification

## Purpose

This document defines **Slice 4: Playback Control** for HarmoniaPlayer.

Slice 4 wires `PlaybackService` into `AppState` to deliver real audio playback
orchestration: loading a track, transitioning through playback states, and
handling playback errors. It upgrades the existing `play(trackID:)` stub into a
full load-and-play operation and adds `play()`, `pause()`, `stop()`, and
`seek(to:)` transport controls.

---

## Slice 4 Overview

### Goals
- Upgrade `FakePlaybackService` with call recording and error stubs for deterministic testing
- Add `playbackState`, `currentTime`, and `duration` to `AppState` published state
- Implement `play()`, `pause()`, `stop()` transport controls in `AppState`
- Upgrade `play(trackID:)` to call `playbackService.load(url:)` then `playbackService.play()`
- Implement `seek(to:)` and update `currentTime` on success
- Propagate playback errors into `lastError` and `playbackState`

### Non-goals
- Real-time `currentTime` polling / timer-based updates (future slice)
- Album artwork loading (future)
- Format validation / Pro gating (Slice 5)
- UI implementation (Slice 5)
- Repeat / shuffle modes (future)
- Auto-advance to next track on completion (future)

### Dependencies
- Requires: Slice 3 complete — `AppState.load(urls:)` async, enriched `Track` in playlist
- Provides: Functional playback engine for Slice 5 (UI / Integration)

---

## Slice 4-A: FakePlaybackService Upgrade + Playback State in AppState

### Goal
Upgrade `FakePlaybackService` with call recording and error stubs so that
Slice 4-B/C/D tests can verify exactly which service methods are called and
simulate failure scenarios deterministically.

Also add `playbackState`, `currentTime`, and `duration` to `AppState` as
`@Published` properties, replacing the implicit dependency on
`playbackService.state` with observable state that SwiftUI views can bind to.

### Scope
- Upgrade `FakePlaybackService` in `FakeInfrastructure/FakeCoreProvider.swift`
  with per-method call counts, recorded arguments, and configurable error stubs
- Add `@Published private(set) var playbackState: PlaybackState = .idle` to `AppState`
- Add `@Published private(set) var currentTime: TimeInterval = 0` to `AppState`
- Add `@Published private(set) var duration: TimeInterval = 0` to `AppState`
- No new public methods on `AppState` in this sub-slice
- No changes to `PlaybackService` protocol

### Files
- `App/HarmoniaPlayer/HarmoniaPlayerTests/FakeInfrastructure/FakeCoreProvider.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/FakePlaybackServiceTests.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePlaybackStateTests.swift` (new)

### Public API shape — FakePlaybackService (upgraded)

```swift
final class FakePlaybackService: PlaybackService {

    // MARK: - Call Recording

    private(set) var loadCallCount = 0
    private(set) var loadedURLs: [URL] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var seekCallCount = 0
    private(set) var seekedToSeconds: [TimeInterval] = []

    // MARK: - Stub Configuration

    var stubbedLoadError: Error? = nil
    var stubbedPlayError: Error? = nil
    var stubbedSeekError: Error? = nil
    var stubbedDuration: TimeInterval = 0
    var stubbedCurrentTime: TimeInterval = 0

    // MARK: - PlaybackService

    var state: PlaybackState = .idle

    func load(url: URL) async throws {
        loadCallCount += 1
        loadedURLs.append(url)
        if let error = stubbedLoadError { throw error }
        state = .loading
    }

    func play() async throws {
        playCallCount += 1
        if let error = stubbedPlayError { throw error }
        state = .playing
    }

    func pause() async {
        pauseCallCount += 1
        state = .paused
    }

    func stop() async {
        stopCallCount += 1
        state = .stopped
    }

    func seek(to seconds: TimeInterval) async throws {
        seekCallCount += 1
        seekedToSeconds.append(seconds)
        if let error = stubbedSeekError { throw error }
    }

    func currentTime() async -> TimeInterval { stubbedCurrentTime }
    func duration() async -> TimeInterval { stubbedDuration }
}
```

### Public API additions — AppState

```swift
@MainActor
final class AppState: ObservableObject {
    // ... existing state ...

    // MARK: - Playback State (Slice 4-A)

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
}
```

### Done criteria
- `FakePlaybackService` compiles with all call-recording and stub properties
- Error stubs (`stubbedLoadError`, `stubbedPlayError`, `stubbedSeekError`) override
  normal state transitions when set
- `AppState` exposes `playbackState`, `currentTime`, `duration` as `@Published`
- All three are `.idle` / `0` / `0` on fresh `AppState` init
- All previous tests still green

### Suggested commit message
```
feat(slice-4a): add playbackState to AppState and upgrade FakePlaybackService with TDD

- Add @Published playbackState, currentTime, duration to AppState
- Upgrade FakePlaybackService with loadCallCount, playCallCount, pauseCallCount,
  stopCallCount, seekCallCount, seekedToSeconds call recording
- Add stubbedLoadError, stubbedPlayError, stubbedSeekError for error simulation
- Add stubbedDuration, stubbedCurrentTime for query stubs
- Add FakePlaybackServiceTests
- Add AppStatePlaybackStateTests for initial state verification
```

---

## Slice 4-B: play() / pause() / stop() Transport Controls

### Goal
Implement `play()`, `pause()`, and `stop()` on `AppState`, each delegating to
`playbackService` and keeping `playbackState` in sync. Errors from `play()`
are captured in `lastError` and reflected in `playbackState`.

### Scope
- Add `func play() async` — calls `playbackService.play()`, sets `playbackState = .playing`
- Add `func pause() async` — calls `playbackService.pause()`, sets `playbackState = .paused`
- Add `func stop() async` — calls `playbackService.stop()`, sets `playbackState = .stopped`,
  resets `currentTime` to `0`
- `play()` on throw: map error to `PlaybackError`, set `lastError` and
  `playbackState = .error(mapped)`
- No track loading in this sub-slice (loading is Slice 4-C)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePlaybackControlTests.swift` (new)

### Public API additions — AppState

```swift
// MARK: - Transport Controls

/// Start playback of the currently loaded track.
///
/// No-op if no track has been loaded via `play(trackID:)`.
/// On error: sets `lastError` and `playbackState = .error(mapped)`.
func play() async

/// Pause playback. Playback position is preserved.
func pause() async

/// Stop playback. Resets `currentTime` to 0.
func stop() async
```

### Error mapping helper (private)

```swift
private func mapToPlaybackError(_ error: Error) -> PlaybackError {
    if let playbackError = error as? PlaybackError { return playbackError }
    return .coreError(error.localizedDescription)
}
```

### Done criteria
- `play()` calls `playbackService.play()` and sets `playbackState = .playing`
- `play()` on error sets `lastError` and `playbackState = .error(...)`
- `pause()` calls `playbackService.pause()` and sets `playbackState = .paused`
- `stop()` calls `playbackService.stop()`, sets `playbackState = .stopped`,
  and resets `currentTime` to `0`
- All Slice 4-B tests green
- All previous tests still green

### Suggested commit message
```
feat(slice-4b): implement play/pause/stop transport controls in AppState with TDD

- Add play() async: delegates to playbackService, updates playbackState
- Add pause() async: delegates to playbackService, updates playbackState
- Add stop() async: delegates to playbackService, resets currentTime to 0
- Map playback errors to PlaybackError via private helper
- Set lastError on play() failure
- Add AppStatePlaybackControlTests
```

---

## Slice 4-C: play(trackID:) — Load and Play

### Goal
Upgrade `play(trackID:)` from a pure state-selection stub (Slice 2-C) into a
full load-and-play operation: set `currentTrack`, call
`playbackService.load(url:)`, then `playbackService.play()`. Update `duration`
after successful load.

### Scope
- Change `play(trackID:)` signature from synchronous to `async`
- Set `currentTrack` to matched track (or `nil` if not found — same as before)
- Call `playbackService.load(url: track.url)` → set `playbackState = .loading`
- On load success: update `duration` from `playbackService.duration()`
- Call `playbackService.play()` → set `playbackState = .playing`
- On load error: set `lastError`, `playbackState = .error(mapped)` — do not call `play()`
- On play error: set `lastError`, `playbackState = .error(mapped)`
- If track not found in playlist: no service calls, no state change

> **Impact on existing tests:**
> `AppStateTrackSelectionTests.testPlay_DoesNotCallPlaybackService` verifies
> that `play(trackID:)` makes no service calls — this assertion is **invalidated**
> by Slice 4-C. That test must be **removed or replaced** in this sub-slice with
> a test that verifies the load and play calls ARE made.
>
> All other `AppStateTrackSelectionTests` tests that were synchronous must be
> updated to `async` because `play(trackID:)` is now `async`.

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateTrackSelectionTests.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePlaybackTrackTests.swift` (new)

### Public API change

```swift
// Before (Slice 2-C):
func play(trackID: Track.ID)

// After (Slice 4-C):
func play(trackID: Track.ID) async
```

### Implementation shape

```swift
func play(trackID: Track.ID) async {
    guard let track = playlist.tracks.first(where: { $0.id == trackID }) else {
        currentTrack = nil
        return
    }
    currentTrack = track
    playbackState = .loading

    do {
        try await playbackService.load(url: track.url)
        duration = await playbackService.duration()
        try await playbackService.play()
        playbackState = .playing
    } catch {
        let mapped = mapToPlaybackError(error)
        lastError = mapped
        playbackState = .error(mapped)
    }
}
```

### Done criteria
- `play(trackID:)` is `async`
- Sets `currentTrack` before making service calls
- Calls `playbackService.load(url:)` with the track's URL
- Updates `duration` from service after successful load
- Calls `playbackService.play()` after successful load
- On load/play error: sets `lastError` and `playbackState = .error(...)`
- Invalid `trackID` → no service calls, no state change
- `AppStateTrackSelectionTests` updated: all sync tests made `async`
- `testPlay_DoesNotCallPlaybackService` removed; replaced by new test in
  `AppStatePlaybackTrackTests` that verifies calls ARE made
- All Slice 4-C tests green
- All previous tests still green

### Suggested commit message
```
feat(slice-4c): upgrade play(trackID:) to load and play track with TDD

- Make play(trackID:) async
- Call playbackService.load(url:) then playbackService.play()
- Set playbackState through .loading → .playing on success
- Update duration from service after successful load
- Set lastError and playbackState = .error on failure
- Update AppStateTrackSelectionTests: async, remove DoesNotCallPlaybackService
- Add AppStatePlaybackTrackTests for load-and-play coverage
```

---

## Slice 4-D: seek(to:)

### Goal
Implement `seek(to:)` on `AppState`: delegate to `playbackService.seek(to:)`,
update `currentTime` on success, and capture errors in `lastError`.

### Scope
- Add `func seek(to seconds: TimeInterval) async`
- Calls `playbackService.seek(to: seconds)`
- On success: set `currentTime = seconds`
- On error: set `lastError = mapped`; do not change `playbackState`
- No `playbackState` transition for seek (seeking does not stop/pause playback)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePlaybackControlTests.swift` (extend)

### Public API addition

```swift
/// Seek to an absolute position in the current track.
///
/// On success: updates `currentTime`.
/// On error: sets `lastError`. `playbackState` is not changed.
///
/// - Parameter seconds: Target playback position in seconds.
func seek(to seconds: TimeInterval) async
```

### Done criteria
- `seek(to:)` calls `playbackService.seek(to: seconds)`
- On success: `currentTime == seconds`
- On error: `lastError` is set; `playbackState` unchanged
- All Slice 4-D tests green
- All previous tests still green

### Suggested commit message
```
feat(slice-4d): implement seek(to:) in AppState with TDD

- Add seek(to:) async: delegates to playbackService
- Update currentTime on successful seek
- Set lastError on seek failure without changing playbackState
- Extend AppStatePlaybackControlTests with seek coverage
```

---

## Slice 4 TDD Matrix

### Test principles
- All tests deterministic — no real audio device or file I/O
- `FakePlaybackService` stubs control service behaviour
- **Swift 6 / Xcode 26:** Test class must be `@MainActor`; test methods calling
  `async` functions must be `async`

---

### Slice 4-A: FakePlaybackService + Initial State

| Test | Given | When | Then |
|------|-------|------|------|
| `testFake_Load_RecordsURL` | Any | `load(url)` | `loadedURLs == [url]` |
| `testFake_Load_StubbedError_Throws` | `stubbedLoadError = err` | `load(url)` | Throws error |
| `testFake_Load_NoError_SetsLoadingState` | No stub | `load(url)` | `state == .loading` |
| `testFake_Play_RecordsCall` | Any | `play()` | `playCallCount == 1` |
| `testFake_Play_StubbedError_Throws` | `stubbedPlayError = err` | `play()` | Throws error |
| `testFake_Pause_RecordsCall` | Any | `pause()` | `pauseCallCount == 1` |
| `testFake_Stop_RecordsCall` | Any | `stop()` | `stopCallCount == 1` |
| `testFake_Seek_RecordsSeconds` | Any | `seek(to: 42.0)` | `seekedToSeconds == [42.0]` |
| `testFake_Seek_StubbedError_Throws` | `stubbedSeekError = err` | `seek(to:)` | Throws error |
| `testFake_Duration_ReturnsStubbedValue` | `stubbedDuration = 180.0` | `duration()` | Returns `180.0` |
| `testAppState_InitialPlaybackState_IsIdle` | Fresh AppState | Read `playbackState` | `.idle` |
| `testAppState_InitialCurrentTime_IsZero` | Fresh AppState | Read `currentTime` | `0` |
| `testAppState_InitialDuration_IsZero` | Fresh AppState | Read `duration` | `0` |

---

### Slice 4-B: Transport Controls

| Test | Given | When | Then |
|------|-------|------|------|
| `testPlay_CallsPlaybackServicePlay` | Any | `await play()` | `fakeService.playCallCount == 1` |
| `testPlay_SetsPlayingState` | No error stub | `await play()` | `playbackState == .playing` |
| `testPlay_OnError_SetsLastError` | `stubbedPlayError` set | `await play()` | `lastError != nil` |
| `testPlay_OnError_SetsErrorState` | `stubbedPlayError` set | `await play()` | `playbackState == .error(...)` |
| `testPause_CallsPlaybackServicePause` | Any | `await pause()` | `fakeService.pauseCallCount == 1` |
| `testPause_SetsPausedState` | Any | `await pause()` | `playbackState == .paused` |
| `testStop_CallsPlaybackServiceStop` | Any | `await stop()` | `fakeService.stopCallCount == 1` |
| `testStop_SetsStoppedState` | Any | `await stop()` | `playbackState == .stopped` |
| `testStop_ResetsCurrentTimeToZero` | `currentTime > 0` | `await stop()` | `currentTime == 0` |

---

### Slice 4-C: play(trackID:) — Load and Play

| Test | Given | When | Then |
|------|-------|------|------|
| `testPlayTrack_SetsCurrentTrack` | Valid trackID | `await play(trackID:)` | `currentTrack == track` |
| `testPlayTrack_CallsLoad` | Valid trackID | `await play(trackID:)` | `fakeService.loadCallCount == 1` |
| `testPlayTrack_LoadsCorrectURL` | Valid trackID | `await play(trackID:)` | `fakeService.loadedURLs[0] == track.url` |
| `testPlayTrack_CallsPlay` | Valid trackID, no error | `await play(trackID:)` | `fakeService.playCallCount == 1` |
| `testPlayTrack_SetsPlayingState` | Valid trackID, no error | `await play(trackID:)` | `playbackState == .playing` |
| `testPlayTrack_UpdatesDuration` | `stubbedDuration = 240.0` | `await play(trackID:)` | `duration == 240.0` |
| `testPlayTrack_LoadError_SetsLastError` | `stubbedLoadError` set | `await play(trackID:)` | `lastError != nil` |
| `testPlayTrack_LoadError_SetsErrorState` | `stubbedLoadError` set | `await play(trackID:)` | `playbackState == .error(...)` |
| `testPlayTrack_LoadError_DoesNotCallPlay` | `stubbedLoadError` set | `await play(trackID:)` | `fakeService.playCallCount == 0` |
| `testPlayTrack_InvalidID_NoServiceCalls` | Invalid trackID | `await play(trackID:)` | `loadCallCount == 0` |
| `testPlayTrack_InvalidID_NilsCurrentTrack` | Invalid trackID | `await play(trackID:)` | `currentTrack == nil` |

---

### Slice 4-D: seek(to:)

| Test | Given | When | Then |
|------|-------|------|------|
| `testSeek_CallsPlaybackServiceSeek` | Any | `await seek(to: 30.0)` | `fakeService.seekCallCount == 1` |
| `testSeek_PassesCorrectSeconds` | Any | `await seek(to: 30.0)` | `fakeService.seekedToSeconds[0] == 30.0` |
| `testSeek_Success_UpdatesCurrentTime` | No error stub | `await seek(to: 30.0)` | `currentTime == 30.0` |
| `testSeek_Error_SetsLastError` | `stubbedSeekError` set | `await seek(to:)` | `lastError != nil` |
| `testSeek_Error_DoesNotChangePlaybackState` | `stubbedSeekError` set, `playbackState = .playing` | `await seek(to:)` | `playbackState == .playing` |

---

## Slice 4 Completion Gate

### Required before Slice 5

- ✅ `FakePlaybackService` has full call recording and error stubs
- ✅ `AppState` publishes `playbackState`, `currentTime`, `duration`
- ✅ `play()` delegates to service and updates `playbackState`
- ✅ `pause()` delegates to service and updates `playbackState`
- ✅ `stop()` delegates to service, resets `currentTime` to `0`
- ✅ `play(trackID:)` is `async` and calls `load()` then `play()` on service
- ✅ `duration` updated after successful load
- ✅ `seek(to:)` delegates to service and updates `currentTime` on success
- ✅ All playback errors captured in `lastError` and `playbackState = .error(...)`
- ✅ `AppStateTrackSelectionTests` updated to `async`; stale `DoesNotCallPlaybackService` test removed
- ✅ All Slice 4 tests green
- ✅ All Slice 1 / 2 / 3 tests still green
- ✅ No module boundary violations

### Verification

```bash
⌘U in Xcode
```

Expected output:
```
Slice 1 tests:   All passing
Slice 2 tests:   All passing
Slice 3 tests:   All passing
Slice 4-A tests: All passing
Slice 4-B tests: All passing
Slice 4-C tests: All passing
Slice 4-D tests: All passing
```

---

## Related Slices

- **Slice 1 (Foundation)** — `PlaybackService` injected into `AppState`
- **Slice 2 (Playlist Management)** — `play(trackID:)` stub and `currentTrack`
- **Slice 3 (Metadata Extraction)** — Enriched `Track` instances consumed here
- **Slice 5 (Integration)** — UI connects to `AppState` playback API; real `HarmoniaCore` adapters replace fakes
