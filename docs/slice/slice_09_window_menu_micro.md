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
| 9-AA | Main window is reopenable after it is closed | Free | ⬜ |
| 9-AB | Standard Window-menu items and macOS-conventional playback shortcuts | Free | ⬜ |

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

### Prerequisite Investigation (web_search 2026-06-27)

- `Window(id:)` is the correct singleton scene: `openWindow(id:)` presents it,
  and a single `Window` (unlike `WindowGroup`) never yields a duplicate for the
  same id — so reopen = focus-or-recreate. (FlineDev, *Window Management on macOS
  with SwiftUI 4*.)
- SwiftUI sets the AppKit `NSWindow.identifier` to the scene `id`; the Dock-reopen
  pattern matches `sender.windows.first { $0.identifier?.rawValue == sceneID }`.
  Giving the main scene `id: "main"` therefore also makes the existing `orderOut`
  filter deterministic. (Itsuki, *SwiftUI/macOS: Custom Dock Icon Primary
  Action*, 2026-03.)
- Dock-reopen pattern: `@NSApplicationDelegateAdaptor`, the delegate holds an
  `OpenWindowAction?` captured from the App, and
  `applicationShouldHandleReopen(_:hasVisibleWindows:)` calls
  `openWindow?(id: "main")` (or `makeKeyAndOrderFront` on an existing window),
  then returns `false`.
- Risk: `applicationShouldHandleReopen` has a history of not firing in
  SwiftUI-lifecycle apps (`FB9754295`). The Window-menu item is the guaranteed
  path; Dock reopen is an enhancement (see Risk in Decisions).

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
   Add a Main Window item that calls `openWindow(id: "main")`
   (`@Environment(\.openWindow)` is already declared in the Commands struct). On a
   singleton `Window`, this focuses the existing window or recreates it if closed.
   (Placement relative to the standard Window items is defined in 9-AB.)

3. **Dock-click reopen** (new `macOS/Free/AppDelegate.swift` + adaptor in the App).
   - `final class AppDelegate: NSObject, NSApplicationDelegate` holding
     `var openWindow: OpenWindowAction?`:
     ```swift
     func applicationShouldHandleReopen(_ sender: NSApplication,
                                        hasVisibleWindows flag: Bool) -> Bool {
         if let main = sender.windows.first(where: { $0.identifier?.rawValue == "main" }) {
             main.makeKeyAndOrderFront(self)
         } else {
             openWindow?(id: "main")
         }
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

### Decisions (frozen)

- **D1** — Main window is a singleton `Window(id: "main")` (not `WindowGroup`).
- **D2** — A Main Window item (key `menu_main_window`) reopens it; no custom
  shortcut (see 9-AB for its placement among the standard Window items).
- **D3** — Dock reopen via `applicationShouldHandleReopen`: existing "main" window
  → `makeKeyAndOrderFront`; otherwise `openWindow(id: "main")`; return `false`.
  **Authorized fallback:** add `applicationWillBecomeActive(_:)` with the same
  body if reopen does not fire. Anything beyond that → **STOP and report**.
- **D4** — Mini Player `orderOut` reliability is a folded consequence of D1.

### TDD / Verification

Pure SwiftUI / AppKit window-lifecycle glue with no meaningful headless assertion
— same situation as slices **9-U** and **9-Y**. **Verification for v1.0 is manual
smoke only** (below). No red-phase unit tests.

### Files

| Status | File | Change |
| --- | --- | --- |
| New | `macOS/Free/AppDelegate.swift` | `NSApplicationDelegate`: holds `OpenWindowAction?`; `applicationShouldHandleReopen` reopens "main" (+ authorized `applicationWillBecomeActive` fallback) |
| Modify | `macOS/Free/HarmoniaPlayerApp.swift` | main scene → `Window(id: "main")`; add `@NSApplicationDelegateAdaptor` + `openWindow` capture |
| Modify | `macOS/Free/Views/HarmoniaPlayerCommands.swift` | add the Main Window reopen item (placement per 9-AB) |
| Modify | `en.lproj/Localizable.strings` | add `"menu_main_window" = "Main Window";` (surgical / Xcode) |
| Modify | `ja.lproj/Localizable.strings` | add `"menu_main_window" = "メインウィンドウ";` |
| Modify | `zh-Hant.lproj/Localizable.strings` | add `"menu_main_window" = "主視窗";` |
| Modify | `docs/user_guide.md` | document Window → Main Window |

### Manual verification

1. Close the main window (no Mini Player open) → Dock click reopens it; Window →
   Main Window reopens it.
2. Open Mini Player so it floats and the main window hides; close the main window
   → Dock click reopens it; Window → Main Window reopens it.
3. Invoke reopen repeatedly → always exactly one main window.
4. ⌘W close, ⌘Q quit, ⌘I File Info, ⌘, Settings unaffected.

### Commit plan

| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-aa)` | give the main window a stable id and a reopen menu item |
| 2 | `fix(slice 9-aa)` | reopen the main window on dock click |

### Doc updates

- `user_guide.md` — Window section: Window → Main Window reopens the main window.
- No `api_reference.md` / `module_boundary.md` / `architecture.md` change (no
  public API, persistence, or HarmoniaCore surface; `AppDelegate` is macOS
  app-lifecycle glue beside the App entry point). architecture.md untouched → the
  HarmoniaCore 5-area audit does not apply.

