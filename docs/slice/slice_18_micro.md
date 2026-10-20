# Slice 18 Micro-slices Specification

## Purpose

This slice is a follow-up to **Slice 9-AA** (`slice_09_window_menu_micro.md`),
the slice that made the main window reopenable after it is closed.
9-AA changed the app's window design: the main window became a single
`Window` scene with the id `"main"` instead of an id-less `WindowGroup`;
an application delegate was added so a Dock click can bring the main
window back; the Mini Player and the main window became two modes of one
player surface (opening one closes the other); the automatic
Window-menu items of each window were removed; and matching a window
to its scene was fixed to accept the identifier macOS actually assigns
(`main-AppWindow-1`, not the bare `main`). 9-AA's doc updates covered
`user_guide.md` only, so three developer-facing descriptions still show
the pre-9-AA design. Readers of those pages get a picture that no longer
matches the code:

- **`development_guide.md` §9.7 (window identification)** still says
  the main window is a `WindowGroup` without an `id`, so the app has to
  tag the window itself to find it later.
- **`implementation_guide_swift.md` §6.1 (App entry point)** still
  shows the pre-9-AA entry: a `WindowGroup`, a StoreKit purchase
  manager, no application delegate, and no removal of the automatic
  Window-menu items.
- **The header comment of `AppDelegate.swift`** — the file 9-AA added —
  still describes 9-AA's first draft of the rules: opening the Mini
  Player *hides* the main window, and a Dock click shows the main
  window even while the Mini Player is visible. The shipped rules are
  that opening the Mini Player *closes* the main window, and a Dock
  click brings the main window back only when neither window exists.

The mismatch was noticed during Slice 17, whose full read of the living
docs is how it surfaced; Slice 17 was scoped to the crash-on-exception
policy and left this for its own slice. This slice corrects the three
descriptions so they say what 9-AA shipped. It changes documentation
text and one comment block; it does not change behaviour, code, or
file layout.

## Slice 18 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 18-A | Correct the three window descriptions (development guide §9.7, implementation guide §6.1, `AppDelegate.swift` header) | Free | ✅ |

### Goals

- A reader of `development_guide.md` §9.7 learns the real window set:
  one main `Window` with id `"main"`, how macOS derives the window's
  identifier from that id, how the app matches windows to scenes, and
  that an old helper (`MainWindowIdentitySetter`) still exists alongside
  the new mechanism.
- A reader of `implementation_guide_swift.md` §6.1 sees an entry-point
  example in which every line exists in the real
  `HarmoniaPlayerApp.swift`.
- A reader of `AppDelegate.swift` gets the real window rules from the
  header without opening the window-menu slice spec.

### Out of Scope

- **Removing the old window-tagging helper.** `ContentView` still
  attaches `MainWindowIdentitySetter`, which overwrites the main
  window's identifier with the plain string `"main"`; and the Mini
  Player's own close handler (`MiniPlayerView.swift`) still looks the
  main window up by that exact string under a comment that calls it the
  "main WindowGroup". Both predate the current design and both work only
  because the helper is still there. Removing them is part of the
  planned window-coordinator refactor (recorded in
  `slice_window_menu_declarative_draft.md`); this slice only *describes*
  that the helper exists.
- **Old slice and version tokens in `HarmoniaPlayerApp.swift`** (a
  comment reading "v0.1 frozen … Re-enable in v0.2" and a "(Slice 9-K)"
  marker). These belong to Slice 10, the slice that strips such tokens
  from source files.
- **Other outdated passages found while reading the two guides end to
  end** (the development guide's local-folder description of the
  HarmoniaCore dependency, its incomplete `nonisolated deinit` list, the
  implementation guide's `StoreKitIAPManager` example, methods missing
  from its provider / adapter / factory examples, the test-class example
  in both guides, and a duplicated section number). None of them
  concerns windows; they were corrected in the documentation-only commit
  `65d311c` (`docs(audit)`) made before this slice opened, following the
  precedent of `cfbfbb3`.
- `architecture.md`, `api_reference.md`, `module_boundary.md`, and
  `user_guide.md` are not touched: nothing about the public API,
  persistence, keyboard shortcuts, or HarmoniaCore changes. Because
  `architecture.md` is untouched, the HarmoniaCore five-area audit does
  not apply.

