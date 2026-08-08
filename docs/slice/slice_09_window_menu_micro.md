# Slice 09 Window & Menu Conformance Micro Spec

## 0. Purpose and relationship to the slice 09 specs

This slice brings the macOS app's **window lifecycle** and **menu / keyboard
behaviour** into line with the macOS Human Interface Guidelines and the App Store
Review Guidelines §4 (Design).

- `slice_09_micro.md` — design authority for slices **9-A … 9-R**.
- `slice_09_smoke_fix_micro.md` — numbering authority for slices **9-S … 9-Z**.
- **This file** — numbering authority for **9-AA** and **9-AB**.

Marketing version stays **1.0.0**; this ships as a **new build**. Bundle
Identifier and `PRODUCT_NAME` are unchanged.

---

## 1. Slice summary

| Slice | Title | Tier | Status |
| --- | --- | --- | --- |
| 9-AA | Main window is reopenable after it is closed | Free | ✅ |
| 9-AB | Standard Window-menu items and macOS-conventional playback shortcuts | Free | ✅ |

---

## Slice 9-AA: Main window is reopenable after it is closed

### Requirement and rationale

On macOS, an app's main window must stay reachable after the user closes it
(macOS HIG; App Store Review Guidelines §4, Design). Today, closing the main
window leaves no menu item and no Dock path to bring it back. The gap is most
visible when the Mini Player is floating: the app still owns a visible window, so
the system does not auto-reopen the main window, and the user is stranded.

### Root cause

1. The main scene is `WindowGroup { ContentView() }` with **no `id`**, so it is
   not addressable by `openWindow(id:)` and its AppKit window has no stable
   `identifier`.
2. `HarmoniaPlayerCommands` **replaces** the entire `.windowArrangement` group,
   so there is no "reopen main window" item and the system's default window list
   is gone.
3. There is **no `NSApplicationDelegate`**, so a Dock click is never handled to
   bring the main window back.
4. Latent: the Mini Player command filters `NSApp.windows` for
   `identifier?.rawValue == "main"`, but with no scene `id` that identifier is
   not reliably set.
5. The player toolbar's ⋯ menu is a second Mini Player entry point whose
   action still ran the pre-slice behaviour — hiding (`orderOut`) the main
   window instead of closing it — so the two entry points for the same
   feature diverged. Per-entry-point closing logic invites exactly this
   drift; the closing rule belongs at the window level, once.
6. Each `Window` scene auto-generates its own menu command (named after the
   window title: "Harmonia Player", "Mini Player", "Equalizer"). These appear
   as a second, duplicate group above the app's own Window-menu items and carry
   default behaviour that ignores the main/Mini exclusivity. They are scene
   commands, not entries in the system windows list, so
   `isExcludedFromWindowsMenu` does not remove them; `.commandsRemoved()` on the
   scene does.

### Window-operation matrix (behaviour authority)

The main window and the Mini Player are two modes of one player surface. The
Window menu shows only the app's own items; a menu separator groups the
player-surface pair (Main Window / Mini Player) apart from the independent
Equalizer. Each Window scene's auto-generated menu command is removed with
`.commandsRemoved()` so only the app's own items appear.

| State | Menu → Mini Player | Dock click | Menu → Main Window |
| --- | --- | --- | --- |
| 1. Main open, Mini closed | close main, open Mini (1-1) | main already there — nothing (1-2) | main already there — nothing (1-3) |
| 2. Main closed, Mini open | switch back — open main, Mini closes (2-1) | Mini already there — nothing (2-2) | close Mini, open main (2-3) |
| 3. Main closed, Mini closed | open Mini (3-1) | open main (3-2) | open main (3-3) |

Additionally, **closing the Mini Player itself returns to the main window**
(recreating it if needed), and closing the main window never summons anything.
The Equalizer is an independent utility window: it may coexist with either mode,
never participates in the exclusivity, and does not affect the matrix.

### Fix

1. **Main scene → `Window(id: "main")`** (`macOS/Free/HarmoniaPlayerApp.swift`).
   Replace `WindowGroup { ContentView()… }` with
   `Window("Harmonia Player", id: "main") { ContentView()… }`, preserving every
   existing modifier (`.environmentObject`, `.frame(minWidth: 620, minHeight: 480)`,
   `.focusedSceneObject(appState)`, `.ignoresSafeArea()`, the `willTerminate` →
   `saveState()` sink) and `.commands { HarmoniaPlayerCommands() }`.
   *Folded consequence:* the Mini Player `orderOut` filter now matches
   deterministically — same commit, no separate test.

