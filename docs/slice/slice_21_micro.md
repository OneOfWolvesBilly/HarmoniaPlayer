# Slice 21 Micro-slices Specification

## Purpose

The File Info window's SOURCE section lists the download origins stored in
the file's `kMDItemWhereFroms` attribute, one selectable row per URL. Each
row is capped at two lines. A URL that needs three or more lines at the
window's width is truncated correctly until the user clicks into it; the
AppKit field editor that takes over the selectable text then lays the
whole string out without the cap, the row keeps its two-line height, and
the extra lines are painted over the next source. Clicking elsewhere does
not undo it.

This slice removes the height cap so every source row is as tall as its
text, keys the rows by position so two identical sources render as two
rows, and keeps the text selectable. Rows never overlap at any URL length
or window width.

## Slice 21 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 21-A | Source rows grow with their text; rows keyed by position | Free | ✅ |

### Goals

- A source URL of any length is shown in full on as many lines as it
  needs, and the following source starts below it, at every window width
  from the 400 pt minimum up.
- The rows stay selectable, and selecting (clicking into) a row changes
  neither its height nor the rows below it.
- Two identical source strings produce two rows.

### Out of Scope

- A tooltip, a Copy context-menu item, or any other way to expose a URL
  besides selection → not needed once the full URL is visible; no
  destination.
- Any change to the other File Info sections, the window's frame limits,
  or the `InfoRow` layout → unchanged.
- Writing or editing the source attribute → the Pro Tag Editor
  (`slice_pro_micro_draft.md`).
- Dropping `.textSelection(.enabled)` from any view → the lyrics-panel
  context-menu candidate decides that for its own panel (development plan,
  pre-Pro candidates); the File Info rows keep it.
- The next v1.0.1 item (Settings window sizing) → its own slice.

### Constraints

- **C1 — No height cap.** A source row carries no `lineLimit`; its height
  follows its text at the proposed width, so the SwiftUI frame and the
  AppKit field editor agree on the line count and nothing can overflow.
- **C2 — Selection stays.** The rows keep `.textSelection(.enabled)` (the
  only way to copy a URL out of the window), consistent with every
  `InfoRow` value in the other sections.
- **C3 — Position identity.** Rows are identified by their index in the
  stored array, not by the string; the array is shown as stored, in
  order, without de-duplication or sorting.
- **C4 — Warning baseline.** `FileInfoView.swift` builds with zero
  warnings before and after the change (its Slice 20-A measurement).

### Dependencies

- None.

### Release

Ships in **v1.0.1**; the release's contents are listed in the development
plan's Version Targets section (§11.17 at the time of writing — the number
moves as slices open and is fixed to its final location when v1.0.1
ships).

---

## Slice 21-A: Source rows grow with their text ✅

### Goal

Make each SOURCE row exactly as tall as its text and key the rows by
position, so a long or duplicated source never paints over the next one.

### Scope (FROZEN as of spec commit)

**`Shared/Views/FileInfoView.swift`, `sourceSection`** — the non-empty
branch becomes:

```swift
ForEach(Array(whereSources.enumerated()), id: \.offset) { _, source in
    Text(source)
        .font(.body)
        .foregroundStyle(Color.primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
}
```

Changes against today's code: `id: \.self` → position (`enumerated()`,
`id: \.offset`); `.lineLimit(2)` removed;
`.fixedSize(horizontal: false, vertical: true)` added so the row's height
is its text's height under any parent proposal. Font, colour, selection,
padding, the enclosing `VStack(alignment: .leading, spacing: 6)`, the
empty-state branch, and the data loading are unchanged. The file header's
section list keeps "Source — kMDItemWhereFroms URLs (read-only display)".

**Docs (at green):**

| Doc | Change |
|---|---|
| `user_guide.md` | File Info → "Source URLs" bullet: each source URL is shown in full on its own row (read-only, selectable) |

**Docs (at close-out):** this spec (status ticks, execution amendments),
`HarmoniaPlayer_development_plan.md` (slice table tick, v1.0.1 row tick),
`slice_12_micro.md` (Slice 21-A re-measurement note).

No `api_reference.md` / `module_boundary.md` / `architecture.md` /
`development_guide.md` / `implementation_guide_swift.md` change (no API,
file, boundary, or persistence change; views are not listed in the API
reference). `architecture.md` untouched → the HarmoniaCore 5-area audit
does not apply.

### Acceptance Criteria

1. AC1: `grep -n "lineLimit" App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/FileInfoView.swift`
   has no match; `grep -n 'id: \\.offset' …/FileInfoView.swift` matches
   exactly one line, inside `sourceSection`; `grep -n 'id: \\.self'` has
   no match.
2. AC2 (manual, width 400 pt): a track whose first source needs three or
   more lines at that width, followed by a second source (reference:
   `02 Payphone  Ft. Wiz Khalifa.mp3` in the Test playlist — a
   140-character URL then `https://yt5s.io/zh-tw15/youtube-to-mp3`).
   Open File Info, resize the window to its minimum width, scroll to
   SOURCE: (a) the first URL is complete (no `…`) on three lines and the
   second source starts on its own row below it; (b) after one click
   inside the first URL the rows look the same — no third line over the
   second source; (c) after a click elsewhere in the window, still the
   same. Before the fix, (b) and (c) show the third line painted over the
   second source.