### Constraints

- **Text and comments only.** The only source file touched is
  `macOS/Free/AppDelegate.swift`, and only its `//` header lines; no
  behaviour, signature, or file-layout change anywhere.
- **Excerpts must be true.** A code example may leave lines out, but
  every line it shows must exist in the file it quotes (same modifiers,
  labels, type names, argument values). Only comment text inside an
  example may be shortened.

### Dependencies

- The window design this slice describes is already shipped (Slices
  9-AA and 9-AB). Nothing depends on an unopened slice.

### Release

Documentation only; the shipped binary is unaffected, so this is not an
item of the v1.0.1 contents list. It lands on `main` and is included in
whatever tag is cut next.

---

## Slice 18-A: Correct the three window descriptions ✅

### Goal

Rewrite the window table and the paragraph after it in
`development_guide.md` §9.7, replace the `HarmoniaPlayerApp` example in
`implementation_guide_swift.md` §6.1 with an excerpt of the shipped
file, and replace the window-rules paragraph in the `AppDelegate.swift`
header — the three places that still describe the pre-9-AA window
design — so that each states what 9-AA shipped.

### Scope (FROZEN as of spec commit)

**1. `docs/development_guide.md` §9.7 "App identity and window
identification" — the window table and the paragraph that follows it.**

Today the table's main-window row says `WindowGroup { ContentView() }`,
and the paragraph says the main `WindowGroup` has no `id`, so
`ContentView` tags the window itself.

After the change:

- The main-window row reads `Window("Harmonia Player", id: "main")` with
  stable identifier `main`. The Mini Player, Equalizer, and File Info
  rows stay as they are.
- The paragraph is replaced by one that explains, in this order:
  1. every top-level `Window` scene gets its identifier from the
     `Window(id:)` it is declared with;
  2. macOS does not store that id verbatim — SwiftUI derives the
     `NSWindow.identifier` as `{id}-AppWindow-{n}` (for example
     `main-AppWindow-1`), so the app matches a window to a scene with
     the tolerant test `raw == id || raw.hasPrefix(id + "-")`. That test
     is the private function `windowMatchesScene(_:id:)`, defined
     separately in `HarmoniaPlayerApp.swift`, `AppDelegate.swift`, and
     `HarmoniaPlayerCommands.swift`; comparing against the bare id
     alone is not how lookups are done;
  3. an older helper still exists: `ContentView` attaches
     `MainWindowIdentitySetter` (an `NSViewRepresentable`), which
     overwrites the main window's identifier with the plain string
     `main`. The tolerant test matches both forms, so the helper is
     harmless today; removing it is part of the window-coordinator
     refactor.
- The rest of §9.7 (product name table, bundle identifier) is unchanged.

**2. `docs/implementation_guide_swift.md` §6.1 "App Entry Point" — the
`HarmoniaPlayerApp` example.**

Today the example shows a `WindowGroup` main scene, builds `AppState`
with `StoreKitIAPManager()`, has no application delegate, and removes no
automatic menu items.

After the change the example is an excerpt of the real
`macOS/Free/HarmoniaPlayerApp.swift` and shows:

- `@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`
  and `@Environment(\.openWindow) private var openWindow`;
- the existing `init()` content (crash-on-exception registration and
  the UI-language bootstrap), unchanged;
- `@StateObject private var appState = AppState(iapManager: FreeTierIAPManager(), provider: HarmoniaCoreProvider())`;
- the main scene `Window("Harmonia Player", id: "main") { ContentView() … }`
  with the three store injections, `.focusedSceneObject(appState)`, the
  `.onAppear` that hands `openWindow` and `appState` to the delegate,
  and the `willTerminateNotification` → `saveState()` sink; then
  `.commandsRemoved()` and, after it, `.commands { HarmoniaPlayerCommands() }`
  — in that order, because removal must happen before the app's own
  menu items are added;
- `Window("Mini Player", id: "mini-player")` and
  `Window("Equalizer", id: "equalizer-window")`, each ending in
  `.commandsRemoved()` (their other modifiers may be shown or left out,
  but anything shown must match the source);
- the `Settings` scene as it is today.

