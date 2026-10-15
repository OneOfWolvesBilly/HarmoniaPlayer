# Slice 17 Micro-slices Specification

## Purpose

On 2026-09-22 the shipped 1.0.0 process caught an exception on the main
thread and kept running for seven days with no windows, a broken
accessibility tree, dead menus, and a ⌘Q that did nothing, until an
unrelated fatal error finally ended it on 2026-09-29. AppKit's default is
to catch exceptions raised during main-thread event dispatch and continue
the run loop; Cocoa is not exception-safe, so what survives is a corrupted
process the user can neither use nor quit. A process in that state is not
an application state at all — it must be removed, not preserved.

This slice sets the AppKit policy under which an uncaught main-thread
exception terminates the process immediately and leaves a crash report,
adds a debug-only trigger to prove it in the real app, and pins the
policy with a unit test. The window-lifecycle decisions of Slice 9-AA
(D5: closing the main window may leave a no-window state, recovered via
Dock or Window → Main Window) are unchanged.

## Slice 17 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 17-A | Crash-on-exception policy + debug raise trigger + registration test | Free | ✅ |

### Goals

- An `NSException` that AppKit would otherwise swallow on the main thread
  terminates the process at once; no zombie process survives it.
- The termination writes a macOS crash report (`.ips`) whose crashed
  thread names the AppKit exception path, so the next occurrence is
  visible instead of silent.
- The policy is registered at launch through `UserDefaults` — the only
  effective mechanism — and a hosted unit test guards the registration.
- A Debug-only launch argument raises a test exception inside the app so
  the termination can be verified end to end without shipping the
  trigger.

### Out of Scope

- Quitting when the last window closes
  (`applicationShouldTerminateAfterLastWindowClosed`) → withdrawn by
  Chen; 9-AA D5 stays; no destination.
- Identifying the exception behind the 2026-09-22 incident → not
  recoverable (the day's unified log is rotated away; the crash report
  carries only the swallowed-exception marker). The policy exists so the
  next occurrence produces a report; the investigation opens from that
  report → BL-17A-02.
- Recording the throw site (exception name, reason, call stack) of an
  AppKit-caught exception before termination → verified impossible under
  the SwiftUI lifecycle (SwiftUI instantiates its own `NSApplication`
  subclass and ignores `NSPrincipalClass`, so `reportException:` cannot be
  overridden); no destination.
- Persisting `volume` and `activePlaylistIndex` at change time (today they
  reach disk only through `saveState()`) → BL-17A-01, its own v1.0.1
  slice.
- The final 2026-09-29 fatal (`_objc_fatal` during a SwiftUI button
  gesture) → a symptom of the corrupted process, not investigated
  separately; no destination.
- Any change to window lifecycle, Dock reopen, or the Mini Player
  exclusivity → 9-AA / the window-menu declarative draft, unchanged.
- Version and build-number settings → release preparation for v1.0.1
  (see Release); `MARKETING_VERSION` is already 1.0.1 and this slice does
  not touch it.

### Constraints

- **C1 — Registration mechanism.** `NSApplicationCrashOnExceptions` is
  read from `NSUserDefaults` at exception time. Info.plist forms
  (`INFOPLIST_KEY_*` or the physical `Info.plist`) are verified
  ineffective and must not be used; the default is registered in the
  registration domain (`UserDefaults.register(defaults:)`), which is
  volatile and never written to the app's preferences.
- **C2 — Reach of the policy.** It changes only exceptions AppKit would
  otherwise catch: those raised on the main thread inside the run loop
  (event dispatch, `Timer`, `RunLoop.perform`, main-actor jobs).
  Exceptions on secondary threads and inside GCD blocks already
  terminate the process today and are unaffected.