3. AC3 (manual, width ≥ 900 pt): the same track at the wider window; the
   first URL takes two lines and the second source sits below; (b) and
   (c) as in AC2 leave it unchanged.
4. AC4 (manual): a file whose attribute holds two identical strings
   shows two rows with that string (fixture recipe in Implementation
   notes); a file without the attribute still shows the single
   localized "none" line.
5. AC5: full ⌘U suite green at 563 passed / 5 skipped / 0 failed (the
   d30f627 count, unchanged — no test is added or removed); UITests
   unchanged (9).
6. AC6: `FileInfoView.swift` builds with zero warnings on a clean build
   (C4); the re-measurement note lands in `slice_12_micro.md` with the
   close-out.
7. AC7: `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` over the slice's added
   `.swift` lines returns no forbidden match.
8. AC8: `user_guide.md` has been read in full and cross-checked against
   source, not grep-patched.

### Out of Scope

- See slice-level Out of Scope.

### Deferred Backlog

None.

### Files

- UI: modify `Shared/Views/FileInfoView.swift` (`sourceSection` only)
- Tests: none added or changed (see TDD matrix)
- Project: `HarmoniaPlayer.xcodeproj/project.pbxproj` — no change
- Docs at green: `user_guide.md`
- Docs at close-out: this spec, `HarmoniaPlayer_development_plan.md`,
  `slice_12_micro.md`

### TDD matrix

No unit-testable rows. The change is layout only: the view has no test
file, the sources are shown as stored (no mapping, ordering, or
de-duplication to extract), and the defect lives in the window-hosted
AppKit layer that neither `ImageRenderer` nor a never-shown `NSWindow`
reproduces (both render the shipped code without overlap). A unit test
here could only assert fixture state or a language guarantee. The slice
is verified by AC1 (source inspection), AC2–AC4 (manual, screenshots at
two widths with the click / click-away sequence), and AC5–AC6 (no
regression in the suite or the warning baseline).

Execution amendments (recorded at close-out):

- Red set empty, as the matrix states; green is the single `sourceSection`
  change plus the user-guide bullet.
- AC5 on a clean build: unit target 563 passed / 5 skipped / 0 failed,
  unchanged. The UITests runner did not start under the command-line run
  (macOS automation authentication cancelled), so the 9 UITests are
  confirmed from Xcode's ⌘U rather than from that run.
- AC2 observed at 400 pt with the reference track: the first URL on three
  lines with no `…`, the second source below; unchanged after a click
  into the row and after a click elsewhere. AC3 at 900 pt: two lines,
  unchanged after a click. AC4: a file without the attribute shows
  "(none)"; a file whose attribute holds `https://vd6s.net/` twice plus a
  311-character URL shows three rows — the short URL twice, then the long
  URL on six lines — with no overlap.
- Warning re-measurement on the clean build (deduplicated
  `file:line:col: warning:` lines, the Slice 19 / 20 method): total 417,
  app target 32 (`PlaylistView.swift` 16, `HarmoniaPlayerApp.swift` 14,
  `AppDelegate.swift` 2), `FileInfoView.swift` 0 (AC6).
- `user_guide.md`, read in full for AC8: the File Info "Technical info"
  bullet lists bitrate, sample rate, channel count, file size, and file
  format, while the window's TECHNICAL section shows format, codec,
  encoding, duration, bit rate, sample rate, and channels, with file size
  under LOCATION. Outside this slice's frozen scope; left for a
  documentation pass.

### Implementation notes

- Mechanism: in a window, `.textSelection(.enabled)` backs the `Text`
  with an AppKit text field sized by SwiftUI; the static cell drawing
  honours the two-line cap, but the field editor installed on the first
  click lays the whole string out, and with `clipsToBounds` false the
  extra lines paint past the row. The fix removes the disagreement
  rather than clipping it: with no cap, SwiftUI's measured height is the
  full text height, which is what the field editor draws.
- `fixedSize(horizontal: false, vertical: true)` keeps the row at its
  text height even if a parent proposed less; the `ScrollView` proposes
  no height, so it is a guard, not a behaviour change.
- Position identity (`enumerated()` + `\.offset`) keeps the visual order
  equal to the stored order and gives two identical strings two rows;
  `\.self` would give them one id and undefined diffing.
- Fixture recipe for AC4 (duplicates) or any URL length, on a copy of a
  Free-format audio file:
  ```bash
  python3 -c 'import plistlib,sys; sys.stdout.buffer.write(plistlib.dumps(["https://example.org/a","https://example.org/a"], fmt=plistlib.FMT_BINARY))' > wf.plist
  xattr -wx com.apple.metadata:kMDItemWhereFroms "$(xxd -p wf.plist | tr -d '\n')" "<file>"
  ```
  `xattr -l "<file>"` shows the attribute; the app reads the xattr
  directly, so Spotlight indexing is not required.
- Manual recipe (AC2 / AC3): only one HarmoniaPlayer instance may run at
  a time (the App Store build and the Xcode build share the bundle ID
  and `playlists.json`); the File Info window is resized by dragging its
  edge, and SOURCE is the last section, reached by scrolling.
- Token discipline: `grep -nE "Slice [0-9]|v[0-9]+\.[0-9]"` on the added
  lines before the commit.