2. **Window-menu reopen item** (`macOS/Free/Views/HarmoniaPlayerCommands.swift`).
   Add a Main Window item whose action, inline, closes the Mini Player window if
   open, then brings the main window forward (`makeKeyAndOrderFront`), recreating
   it via `openWindow(id: "main")` only when no instance exists.
   `@Environment(\.openWindow)` is already declared in the Commands struct.
   (Placement relative to the standard Window items is defined in 9-AB.)
   *v1.0.0 note:* this reopen logic is duplicated inline again in the Dock handler
   (step 3); consolidating both into one neutral coordinator — together with the
   Mini Player button's own inline `orderOut` — is a tracked refactor, not part of
   this ship build.

3. **Dock-click reopen** (new `macOS/Free/AppDelegate.swift` + adaptor in the App).
   - `final class AppDelegate: NSObject, NSApplicationDelegate` holding
     `var openWindow: OpenWindowAction?`. The Dock click acts **only when no
     player surface exists** (matrix rows 1-2 / 2-2 / 3-2): an existing main
     window or Mini Player is left alone and the click behaves like a plain app
     activation; only when neither exists does it bring the main window back:
     ```swift
     func applicationShouldHandleReopen(_ sender: NSApplication,
                                        hasVisibleWindows flag: Bool) -> Bool {
         let hasPlayerSurface = sender.windows.contains {
             let id = $0.identifier?.rawValue
             return id == "main" || id == "mini-player"
         }
         guard !hasPlayerSurface else { return true }
         showMainWindow()   // bring forward, or recreate via openWindow(id: "main")
         return false
     }
     ```
   - `HarmoniaPlayerApp`: add `@NSApplicationDelegateAdaptor(AppDelegate.self)`
     and `@Environment(\.openWindow)`, and capture the action into the delegate.
     **Primary:** assign in `init` (`appDelegate.openWindow = openWindow`).
     **Authorized fallback** if init-time environment access is unavailable:
     capture via the main window content's
     `.onAppear { appDelegate.openWindow = openWindow }`, kept in the macOS/Free
     layer only.

4. **Remove the auto-generated scene commands** (`macOS/Free/HarmoniaPlayerApp.swift`,
   scene modifiers). Apply `.commandsRemoved()` to the main, Mini Player, and
   Equalizer `Window` scenes so their auto-generated menu commands (the
   duplicate "Harmonia Player" / "Mini Player" / "Equalizer" group) disappear;
   the app's own `HarmoniaPlayerCommands` items become the single source of
   control. On the main scene, order matters: `.commandsRemoved()` **before**
   `.commands { HarmoniaPlayerCommands() }` so removal happens first and the
   custom Window menu is re-added afterwards.

   Window-level exclusivity is enforced separately by a
   `NSWindow.didBecomeKeyNotification` observer in `init` (beside the existing
   restoration observer), **in both directions**: whichever of the two player
   surfaces becomes key closes the other. Entry points (Window menu, player
   toolbar ⋯ menu, Dock) therefore only ever call `openWindow`; no entry point
   carries its own closing logic, so every current or future entry point obeys
   the rule automatically.
   - When the window with identifier "main" becomes key, closes every window
     with identifier "mini-player"; when the "mini-player" window becomes key,
     closes every "main" window. This enforces D5 at the point where the event
     happens, covering every path in either direction — the Window-menu items,
     the player toolbar ⋯ menu, Dock reopen, and window cycling — including
     paths the app does not own. The inline close in the Main Window menu item
     (step 2) is redundant safety and stays as shipped for v1.0.0.

5. **Closing the Mini Player returns to the main window**
   (`macOS/Free/AppDelegate.swift`). The Mini Player and the main window are two
   modes of one player surface, so leaving mini mode switches back to the main
   window. The delegate observes `NSWindow.willCloseNotification` for the
   "mini-player" window and shows the main window on the next runloop pass —
   bringing it forward, or recreating it via the captured `openWindow` when the
   user had closed it. Guarded by an `isTerminating` flag set in
   `applicationShouldTerminate` so quitting with the Mini Player open does not
   resurrect the main window during termination.

6. **Mini Player entry points only open the window** (matrix row 1-1,
   `macOS/Free/Views/HarmoniaPlayerCommands.swift` and
   `Shared/Views/PlayerView.swift`). Both Mini Player entry points — the Window
   menu item and the player toolbar ⋯ menu — reduce to a bare
   `openWindow(id: "mini-player")`. Closing the main window is handled by the
   window-level rule (step 4), so in mini mode the main window is closed, not
   hidden, from every entry point, and the deferred `orderOut`/`close` hacks
   are deleted. `PlayerView` (Shared) no longer touches `NSApp`/AppKit window
   management.