- **C3 — No last-resort flush.** Termination through the policy skips
  `applicationWillTerminate` and the `willTerminateNotification` sink, so
  `saveState()` does not run. Only `volume` and `activePlaylistIndex`
  changes since the last playlist mutation, repeat, or shuffle change can
  be lost; every other persisted value is written at change time. Accepted
  for this slice: the corrupted process could not save either (the 9/29
  ⌘Q never reached termination). BL-17A-01 closes the window within the
  same release.
- **C4 — Debug-only trigger.** The raise trigger is compiled under
  `#if DEBUG` only; the Release binary contains neither the argument
  string nor the raise.
- **C5 — Warning baseline.** `HarmoniaPlayerApp.swift` (14) and
  `AppDelegate.swift` (2) are re-measured after the change and keep their
  Slice 12 baseline counts; the new test file builds warning-free.
- **C6 — TDD.** Red-green; the red set is reported from the working tree;
  "是請執行" gates the green phase; red, green, and docs land as one
  atomic code commit (Slice 16 protocol). Termination itself is verified
  manually (Slice 9-AA precedent) — an automated crash test would raise
  a macOS crash dialog and write a report on every ⌘U.

### Dependencies

- None on other slices. External behaviour (AppKit swallow scope,
  registration mechanism and timing, SwiftUI principal-class behaviour,
  crash-report shape) was verified before this freeze; the sources and
  the probe matrix are in the never-committed draft.

### Release

