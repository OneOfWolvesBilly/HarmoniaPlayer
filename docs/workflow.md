# HarmoniaPlayer Development Workflow

This document defines the SDD → TDD → commit cycle used in HarmoniaPlayer,
together with the commit atomicity rules and cross-repo coordination when
a slice touches HarmoniaCore.

> For cross-repo setup (local path vs GitHub tag, subtree split, etc.) see
> [Development Guide](development_guide.md). This document focuses on the
> per-slice engineering workflow.

---

## 1. Core Cycle: SDD → TDD Red → Confirm → TDD Green → Commit

Every change — feature, fix, refactor — follows the same five-stage cycle:

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│   SDD    │ → │ TDD red  │ → │ confirm  │ → │TDD green │ → │  commit  │
│  (spec)  │   │  (tests) │   │  ("是請   │   │  (code)  │   │ (atomic) │
│          │   │          │   │ 執行")    │   │          │   │          │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

1. **SDD (Spec-Driven Development)** — write the slice spec first.
2. **TDD Red** — write the failing tests based on the spec.
3. **Confirm** — **implementation does not begin until explicit
   confirmation is given.** The developer must explicitly say "是請執行"
   (yes, please execute) before code is written. This is a hard gate.
4. **TDD Green** — write the minimal code to make the tests pass.
5. **Commit** — atomic commit following the project's commit rules.

The confirmation step exists because plans drift — between writing the
spec and writing code, the developer may see a better approach. Making
confirmation explicit forces the team to decide before anyone types Swift.

---

## 2. Engineering Workflow Rules

Five rules that apply to every change, especially during investigation:

1. **Always start with investigation** — read the actual code, logs, error
   messages; never answer from memory.
2. **List hypotheses before implementing fixes** — generate at least three
   possible causes; identify the most likely one.
3. **Prefer minimal changes** — avoid rewriting large sections; maintain
   compatibility.
4. **Verify every fix with tests or commands** — show evidence, not
   assertions.
5. **Never claim success without verification** — green tests, passing
   build, or reproduced behaviour. No claims without evidence.

Violating any of these creates technical debt that compounds across slices.

---

## 3. Spec-Driven Development (SDD)

### 3.1 Two-spec-file pattern

Each slice produces two spec files in `docs/slice/`:

| File | Content | Committed? |
|------|---------|-----------|
| `slice_0X_micro.md` | Concise reference: Goal / Scope / Files / API / TDD plan / Commit plan | **Yes** — in repo |
| `HarmoniaPlayer_slice_X_micro.md` | Detailed developer version: working notes, alternatives considered, rough edges | **No** — local-only, ignored by git |

The committed spec is the team-facing summary. The local spec is the
developer's scratch pad and never pushed. See
[Documentation Strategy](documentation_strategy.md) §5 for rationale.

### 3.2 Committed spec structure

`slice_NN_micro.md` must contain these sections, in order:

1. **Goal** — one-sentence statement of what shippable behaviour this slice adds
2. **Scope** — in-scope bullets and explicit non-goals
3. **Files** — every `.swift` file that will be created or modified
4. **API** — new or changed public signatures, as Swift code blocks
5. **TDD Plan** — ordered list of tests, each one small and focused
6. **Commit Plan** — ordered list of commits, each one atomic

### 3.3 Spec commit precedes code commit

The spec is always committed **before** any code for the slice:

```
feat(docs): add slice 9-B spec (tag editor basic fields)
feat(slice 9-B): add TagWriterPort + AVMutableTagWriterAdapter
feat(slice 9-B): add HarmoniaTagWriterAdapter integration wrapper
feat(slice 9-B): add tag editor UI with save success/fail alerts
```

Four commits — one for the spec, three for code. Never squash the spec
into code commits.

---

## 4. Test-Driven Development (TDD)

### 4.1 Red → Confirm → Green

- **Red** — write tests for the first commit in the plan. Run them.
  They must fail (no code exists yet).
- **Confirm** — await explicit "是請執行" before proceeding.
- **Green** — implement the minimum code to make the tests pass. Run them.
  They must all pass.

Repeat for each commit in the plan.

### 4.2 Test integrity

**One operation per test.** Setup and seed operations must clear the
undo stack (or equivalent state) before the operation under test:

```swift
func testPlayCallsServicePlay() async {
    // Setup: seed a track so play() can proceed past the guards.
    // seedTracks() calls play(trackID:) internally, which bumps counts
    // and registers undo actions.
    await seedTracks()

    // Clear counts and undo stack so the next operation is isolated.
    fakePlaybackService.resetCounts()
    sut.undoManager.removeAllActions()

    // Operation under test — assertions target THIS call only.
    await sut.play()

    XCTAssertEqual(fakePlaybackService.playCallCount, 1)
    XCTAssertEqual(sut.playbackState, .playing)
}
```

Never mix setup operations with the asserted operation. If the setup
bumps a counter to 1 and the operation under test bumps it to 2, the
assertion must target 2 cleanly — not "2 because setup already did 1."
The test must be readable in isolation.

### 4.3 Fix mocks, not tests

When a mock doesn't support a test case, **fix the mock** — don't patch
the test to work around a poor mock design. Examples of "patching the test"
that should be refused:

- Using a non-optional `Float = 1.0` default where the test needs to
  verify "not set yet" — the mock should store `Float?` so `nil` means
  "not set"
- Adding `if mock.didSet { ... }` guards in the test — the mock should
  expose `lastSetValue: T?` instead
- Commenting out an assertion because the mock can't distinguish cases
  — the mock should be extended to record what the test needs

Poor mocks create flaky tests and hide bugs. Fix at the source.

### 4.4 Test class conventions (Swift 6)

AppState is `@MainActor`, so test classes using it must also be
`@MainActor`. XCTest runs `@MainActor`-isolated classes on the main actor
automatically — no `await MainActor.run {}` boilerplate needed.

```swift
@MainActor
final class AppStatePlaybackControlTests: XCTestCase {
    // ...
}
```

See [Development Guide](development_guide.md) §7 for the full test
template including `UserDefaults(suiteName:)` isolation.

---

## 5. Commit Rules

### 5.1 Atomicity

**One logical change per commit.** If a commit's description needs the
word "and" to connect two concerns, split it.

- Spec commit is always separate from code commit
- Bug fix is separate from refactor
- Test addition is separate from implementation (within a single commit
  in TDD Green, yes — but across features, separate)

### 5.2 Commit message format

```
<type>(<scope>): <description>

- <fact>
- <fact>
- <fact>
```

**Rules:**
- Bullet points use `-` only; no `*` or `•`
- Facts only in bullets; no prose paragraphs in the body
- No explanatory suffixes like "(for clarity)" or "(this fixes X)"
- Spec bullet text must be reproduced verbatim from the slice spec

### 5.3 HarmoniaPlayer commit types

| Type | Scope | Meaning |
|------|-------|---------|
| `feat(slice X-Y)` | Active slice | New feature / behavior |
| `fix(slice X)` | Active slice | Bug fix within the active slice |
| `refactor(slice X)` | Active slice | Internal restructuring, no behaviour change |
| `test(slice X)` | Active slice | Test-only change |
| `docs(...)` | File or topic | Documentation update |
| `chore(...)` | Area | Maintenance (renames, cleanup) |

### 5.4 Multi-commit delivery pattern

When a slice produces multiple commits, deliver files **one commit at a
time, sequentially.** Each commit builds on the last. Never organise
deliverables into parallel folders where shared files appear in multiple
commits simultaneously — that makes review impossible.

---

## 6. Cross-Repo Coordination

If a slice affects HarmoniaCore (new port, changed service, new adapter),
the order across repos is:

1. **HarmoniaCore** — spec commit, then implementation commit(s), then
   HarmoniaCore-local tests green
2. **HarmoniaCore-Swift** — if a new release is needed, subtree split +
   tag (see [Development Guide](development_guide.md) §6.2)
3. **HarmoniaPlayer** — update SPM pin (deploy mode) or rely on local
   path (dev mode); add Integration Layer adapter changes; then AppState
   + Views; then HarmoniaPlayer tests green
4. **Slice spec** — mark slice complete only after both repos' tests are
   green

**Boundary order rule:** commits always land in boundary order
(HarmoniaCore → HarmoniaPlayer). Do not ship app features that depend
on unpushed HarmoniaCore changes.

For the detailed cross-repo mechanics (local path vs tag, subtree split
workflow), see [Development Guide](development_guide.md) §6.

---

## 7. Definition of Done

A slice is done only when all of these are satisfied:

- Slice spec exists and has been committed
- All tests in the TDD plan are green
- All commits in the Commit plan have landed in the correct order
- No `import HarmoniaCore` outside the 3 Integration Layer files
- No Xcode warnings introduced
- If HarmoniaCore changed: HarmoniaCore tests are green and the SPM pin
  is updated (deploy mode) or the local path resolves (dev mode)
- Slice spec in `docs/slice/` reflects the shipped behaviour
- No feature claimed in the spec that is not backed by tests + code

---

## 8. Non-Negotiable Rules

- **No implementation without "是請執行"** — explicit confirmation is the gate
- **No `import HarmoniaCore` in View layer**
- **No UI logic inside HarmoniaCore**
- **No AVFoundation / StoreKit / OSLog in Application Layer**
- **No `String` payload across the module boundary** (`PlaybackError` is typed codes only)
- **No squashed spec-and-code commits**
- **No claiming completion without test coverage**
- **No app feature added first and core contract fixed later** — spec changes in HarmoniaCore first

---

## 9. Summary

The actual HarmoniaPlayer workflow is:

```
SDD (spec committed)
  → TDD red (tests written and failing)
    → confirm ("是請執行")
      → TDD green (code written, tests passing)
        → commit (atomic, formatted)
          → next commit in the slice plan
            → ... until the slice is complete
              → slice spec marked complete
```

For cross-repo slices, expand the TDD loop around HarmoniaCore first,
then HarmoniaCore-Swift release sync (if needed), then HarmoniaPlayer
integration.

---

## 10. Cross-References

- [Development Guide](development_guide.md) — setup, cross-repo workflow, test doubles
- [Documentation Strategy](documentation_strategy.md) — spec file pattern, commit conventions for docs
- [Module Boundaries](module_boundary.md) — enforcement of the non-negotiable rules
- [Implementation Guide (Swift)](implementation_guide_swift.md) — test template, @MainActor patterns