The prose above the example gains one sentence: the delegate receives
`openWindow` and `appState` from the main window's `.onAppear`, because
SwiftUI does not fill in `@Environment` values while `App.init` runs.
The example may leave out the File Info `WindowGroup(for: Track.ID.self)`
scene and the window-exclusivity observers inside `init()`; leaving them
out is an excerpt, not a claim that they do not exist.

**3. `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/AppDelegate.swift`
header — the paragraph at lines 10–13.**

Today it reads that opening the Mini Player hides the main window, and
that clicking the Dock icon shows the main window even when the Mini
Player is still visible. It is replaced by:

```
//  The main window and the Mini Player are two modes of one player surface:
//  opening the Mini Player closes the main window, and closing the Mini
//  Player returns to the main window. Clicking the Dock icon brings the main
//  window back only when neither the main window nor the Mini Player exists;
//  while either exists, the click is a plain app activation.
```

The other header lines (the purpose sentence and the sentence about the
Debug-only test-exception trigger) stay as they are.

**Close-out, in the same commit:** this spec (status ticks, execution
notes if anything deviated) and the Slice 18 row in
`HarmoniaPlayer_development_plan.md`.

### Acceptance Criteria

1. AC1: `grep -nE 'WindowGroup \{ ContentView|has no .id:.|StoreKitIAPManager\(\)' docs/development_guide.md docs/implementation_guide_swift.md`
   prints nothing.
2. AC2: `docs/development_guide.md` §9.7 contains, in this order: the
   main-window table row `Window("Harmonia Player", id: "main")` / `main`;
   the string `{id}-AppWindow-{n}`; the test
   `raw == id || raw.hasPrefix(id + "-")`; the three file names that
   define `windowMatchesScene`; and `MainWindowIdentitySetter` described
   as still attached by `ContentView` and slated for the
   window-coordinator refactor.
3. AC3: in `docs/implementation_guide_swift.md` §6.1 the example contains
   `@NSApplicationDelegateAdaptor(AppDelegate.self)`,
   `iapManager: FreeTierIAPManager()`,
   `Window("Harmonia Player", id: "main")`, exactly three
   `.commandsRemoved()` lines, and the main scene's `.commandsRemoved()`
   on the line right before `.commands {`; every non-comment line of
   the example also appears in `macOS/Free/HarmoniaPlayerApp.swift` at
   the commit being edited (ignoring indentation).
4. AC4: `AppDelegate.swift` lines 10–14 equal the block in Scope item 3;
   `git diff` of the file shows only `//` lines added or removed; and
   `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` on the file prints nothing.
5. AC5: `xcodebuild build -project App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj -scheme HarmoniaPlayer -configuration Debug -destination 'platform=macOS'`
   succeeds, and `AppDelegate.swift` still reports its baseline of 2
   warnings (a comment-only edit cannot change diagnostics; the build
   proves the file still compiles). No note is added to
   `slice_12_micro.md` because no count changes.

### Out of Scope

- See the slice-level Out of Scope above.

### Deferred Backlog

None.

### Files

- HarmoniaPlayer macOS layer:
  - modify `macOS/Free/AppDelegate.swift` (header comment lines 10–13 only)
- Docs:
  - modify `docs/development_guide.md` (§9.7)
  - modify `docs/implementation_guide_swift.md` (§6.1)
- Docs at close-out: this spec, `docs/slice/HarmoniaPlayer_development_plan.md`
- Tests: none (no behaviour change)
- Project: `project.pbxproj`, `Info.plist` — no change

### TDD matrix

No new tests: the sub-slice changes documentation text and one comment
block. Verification is AC1–AC5 above (grep and diff inspection plus one
Debug build). There is no red phase, as with the earlier window-menu
slices that had nothing to unit-test.

### Implementation notes

- The window behaviour described here was decided in
  `slice_09_window_menu_micro.md` (Slice 9-AA, decisions D3, D5, D7, D8).
  This slice restates those decisions in the living documents in plain
  words and does not reinterpret them.
- `development_guide.md` §5.3 already builds `AppState` with
  `FreeTierIAPManager()`; item 2 brings the implementation guide's
  entry-point example in line with it.
- `MainWindowIdentitySetter` overwrites the identifier asynchronously
  (`DispatchQueue.main.async` inside `makeNSView`). The guide text
  therefore describes the two identifier forms and the tolerant test
  without claiming which form a window carries at a given instant.