### Decisions (frozen)

- **D1** — Main window is a singleton `Window(id: "main")` (not `WindowGroup`).
- **D2** — A Main Window item (key `menu_main_window`) reopens the main window
  inline (close Mini Player, then bring/recreate main); no custom shortcut (see
  9-AB for its placement among the standard Window items).
- **D3** — Dock reopen via `applicationShouldHandleReopen` acts **only when no
  player surface exists** (matrix 1-2 / 2-2 / 3-2): an existing main window or
  Mini Player is left alone (`return true`, plain activation); otherwise it
  shows/recreates the main window and returns `false`. **Authorized fallback:**
  add `applicationWillBecomeActive(_:)` making the same call if reopen does not
  fire. Anything beyond that → **STOP and report**.
- **D4** — Giving the main scene a stable `id` also made the Mini Player
  button's main-window lookup deterministic (folded consequence of D1).
- **D5** — The main window and the Mini Player are two modes of **one player
  surface**, never visible together. Opening the Mini Player **closes** the main
  window (matrix 1-1); **closing the Mini Player returns to the main window**,
  recreating it. Exclusivity is enforced at the **window level in both
  directions** (whichever of the two becomes key closes the other), so every
  entry point in either direction obeys it — the Window-menu items, the player
  toolbar ⋯ menu, Dock reopen, and window cycling — and entry points only ever
  open a window. Closing the **main**
  window dismisses the player surface without summoning anything: a no-window
  (blank) state is acceptable and is recovered only by an explicit reopen (menu
  or Dock).
- **D6** — For v1.0.0 the window coordination is deliberately spread across the
  menu item (inline), the Dock handler and the mini-close restore (AppDelegate),
  and the exclusivity observer (App init). Consolidating them into one neutral
  window coordinator is a tracked refactor (see the working notes), out of the
  ship build.
- **D7** — The main, Mini Player, and Equalizer `Window` scenes use
  `.commandsRemoved()` to drop their auto-generated scene menu commands, so the
  app's own Window-menu items are the single source of control (eliminating the
  duplicate "Harmonia Player" / "Mini Player" / "Equalizer" group). On the main
  scene `.commandsRemoved()` precedes `.commands { HarmoniaPlayerCommands() }`.
  `isExcludedFromWindowsMenu` was tried first and does not work: these are scene
  commands, not system windows-list entries. File Info windows keep their
  default commands
  (several can coexist; the list is how users find them).
- **D8** — All scene-window matching uses the tolerant predicate
  `raw == id || raw.hasPrefix(id + "-")` (fileprivate `windowMatchesScene` in
  each of the three files), because SwiftUI derives `NSWindow.identifier` as
  `{id}-AppWindow-{n}`. Exact-match comparison against the bare scene id is
  forbidden in this codebase.

### TDD / Verification

Pure SwiftUI / AppKit window-lifecycle glue with no meaningful headless assertion
— same situation as slices **9-U** and **9-Y**. **Verification for v1.0 is manual
smoke only** (below). No red-phase unit tests.

### Files

| Status | File | Change |
| --- | --- | --- |
| New | `macOS/Free/AppDelegate.swift` | `NSApplicationDelegate`: holds `OpenWindowAction?`; Dock reopen closes the Mini Player and shows/recreates the main window; closing the Mini Player returns to the main window (termination-guarded via `applicationShouldTerminate`) |
| Modify | `macOS/Free/HarmoniaPlayerApp.swift` | main scene → `Window(id: "main")`; add `@NSApplicationDelegateAdaptor` + `openWindow` capture; `.commandsRemoved()` on main/Mini/EQ scenes to drop auto scene commands; key-window observer enforces exclusivity in both directions (main↔mini) |
| Modify | `Shared/Views/PlayerView.swift` | toolbar ⋯ Mini Player action reduced to `openWindow` only; AppKit window handling removed from the Shared layer |
| Modify | `macOS/Free/Views/HarmoniaPlayerCommands.swift` | add the Main Window reopen item (placement per 9-AB); Mini Player button reduced to `openWindow` only; separator between the player-surface items and the Equalizer |
| Modify | `en.lproj/Localizable.strings` | add `"menu_main_window" = "Main Window";` (surgical / Xcode) |
| Modify | `ja.lproj/Localizable.strings` | add `"menu_main_window" = "メインウィンドウ";` |
| Modify | `zh-Hant.lproj/Localizable.strings` | add `"menu_main_window" = "主視窗";` |
| Modify | `docs/user_guide.md` | document Window → Main Window |