Ships in **v1.0.1** (Chen's decision, 2026-09-30); the release's full
contents are listed in the development plan §11.14.

---

## Slice 17-A: Crash-on-exception policy ✅

### Goal

Make an AppKit-caught main-thread exception fatal at launch-time
registration, prove it in the real app through a Debug-only trigger, and
guard the registration with a hosted unit test.

### Scope (FROZEN as of spec commit)

**Policy registration** — `macOS/Free/HarmoniaPlayerApp.swift`, `init()`,
first statement:

```swift
UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
```

with a doc comment stating the policy (AppKit catches main-thread
exceptions by default and leaves a corrupted, unquittable process; this
default makes such an exception terminate the process and write a crash
report; it is a user default, not an Info.plist key). The existing
AppleLanguages bootstrap follows unchanged.

**Debug trigger** — `macOS/Free/AppDelegate.swift`,
`applicationDidFinishLaunching(_:)`, wrapped in `#if DEBUG`: when
`ProcessInfo.processInfo.arguments` contains `--hp-raise-test-exception`,
schedule a one-shot `Timer` (1 s, main run loop) whose handler raises
`NSException(name: .genericException, reason: "Test exception raised by
--hp-raise-test-exception", userInfo: nil)`. The `Timer` path is a
verified AppKit-swallowed path (without the policy the process survives
it; with the policy it terminates). The double-dash form keeps
`NSUserDefaults` from parsing the argument into its arguments domain.
The file header gains one sentence naming the trigger.

**Unit test** — new `HarmoniaPlayerTests/SharedTests/HarmoniaPlayerAppTests.swift`
(the test target is hosted in the app, so `HarmoniaPlayerApp.init` has
run before the test executes): reads the registration domain
(`UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)`)
and asserts the key is `true`. Reading the registration domain rather
than `bool(forKey:)` pins that the value comes from the launch
registration, not from a persisted preference.

**Docs (at green):**

| Doc | Change |
|---|---|
| `development_guide.md` | project-structure comments for `HarmoniaPlayerApp.swift` (launch bootstrap + crash-on-exception policy) and `AppDelegate.swift` (debug raise trigger); a short "Verifying the crash-on-exception policy" note in the testing / troubleshooting area giving the `--hp-raise-test-exception` recipe and the expected `.ips` |
| `implementation_guide_swift.md` | §6.1 `HarmoniaPlayerApp` example gains the `register(defaults:)` line and its comment |
| `user_guide.md` | Troubleshooting: new entry "The app quit unexpectedly" — the app terminates rather than continuing in a broken state; a crash report is written to `~/Library/Logs/DiagnosticReports` (Console → Crash Reports); Report a bug: add "the crash report, if the app quit unexpectedly" to the list |

**Docs (at close-out):** this spec (status ticks, execution amendments),
`HarmoniaPlayer_development_plan.md` (slice table tick),
`slice_12_micro.md` (Slice 17-A re-measurement note).

No `api_reference.md` / `module_boundary.md` / `architecture.md` change
(no public API, persistence key, or HarmoniaCore surface; the registration
domain is not a persisted key). `architecture.md` untouched → the
HarmoniaCore 5-area audit does not apply.

### Acceptance Criteria

1. AC1: `grep -n "NSApplicationCrashOnExceptions" App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift`
   matches exactly one `register(defaults:)` statement, and the key
   appears in no `Info.plist`, `project.pbxproj`, or `.entitlements` file
   under `App/`.
2. AC2: `HarmoniaPlayerAppTests.testLaunch_RegistersCrashOnExceptionsDefault`
   passes; full ⌘U suite green at 519 passed / 5 skipped / 0 failed
   (pre-slice 518 / 5 on 7a0dcbb, the Slice 16-A close-out measurement,
   + 1); UITests unchanged (9).
3. AC3 (manual, Debug build): launched with `--hp-raise-test-exception`,
   the process is gone within 5 s of its window appearing (`pgrep -f
   "Harmonia Player"` empty) and a new
   `~/Library/Logs/DiagnosticReports/Harmonia Player-<date>.ips` exists
   whose exception type is `EXC_BREAKPOINT (SIGTRAP)` and whose crashed
   thread's top frames are `+[NSApplication _crashOnException:]` and
   `-[NSApplication reportException:]`.
4. AC4 (manual, same Debug build, no argument): normal launch, playback,
   and ⌘Q; the process exits within ~1 s of ⌘Q and `playlists.json`'s
   modification time updates.
5. AC5: `strings` on the Release product's executable contains no
   `hp-raise-test-exception`; on the Debug product it does.
6. AC6: `slice_12_micro.md` — `HarmoniaPlayerApp.swift` keeps 14 and
   `AppDelegate.swift` keeps 2 after re-measurement;
   `HarmoniaPlayerAppTests.swift` builds with zero warnings. Re-measurement
   note lands with the close-out.
7. AC7: `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` over the slice's added
   `.swift` lines returns no forbidden match.
8. AC8: every doc listed under Scope → Docs has been read in full and
   cross-checked against source, not grep-patched.

### Out of Scope

- See slice-level Out of Scope.

### Deferred Backlog

1. BL-17A-01 — persist `volume` and `activePlaylistIndex` at change time
   (today only via `saveState()`), closing the C3 loss window. Target: its
   own v1.0.1 slice, numbered when it opens (required for v1.0.1 by
   Chen's 2026-09-30 decision).
2. BL-17A-02 — investigate the exception class behind the 2026-09-22
   incident once a crash report produced under this policy exists.
   Target: its own slice, opened when such a report arrives.

### Files

- HarmoniaPlayer macOS layer:
  - modify `macOS/Free/HarmoniaPlayerApp.swift` (registration + doc comment)
  - modify `macOS/Free/AppDelegate.swift` (`#if DEBUG` trigger + header sentence)
- Tests:
  - add `HarmoniaPlayerTests/SharedTests/HarmoniaPlayerAppTests.swift`
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change
  (`PBXFileSystemSynchronizedRootGroup`, Slice 13-A execution amendment);
  `Info.plist` — no change (C1)
- Docs at green: `development_guide.md`, `implementation_guide_swift.md`,
  `user_guide.md`
- Docs at close-out: `slice_12_micro.md`, this spec,
  `HarmoniaPlayer_development_plan.md`

### TDD matrix

| # | Test | Given | When | Then | Test File Decision |
| --- | --- | --- | --- | --- | --- |
| 1 | `testLaunch_RegistersCrashOnExceptionsDefault` | the hosted test bundle is running inside the launched app (`HarmoniaPlayerApp.init` has executed) | read `UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)["NSApplicationCrashOnExceptions"]` | `as? Bool == true` | New `SharedTests/HarmoniaPlayerAppTests.swift` |

Red phase — the test file is added; no source changes. Expected red (1):
row 1 (the key is absent from the registration domain today). Green =
the single `register(defaults:)` statement.

Not unit-testable, verified manually (AC3–AC5): the termination itself
and the crash report — they require a real AppKit run loop and a
process death, and an automated version would crash the app on every
⌘U (C6).

Execution amendments (recorded at close-out):

- The observed red set matched the prediction: row 1 failed with
  `("nil") is not equal to ("Optional(true)")`, confirming that the hosted
  test runs after `HarmoniaPlayerApp.init`. Green on a clean build:
  533 tests in the run, 528 passed / 5 skipped / 0 failed = 519 unit
  tests passed + 5 skipped + 9 UITests, exactly pre-slice + 1.
- AC5's Debug-side check inspects `Contents/MacOS/Harmonia Player.debug.dylib`,
  not the Debug product's stub executable: the Debug configuration links
  the app's code into that dylib (Xcode debug-dylib support), so the stub
  carries no string literals at all. The Release executable is a single
  Mach-O and contains no `hp-raise-test-exception`; the Debug dylib
  contains it once.
- AC3 observed on the Debug build: the process was gone about 2 s after
  launch detection; the report `Harmonia Player-2026-10-01-105446.ips`
  carries `app_version 1.0.1`, `build_version 3`, `EXC_BREAKPOINT
  (SIGTRAP)`, termination `byProc: exc handler`, crashed thread
  `+[NSApplication _crashOnException:]` ← `-[NSApplication reportException:]`
  ← `-[NSApplication run]`.
- AC4 observed on the same Debug build without the argument: alive after
  4.5 s; ⌘Q posted to the PID (CGEvent, after the focus gate) → process
  gone in 0.909 s; `playlists.json` modification time advanced.
- Warning re-measurement on the clean build: `HarmoniaPlayerApp.swift`
  14 and `AppDelegate.swift` 2 unchanged; `HarmoniaPlayerAppTests.swift` 0.

### Implementation notes

- Registration in `App.init` runs before `NSApplication` exists; AppKit
  consults the default when an exception reaches its handler, so any
  launch-time site is effective (verified: `App.init` and
  `applicationDidFinishLaunching` both work). `App.init` is chosen because
  it already owns the launch-time `UserDefaults` bootstrap.
- Crash-report shape under the policy: `EXC_BREAKPOINT / SIGTRAP`,
  termination `byProc: exc handler`, crashed thread
  `+[NSApplication _crashOnException:] ← -[NSApplication reportException:]
  ← -[NSApplication run]`. The throw site is not in the report (the
  exception was caught and unwound before AppKit decided to crash) and no
  `lastExceptionBacktrace` is recorded; the report proves an exception
  crash and its time. Exceptions on GCD/secondary threads keep today's
  uncaught-exception report with the throw stack.
- The trigger raises from a `Timer` because the AppKit-swallowed paths
  verified are event dispatch, `Timer`, `RunLoop.perform`, and main-actor
  jobs; a `DispatchQueue.main` block would terminate the process even
  without the policy and would prove nothing.
- Manual recipe (AC3): build Debug, then
  `open -a "<Debug product>.app" --args --hp-raise-test-exception`; the
  window appears, the process dies about 1 s later, macOS shows the
  "unexpectedly quit" dialog (Ignore), and the report is in
  `~/Library/Logs/DiagnosticReports`. Only one Harmonia Player instance
  may run at a time (App Store build and Xcode build share the bundle ID
  and `playlists.json`).
- Token discipline: `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` on added
  lines before the commit; the `AppDelegate.swift` header stays free of
  slice tokens.