### Non-goals

- `.restorationBehavior` / `.defaultLaunchBehavior` tuning for Mini Player / EQ /
  File Info — unchanged.
- MenuBarExtra — not introduced.

---

## Slice 9-AB: Standard Window-menu items and macOS-conventional playback shortcuts

### Requirement and rationale

Bring menu and keyboard behaviour into line with macOS conventions and the native
Music app's shortcut map (macOS HIG; Review Guidelines §4):

- `⌘M` is the system-standard **Minimize** shortcut; the app currently binds it to
  the Mini Player, shadowing Minimize.
- The standard Window-menu items **Minimize** and **Zoom** were dropped when
  `.windowArrangement` was replaced wholesale.
- **Seek** is bound to **bare arrow keys**. A menu key equivalent is evaluated
  before the focused responder, so bare ←/→ pre-empt arrow-key navigation in the
  playlist table.

### Root cause

Menu key equivalents are global and take precedence over the first responder, so
bare keys (←/→) and system-reserved combos (⌘M) override the behaviour the
focused control should provide; and replacing the whole `.windowArrangement`
group removed Minimize/Zoom.

### Prerequisite Investigation — native Music shortcut reference (web_search 2026-06-27)

Apple Music (macOS) shortcut map, used as the alignment reference:

| Action | Music (macOS) |
| --- | --- |
| Play / Pause | Space |
| Previous / Next | `⌘←` / `⌘→` |
| Seek backward / forward | `⌥⌘←` / `⌥⌘→` |
| Volume down / up | `⌘↓` / `⌘↑` |

Sources: Apple *Keyboard shortcuts in Music on Mac*
(`support.apple.com/guide/music/keyboard-shortcuts-mus1019/mac`); seek =
`⌥⌘`+arrow corroborated by iDownloadBlog and Apple Support Communities.

### Fix (`macOS/Free/Views/HarmoniaPlayerCommands.swift`)

1. **Restore `⌘M` to Minimize.** Do not bind a custom command to `⌘M`. Move the
   Mini Player command to **`⌥⌘M`**.
2. **Keep the standard Window-menu items.** Instead of replacing the whole
   `.windowArrangement` group, keep Minimize and Zoom and **add** the 9-AA Main
   Window item (and the existing Mini Player / Equalizer items) alongside them.
3. **Move Seek to `⌥⌘←` / `⌥⌘→`** (Music parity). This frees the bare arrow keys
   for playlist-table navigation.
4. **Leave Previous / Next at `⌘←` / `⌘→`** — already matches Music; no change.
5. **Play / Pause stays Space**, implemented so a focused text field consumes
   Space first (handled at the responder level, not as a hard global menu key
   equivalent that pre-empts typing).

### Decisions (frozen)

- **D5** — `⌘M` = Minimize (system standard); Mini Player = `⌥⌘M`.
- **D6** — Window menu keeps Minimize + Zoom; the Main Window item is added, the
  standard group is not wholesale-replaced.
- **D7** — Seek = `⌥⌘←` / `⌥⌘→`; bare arrow keys are reserved for table navigation.
- **D8** — Previous / Next unchanged (`⌘←` / `⌘→`); Equalizer unchanged (`⌘⌥E`);
  Play / Pause stays Space, handled at the responder level.

### TDD / Verification

Menu / keyboard glue with no meaningful headless assertion (precedent 9-U / 9-Y).
**Manual smoke only**, and it **must** include the table-navigation check below.

### Files

| Status | File | Change |
| --- | --- | --- |
| Modify | `macOS/Free/Views/HarmoniaPlayerCommands.swift` | restore standard Window items + `⌘M` Minimize; Mini Player → `⌥⌘M`; Seek → `⌥⌘`+arrow; Space handled at responder level |
| Modify | `docs/user_guide.md` | update the Window / Playback shortcut tables |

### Manual verification

1. **Minimize.** `⌘M` minimises the main window; the Window menu shows Minimize +
   Zoom; Mini Player opens on `⌥⌘M`.
2. **Table navigation (critical).** Focus the playlist table, press `←` / `→` →
   selection moves; it does **not** seek.
3. **Seek.** `⌥⌘←` / `⌥⌘→` seek backward / forward.
4. **Transport.** Space toggles play/pause; while renaming a playlist, Space types
   a space (the field wins). `⌘←` / `⌘→` change track.

### Commit plan

| Order | Type / Scope | Subject |
| --- | --- | --- |
| 1 | `fix(slice 9-ab)` | restore standard window menu items and the minimize shortcut |
| 2 | `fix(slice 9-ab)` | align playback shortcuts with the macOS music conventions |

### Doc updates

- `user_guide.md` — Window / Playback shortcut tables: `⌘M` Minimize, Mini Player
  `⌥⌘M`, Seek `⌥⌘`+arrow.

### Non-goals

- Restoring Cut / Copy / Paste / Select All in the Edit menu — Apple permits
  removing default commands that do not apply; this is polish, deferred.
- Volume shortcuts (`⌘↑` / `⌘↓`) — not in this slice.

---

## 2. Workflow

Spec frozen and committed first. Both 9-AA and 9-AB are manual-smoke-only
(precedent 9-U / 9-Y), so the `是請執行` confirmation gates the spec →
implementation transition directly. Then green (minimum code) + doc updates in the
same commits, per each slice's commit plan.