### Manual verification

Follow the matrix, one cell at a time:

1. **1-1** Main open, Mini closed → open Mini from **both** entry points (in
   separate runs): Window → Mini Player, and the player toolbar **⋯ → Mini
   Player** → Mini opens **and the main window closes** (not just hides) from
   either entry.
2. **1-2** Main open → Dock click → nothing changes (main stays, no Mini).
3. **1-3** Main open → Window → Main Window → nothing changes (still exactly one
   main window).
4. **2-1** Mini open, main closed → menu Mini Player / `⇧⌘M` → **switches back:
   main opens, Mini closes** (toggle).
5. **2-2** Mini open, main closed → Dock click → **nothing changes** (Mini
   stays; no main window appears).
6. **2-3** Mini open, main closed → Window → Main Window → **Mini closes, main
   opens** (never both).
7. **3-1** Blank (both closed) → menu Mini Player → Mini opens.
8. **3-2** Blank → Dock click → main opens.
9. **3-3** Blank → Window → Main Window → main opens.
10. **Mode switch** Close the Mini Player (red button or ⌘W) → the main window
    reappears (recreated) — including when main had been closed before opening
    the Mini Player.
11. **No duplicate scene commands** With main open (and again with Mini open),
    open the Window menu → the auto-generated top group is gone: no "Harmonia
    Player" / duplicate "Mini Player" / duplicate "Equalizer"; only the app's
    own items (Main Window / Mini Player / — / Equalizer) plus Bring All to
    Front, and File Info entries when File Info windows are open.
12. **Quit guard** Open Mini Player, then ⌘Q → the app quits cleanly; the main
    window does not flash open during termination; playlist state is saved.
13. **Window-placement commands** With the **main** window focused (playing or
    not), the Window menu shows the system placement items (Minimize / Zoom /
    Fill / Center / Move & Resize) — playback must not change them. With the
    **Mini Player** focused, the system hides the placement items for the
    floating panel; that reduction is expected macOS behaviour, not a defect.
14. **Regression** Closing the main window never makes the Mini Player appear;
    Equalizer opens/closes independently in both modes; ⌘W, ⌘I File Info, ⌘,
    Settings unaffected; the standard App menu (About / Quit) and the Edit menu
    remain present after `.commandsRemoved()`.

### Commit plan

| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-aa)` | give the main window a stable id and a reopen menu item that closes the mini player |
| 2 | `fix(slice 9-aa)` | reopen the main window on dock click |

### Doc updates

- `user_guide.md` — Window section: Window → Main Window reopens the main window.
- No `api_reference.md` / `module_boundary.md` / `architecture.md` change (no
  public API, persistence, or HarmoniaCore surface; `AppDelegate` is macOS
  app-lifecycle glue beside the App entry point). architecture.md untouched → the
  HarmoniaCore 5-area audit does not apply.

### Non-goals

- **Auto-summon on main-window close.** Closing the main window dismisses the
  player surface; nothing (in particular the Mini Player) is summoned to avoid a
  blank state, which is recovered only by an explicit reopen (menu or Dock).
  Closing the Mini Player, by contrast, returns to the main window — see D5.
- `.restorationBehavior` / `.defaultLaunchBehavior` tuning for Mini Player / EQ /
  File Info — unchanged.
- MenuBarExtra — not introduced.

---

## Slice 9-AB: macOS-conventional playback and Mini Player shortcuts

### Requirement and rationale

Align the keyboard map with macOS conventions and the native Music app
(macOS HIG; Review Guidelines §4):

- `⌘M` is the system-standard Minimize and already behaves as such in the
  released build: the Mini Player item's own `⌘M` equivalent never fires
  because the system Minimize item resolves first, so the binding is dead
  code — and `user_guide.md` documents `⌘M` as "Open Mini Player", which does
  not match the actual behaviour. The Mini Player therefore has no working
  shortcut at all.
- Seek is bound to bare arrow keys. A menu key equivalent is evaluated before
  the focused responder, so bare ←/→ pre-empt arrow-key navigation in the
  playlist table.

### Root cause

Menu key equivalents are global and take precedence over the first responder
(bare ←/→ steal table navigation), and duplicate equivalents resolve to the
menu-order-first item (the system Minimize precedes the app's Window group, so
the Mini Player's `⌘M` never fires).

### Fix (`macOS/Free/Views/HarmoniaPlayerCommands.swift`)

1. **Mini Player → `⇧⌘M`, as a two-way switch.** Remove the dead `⌘M`
   equivalent and assign `⇧⌘M` — Music's "Switch to MiniPlayer" binding, which
   matches this app's exclusive mode-switch semantics, including the return
   direction: the menu action opens whichever player surface is currently
   absent (main open → opens the Mini Player; Mini open → opens the main
   window), and the window-level exclusivity rule closes the other. The
   entry point still only opens a window; no closing logic is added. `⌥⌘M`
   is not used: it is the system's Minimize All variant, and Music reserves
   it for its non-exclusive "Mini Player" item, which this app does not have.
2. **Seek → `⌥⌘←` / `⌥⌘→`** (Music parity). Frees the bare arrow keys for
   playlist-table navigation.
3. **Previous / Next unchanged** at `⌘←` / `⌘→` — already Music parity.
4. **Play / Pause unchanged** as the bare-Space menu equivalent. Verification
   includes the rename-field check (a focused text field must consume Space);
   if the field does not win, stop and report — no responder-chain rework
   inside this slice.
5. **No Window-menu structural change.** Minimize / Zoom are provided by the
   system outside the replaced `.windowArrangement` group and are already
   present; 9-AA settled the Window-menu composition.

### Decisions (frozen)

- **D9** — Mini Player = `⇧⌘M`, a two-way switch between the main window and
  the Mini Player (Switch-to-MiniPlayer parity, matrix rows 1-1 / 2-1 / 3-1);
  the dead `⌘M` equivalent is removed; `⌘M` remains the system Minimize.
  `⌥⌘M` is avoided (system Minimize All variant).
- **D10** — Seek = `⌥⌘←` / `⌥⌘→`; bare arrow keys are reserved for table
  navigation.
- **D11** — Previous / Next unchanged (`⌘←` / `⌘→`); Equalizer unchanged
  (`⌥⌘E`); Stop unchanged (`⌘.`).
- **D12** — Play / Pause stays the bare-Space menu equivalent. The first
  manual test must confirm a focused rename field consumes Space; if it does
  not, stop and report before any further change.

### TDD / Verification

Menu / keyboard glue with no meaningful headless assertion (precedent 9-U /
9-Y). Manual smoke only, and it must include the table-navigation check.

### Files

| Status | File | Change |
| --- | --- | --- |
| Modify | `macOS/Free/Views/HarmoniaPlayerCommands.swift` | Mini Player equivalent `⌘M` → `⇧⌘M` acting as a two-way switch; Seek `←`/`→` → `⌥⌘←`/`⌥⌘→` |
| Modify | `docs/user_guide.md` | correct the Window / Playback shortcut tables (`⌘M` = Minimize, Mini Player `⇧⌘M`, Seek `⌥⌘`+arrow) |

### Manual verification

1. **Minimize.** `⌘M` minimises the focused window (main and Mini Player) —
   unchanged system behaviour.
2. **Mini Player switch (both directions).** From the main window, `⇧⌘M`
   opens the Mini Player and the main window closes; pressing `⇧⌘M` again
   opens the main window and the Mini Player closes.
3. **Table navigation (critical).** Focus the playlist table, press `←` / `→`
   → selection moves; it does **not** seek.
4. **Seek.** `⌥⌘←` / `⌥⌘→` seek backward / forward 5 s.
5. **Transport.** Space toggles play/pause; while renaming a playlist, Space
   types a space (the field wins — D12 gate). `⌘←` / `⌘→` change track; `⌘.`
   stops; `⌥⌘E` opens the Equalizer.

### Commit plan

| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `docs(slice 9-ab)` | revise the shortcut spec to the released-build behaviour and correct the user guide tables |
| 2 | `fix(slice 9-ab)` | align the mini player and seek shortcuts with the macos music conventions |

### Doc updates

- `user_guide.md` — Window / Playback shortcut tables: `⌘M` Minimize, Mini
  Player `⇧⌘M`, Seek `⌥⌘`+arrow (ships with commit 1).
- No `api_reference.md` / `module_boundary.md` / `architecture.md` change.

### Non-goals

- Restoring Cut / Copy / Paste / Select All in the Edit menu — polish, deferred.
- Volume shortcuts (`⌘↑` / `⌘↓`) — not in this slice.
- Removing the legacy `MainWindowIdentitySetter` — tracked in the working
  notes for the coordinator refactor.

---

## 2. Workflow

Spec frozen and committed first. Both 9-AA and 9-AB are manual-smoke-only
(precedent 9-U / 9-Y), so the `是請執行` confirmation gates the spec →
implementation transition directly. Then green (minimum code) + doc updates in the
same commits, per each slice's commit plan.