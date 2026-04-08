# Slice 09 Micro-slices Specification

## Purpose

This document defines **Slice 9: Pro Tier — IAP, Tag Editor, Lyrics, Now Playing, Gapless**
for HarmoniaPlayer.

Slice 9 implements the full Pro purchase flow via StoreKit 2 and unlocks
Pro-only features: FLAC/DSD playback (already gated in Slice 5-A), Tag Editor,
LRC synchronised lyrics, and Gapless playback. Two all-tier features are also
added in this slice: USLT static lyrics display/edit and MPNowPlayingInfoCenter
integration.

> **Prerequisite:** HarmoniaCore TagBundle patch must be committed before any
> Slice 9 work begins. The patch adds `composer`, `trackTotal`, `discTotal`,
> `bpm`, `replayGainTrack`, `replayGainAlbum`, `comment` to `TagBundle` and
> updates `AVMetadataTagReaderAdapter` accordingly. Without this patch,
> `HarmoniaTagReaderAdapter` does not compile.

---

## Slice 9 Overview

### Sub-slice summary

| Sub-slice | Content | Tier |
|---|---|---|
| 9-A | StoreKit 2 IAP + Paywall UI | — |
| 9-B | Tag Editor — basic fields | Pro |
| 9-C | Tag Editor — sort fields | Pro |
| 9-D | Tag Editor — artwork | Pro |
| 9-E | Lyrics — USLT static display + edit | All tiers |
| 9-F | Lyrics — LRC synchronised display | Pro |
| 9-G | MPNowPlayingInfoCenter + MPRemoteCommandCenter | All tiers |
| 9-H | Gapless playback | Pro |

### Goals
- Implement real StoreKit 2 purchase flow for Pro unlock
- Show Paywall UI when user attempts a Pro-only action
- Unlock FLAC/DSD playback after purchase (format gating already in place)
- Allow Pro users to edit audio file tags (ID3 / MP4 metadata)
- Display and edit embedded lyrics (USLT) for all users
- Synchronised LRC lyrics display for Pro users
- Integrate macOS Now Playing media control centre for all users
- Eliminate silence gap between tracks for Pro users (Gapless)

### Non-goals
- Tag editor for FLAC / Vorbis Comment (requires HarmoniaCore TagLib support, future)
- Equalizer / DSP (Slice 10-A)
- iCloud sync (future)
- Word-level karaoke / SYLT tag (post-Slice 9 backlog)

### Constraints
- `import HarmoniaCore` restricted to Integration Layer files only
- Tag writing uses `AVMutableMetadataItem` (Apple formats only — MP3, AAC, ALAC, AIFF)
- Format gating for FLAC/DSD already in `AppState.play(trackID:)` — no changes needed
- All new Pro-only actions must call `AppState.showPaywallIfNeeded()` before proceeding

### Dependencies
- Requires: Slice 8 complete
- Requires: HarmoniaCore TagBundle patch committed
- Requires: App Store Connect product ID configured (`harmoniaplayer.pro`)
- Requires: Slice 7-G Track model (Groups A–E fields already defined)

---

## Slice 9-A: StoreKit 2 IAP + Paywall UI

### Goal
Replace `FreeTierIAPManager` with a real StoreKit 2 implementation.
Show a Paywall sheet when the user attempts a Pro-only action on the Free tier.

### Scope
- Extend `IAPManager` protocol: add `refreshEntitlements() async` and
  `purchasePro() async throws`
- Implement `StoreKitIAPManager` conforming to `IAPManager`:
  - `refreshEntitlements()` — verify existing purchases on launch via
    `Transaction.currentEntitlements(for:)`
  - `purchasePro()` — StoreKit 2 `Product.purchase()` flow
  - `isProUnlocked: Bool` — `true` after verified purchase; persisted in
    `UserDefaults` as a fast-read cache
  - `Transaction.updates` listener Task started in `init()` — handles
    Ask to Buy approvals, Family Sharing grants, and purchases completed
    while the app was in the background; required by Apple for App Store
    approval; `updatesTask` cancelled in `deinit`
- `HarmoniaPlayerApp` uses `StoreKitIAPManager` in production;
  `MockIAPManager` remains for tests
- New `PaywallView` sheet:
  - Shown when Free user triggers a Pro-only action
  - Lists Pro features: FLAC/DSD, Tag Editor, LRC Sync, Gapless
  - "Unlock Pro" button → calls `iapManager.purchasePro()`
  - "Restore Purchases" button → calls `iapManager.refreshEntitlements()`
- Add `AppState.showPaywall: Bool` — set `true` when any Pro action is blocked
- `AppState.showPaywallIfNeeded() -> Bool` — returns `true` and sets
  `showPaywall = true` when `!isProUnlocked`; returns `false` otherwise
- `AppState.featureFlags` changed to `private(set) var` — rebuilt after
  `purchasePro()` and `refreshEntitlements()` so play gate reflects updated tier
- Format handling in `load(urls:)`:
  - All tiers: FLAC/DSF/DFF added to playlist; PlaylistView shows strikethrough
    for Free users; `play(trackID:)` presents Paywall when user attempts playback
  - All tiers: unrecognised formats blocked, `skippedUnsupportedURLs` set, alert shown
  - `AppState.freeFormats` / `proOnlyFormats` static sets for classification
- `AppState.paywallDismissedThisSession: Bool` — session-only flag; when `true`,
  `trackDidFinishPlaying()` silently skips Pro-format tracks during auto-play;
  manual selection always shows Paywall regardless
- `PlaylistView`: Pro-format tracks show strikethrough + tertiary colour for Free users
- `PlaylistView.openFilePicker()`: FLAC/DSF/DFF always visible in Open panel
- `PaywallView`: checkbox "本次使用期間，自動播放遇到付費格式時直接跳過，不再提醒"
  (default checked); sets `paywallDismissedThisSession` on Maybe Later
- `MiniPlayerView`: Paywall sheet + track list popover with lock icon for
  format-gated tracks
- `ContentView`: unsupported format alert binding

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/IAPManager.swift`
  (modify — add `IAPError`, `refreshEntitlements()`, `purchasePro()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/FreeTierIAPManager.swift`
  (modify — add stub `refreshEntitlements()`, `purchasePro()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/StoreKitIAPManager.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PaywallView.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/ContentView.swift`
  (modify — Paywall sheet, unsupported format alert)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift`
  (modify — Open panel always includes FLAC/DSF/DFF; strikethrough for
  Pro-format tracks when Free tier)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/MiniPlayerView.swift`
  (modify — Paywall sheet; track list popover with lock icon for format-gated tracks)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — `showPaywall`, `showPaywallIfNeeded()`, `paywallDismissedThisSession`,
  `featureFlags` var, `freeFormats`/`proOnlyFormats`, `skippedUnsupportedURLs`,
  load behaviour in `load(urls:)`, `trackDidFinishPlaying()` silent skip,
  `purchasePro()`, `refreshEntitlements()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift`
  (modify — use `StoreKitIAPManager` in production)
- `App/HarmoniaPlayer/HarmoniaPlayer/en.lproj/Localizable.strings`
  (modify — add `alert_unsupported_format_title/body`)
- `App/HarmoniaPlayer/HarmoniaPlayer/zh-Hant.lproj/Localizable.strings`
  (modify — add `alert_unsupported_format_title/body`)
- `App/HarmoniaPlayer/HarmoniaPlayer/ja.lproj/Localizable.strings`
  (modify — add `alert_unsupported_format_title/body`)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/FakeInfrastructure/MockIAPManager.swift`
  (modify — add stub `refreshEntitlements()`, `purchasePro()`)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/IAPManagerTests.swift`
  (modify — add `@MainActor`, `bundleURL` helper, Pro unlock flow tests)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateFormatGatingTests.swift`
  (modify — replace play-gate FLAC+Free tests with load-gate tests)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/IntegrationTests.swift`
  (modify — update `testIntegration_UnsupportedFormat_Free` for load gate)

### Public API shape

```swift
// IAPManager protocol additions
protocol IAPManager: AnyObject {
    var isProUnlocked: Bool { get }
    func refreshEntitlements() async
    func purchasePro() async throws
}

// StoreKitIAPManager
final class StoreKitIAPManager: IAPManager {
    private(set) var isProUnlocked: Bool = false
    private var updatesTask: Task<Void, Never>?   // started in init(), cancelled in deinit
    func refreshEntitlements() async
    func purchasePro() async throws
}

// AppState additions
@Published var showPaywall: Bool = false
@Published var paywallDismissedThisSession: Bool = false   // session-only, not persisted
@Published var skippedUnsupportedURLs: [URL] = []

static let freeFormats: Set<String>    = ["mp3", "aac", "m4a", "wav", "aiff", "alac"]
static let proOnlyFormats: Set<String> = ["flac", "dsf", "dff"]

@discardableResult
func showPaywallIfNeeded() -> Bool
func purchasePro() async throws
func refreshEntitlements() async
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testIsProUnlocked_DefaultIsFalse` | Fresh `MockIAPManager` | read `isProUnlocked` | `false` |
| `testShowPaywallIfNeeded_ReturnsTrueForFreeUser` | `isProUnlocked == false` | `showPaywallIfNeeded()` | returns `true`, `showPaywall == true` |
| `testShowPaywallIfNeeded_ReturnsFalseForProUser` | `isProUnlocked == true` | `showPaywallIfNeeded()` | returns `false`, `showPaywall == false` |
| `testLoad_FLAC_FreeTier_AddsToPlaylist` | `isProUnlocked == false`, `.flac` URL | `load(urls:)` | `playlist.tracks.count == 1`, `showPaywall == false` |
| `testLoad_FLAC_ProTier_AddsToPlaylist` | `isProUnlocked == true`, `.flac` URL | `load(urls:)` | `playlist.tracks.count == 1` |
| `testLoad_UnsupportedFormat_BlockedWithAlert` | any tier, `.xyz` URL | `load(urls:)` | playlist empty, `skippedUnsupportedURLs.count == 1` |
| `testPlayGate_FLAC_FreeTier_ShowsPaywall` | Free, FLAC in playlist | `play(trackID:)` | `showPaywall == true` |
| `testPlayGate_FLAC_FreeTier_DoesNotPlay` | Free, FLAC in playlist | `play(trackID:)` | `fakePlaybackService.loadCallCount == 0` |
| `testPaywallDismissedThisSession_DefaultIsFalse` | Fresh `AppState` | read `paywallDismissedThisSession` | `false` |
| `testAutoPlay_FLAC_DismissedSession_SilentSkip` | Free, `paywallDismissedThisSession == true`, playlist [MP3, FLAC, MP3] | `trackDidFinishPlaying()` from MP3[0] | plays MP3[2], `showPaywall == false` |
| `testAutoPlay_FLAC_NotDismissed_ShowsPaywall` | Free, `paywallDismissedThisSession == false`, playlist [MP3, FLAC] | `trackDidFinishPlaying()` from MP3[0] | `showPaywall == true` |

### Done criteria
- ✅ `StoreKitIAPManager` fetches product and completes purchase via StoreKit 2
- ✅ `Transaction.updates` listener running throughout app lifecycle; handles Ask to Buy and background purchases
- ✅ `isProUnlocked` persists across launches after purchase
- ✅ `featureFlags` rebuilt after purchase/restore so play gate reflects updated tier
- ✅ FLAC/DSF/DFF visible in Open panel for all tiers; added to playlist for all tiers
- ✅ Free user drops/imports FLAC → added to playlist with strikethrough
- ✅ Free user plays FLAC → Paywall shown, track not played
- ✅ Pro user plays FLAC → plays normally, no Paywall
- ✅ Unrecognised format → unsupported format alert, track not added
- ✅ "Restore Purchases" correctly restores prior purchase
- ✅ PaywallView checkbox sets `paywallDismissedThisSession` on Maybe Later
- ✅ Auto-play silently skips Pro-format tracks when `paywallDismissedThisSession == true`
- ✅ MiniPlayerView shows Paywall sheet and track list popover
- ✅ All IAPManagerTests and AppStateFormatGatingTests green
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-A): implement StoreKit 2 IAP, Paywall UI, and Pro-format display

- Add IAPError enum and extend IAPManager protocol: refreshEntitlements(), purchasePro()
- Add StoreKitIAPManager: StoreKit 2 purchase and restore, UserDefaults cache
- Add StoreKitIAPManager.updatesTask: observe Transaction.updates for Ask to Buy,
  Family Sharing, and background purchase completion (required for App Store approval)
- Add PaywallView: Pro feature list, Unlock Pro, Restore Purchases, Maybe Later,
  session-skip checkbox (default checked)
- AppState.showPaywall and showPaywallIfNeeded()
- AppState.paywallDismissedThisSession: session-only flag for silent auto-play skip
- AppState.featureFlags: private(set) var, rebuilt after purchasePro/refreshEntitlements
- AppState.load(urls:): allow FLAC/DSF/DFF into playlist for all tiers;
  only truly unsupported formats are blocked
- AppState.trackDidFinishPlaying(): silently skip format-gated tracks when
  paywallDismissedThisSession is true (all repeat modes and shuffle)
- AppState.freeFormats / proOnlyFormats static format classification sets
- PlaylistView: strikethrough and tertiary colour for Pro-format tracks on Free tier;
  Open panel always shows FLAC/DSF/DFF
- MiniPlayerView: Paywall sheet; track list popover with lock icon for format-gated tracks
- ContentView: Paywall sheet, unsupported format alert
- Localizable (en/zh-Hant/ja): alert_unsupported_format_title/body,
  paywall_skip_session_checkbox
- HarmoniaPlayerApp: switch to StoreKitIAPManager, refresh entitlements on launch
- MockIAPManager: PurchaseResult enum, mutable isProUnlocked, call tracking
- IAPManagerTests: @MainActor, bundleURL helper, Pro unlock flow tests
- AppStateFormatGatingTests: rewritten to cover new load + play + auto-play behaviour
- IntegrationTests: update UnsupportedFormat_Free for new load behaviour
```

---

## Slice 9-B: Tag Editor — Basic Fields

### Goal
Allow Pro users to edit core audio file tags and write them back to the file.

### Scope
- New `TagWriterService` protocol (Application Layer)
  - Accepts `Track` (Application Layer type), NOT `TagBundle` (HarmoniaCore type)
  - `HarmoniaTagWriterAdapter` (Integration Layer) is responsible for converting
    `Track` fields into `TagBundle` before calling `AVMutableTagWriterAdapter`
- New `HarmoniaTagWriterAdapter` (Integration Layer — wraps `AVMutableTagWriterAdapter`)
- New `TagEditorView` sheet (Pro-only, lives in `macOS/Pro/Views/`):
  - Triggered via right-click context menu → "Edit Tags" or ⌘E
  - Pro gate: calls `showPaywallIfNeeded()` before opening sheet
  - Editable fields: title, artist, album, albumArtist, composer, genre,
    year, trackNumber, trackTotal, discNumber, discTotal, bpm, comment
- On save: `TagEditorView` calls `AppState.saveTagEdits(trackID:editedTrack:)`,
  which passes the updated `Track` to `TagWriterService`, then updates
  `AppState.playlists` immediately — HarmoniaCore types never reach AppState
- `AppState.saveTagEdits(trackID:editedTrack:)` — coordinates write + model update

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/TagWriterService.swift`
  (new — protocol)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaTagWriterAdapter.swift`
  (new — Integration Layer, wraps `AVMutableTagWriterAdapter`; converts `Track` → `TagBundle` internally)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Pro/Views/TagEditorView.swift`
  (new — Pro-only view)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `showTagEditor`, `tagEditorTrack`, `saveTagEdits(trackID:editedTrack:)`,
  `showTagEditorIfAllowed(trackID:)`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/PlaylistView.swift`
  (modify — add right-click "Edit Tags" context menu item)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/HarmoniaPlayerCommands.swift`
  (modify — add ⌘E shortcut, Pro-gated)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/TagWriterServiceTests.swift`
  (new)

### Public API shape

```swift
// TagWriterService protocol — Application Layer only; no HarmoniaCore types
protocol TagWriterService: AnyObject {
    // Accepts Track (Application Layer type).
    // HarmoniaTagWriterAdapter converts Track → TagBundle internally.
    func writeTags(from track: Track, to url: URL) async throws
}

// AppState additions
@Published var showTagEditor: Bool = false
@Published var tagEditorTrack: Track? = nil

func showTagEditorIfAllowed(trackID: Track.ID)
// editedTrack carries the user's edits; AppState passes it to TagWriterService
// and then overwrites the matching entry in playlists[]
func saveTagEdits(trackID: Track.ID, editedTrack: Track) async
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testShowTagEditor_Free_ShowsPaywall` | `isProUnlocked == false` | `showTagEditorIfAllowed(trackID:)` | `showPaywall == true`, `showTagEditor == false` |
| `testShowTagEditor_Pro_OpensEditor` | `isProUnlocked == true`, track in playlist | `showTagEditorIfAllowed(trackID:)` | `showTagEditor == true`, `tagEditorTrack != nil` |
| `testSaveTagEdits_UpdatesTrackTitle` | Track with title "Old" in playlist | `saveTagEdits(trackID:editedTrack:)` with title "New" | `playlist.tracks[0].title == "New"` |
| `testSaveTagEdits_UpdatesTrackArtist` | Track with artist "Old" | `saveTagEdits(trackID:editedTrack:)` with artist "New" | `playlist.tracks[0].artist == "New"` |

### Done criteria
- ✅ Tag Editor sheet opens on right-click or ⌘E for Pro users
- ✅ Paywall shown when Free user triggers ⌘E or right-click "Edit Tags"
- ✅ All basic fields editable and saved to file
- ✅ `Track` in playlist updated immediately after save
- ✅ TagWriterServiceTests green
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-B): add Tag Editor for basic fields (Pro)

- Add TagWriterService protocol (accepts Track, not TagBundle — module boundary safe)
- Add HarmoniaTagWriterAdapter: Integration Layer, converts Track → TagBundle internally
- Add TagEditorView (macOS/Pro/Views/): basic fields (Groups A+C from Track model)
- Add AppState.showTagEditor, tagEditorTrack, saveTagEdits(trackID:editedTrack:)
- Add right-click "Edit Tags" in PlaylistView context menu
- Add ⌘E shortcut in HarmoniaPlayerCommands (Pro-gated)
- Pro-gate: showPaywallIfNeeded() before opening editor
- Add TagWriterServiceTests
```

---

## Slice 9-C: Tag Editor — Sort Fields

### Goal
Add sort fields to the Tag Editor.

### Scope
- Add sort tag fields to `Track` model:
  `sortTitle`, `sortArtist`, `sortAlbum`, `sortAlbumArtist`, `sortComposer`
  (all `String`, default `""`)
- Map sort fields in `HarmoniaTagReaderAdapter` from `TagBundle`
  (requires HarmoniaCore TagBundle patch to include sort fields)
- Add "Sorting" tab to `TagEditorView`
- Write sort fields back to file on save via `TagWriterService`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Track.swift`
  (modify — add sort fields)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaTagReaderAdapter.swift`
  (modify — map sort fields from `TagBundle`)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Pro/Views/TagEditorView.swift`
  (modify — add Sorting tab)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/TrackTests.swift`
  (modify — add sort field tests)

### Public API shape

```swift
// Track additions
var sortTitle: String        // TSOT — default ""
var sortArtist: String       // TSOP — default ""
var sortAlbum: String        // TSOA — default ""
var sortAlbumArtist: String  // TSO2 — default ""
var sortComposer: String     // TSOC — default ""
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultSortFields_AreAllEmpty` | `Track(url:)` | read all sort fields | all `""` |
| `testTrack_SortFields_Codable_RoundTrip` | Track with all sort fields set | encode → decode | all sort fields match original |
| `testSortFields_MappedFromTagBundle` | `TagBundle` with sort fields populated | `HarmoniaTagReaderAdapter.readMetadata` | `Track` sort fields match `TagBundle` values |
| `testSortFields_DefaultToEmpty_WhenTagBundleNil` | `TagBundle` with sort fields `nil` | `HarmoniaTagReaderAdapter.readMetadata` | `Track` sort fields all `""` |

### Done criteria
- ✅ Sort fields visible and editable in "Sorting" tab of Tag Editor
- ✅ Sort fields written to file on save
- ✅ Sort fields correctly read from files that have them
- ✅ TrackTests green
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-C): add sort fields to Tag Editor

- Add sortTitle, sortArtist, sortAlbum, sortAlbumArtist, sortComposer to Track
- Map sort fields in HarmoniaTagReaderAdapter from TagBundle
- Add Sorting tab to TagEditorView
- Add sort field tests to TrackTests
```

---

## Slice 9-D: Tag Editor — Artwork

### Goal
Allow Pro users to view and replace embedded album artwork in the Tag Editor.

### Scope
- Add "Artwork" tab to `TagEditorView`:
  - Displays current embedded artwork (`Track.artworkData`), or a placeholder
    if absent
  - "Add Artwork" button → `NSOpenPanel` filters for `.jpg`, `.png`
  - "Remove Artwork" button → clears `artworkData` in the pending edit bundle
- Save writes `artworkData` to file via `HarmoniaTagWriterAdapter`
- `artworkData` already exists in both `Track` and `TagBundle` — no model
  changes needed

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Pro/Views/TagEditorView.swift`
  (modify — add Artwork tab)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaTagWriterAdapter.swift`
  (modify — write `artworkData` via `AVMutableMetadataItem`)

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testSaveTagEdits_Artwork_UpdatesTrack` | Track with `artworkData == nil` | `saveTagEdits` with non-nil `artworkData` | `playlist.tracks[0].artworkData != nil` |
| `testSaveTagEdits_RemoveArtwork_ClearsTrack` | Track with `artworkData` set | `saveTagEdits` with `artworkData == nil` | `playlist.tracks[0].artworkData == nil` |

### Done criteria
- ✅ Artwork tab shows current embedded image (placeholder if absent)
- ✅ Add Artwork loads image from disk and previews before save
- ✅ Remove Artwork clears the embedded image
- ✅ Save writes artwork correctly to file
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-D): add artwork tab to Tag Editor

- Add Artwork tab to TagEditorView: display, add, remove artwork
- Implement artworkData write in HarmoniaTagWriterAdapter
```

---

## Slice 9-E: Lyrics — USLT Static Display + Edit (All Tiers)

### Goal
Allow all users to view embedded unsynchronised lyrics.
Allow Pro users to edit lyrics via the Tag Editor.

### Scope
- Add `lyrics: String?` to `Track` model (default `nil`)
- Map `USLT` tag in `HarmoniaTagReaderAdapter` from `TagBundle`
  (requires HarmoniaCore TagBundle patch to include `lyrics`)
- New `LyricsView`: read-only lyrics panel accessible from `PlayerView`
  for all users; shows empty state when `Track.lyrics == nil`
- Add "Lyrics" tab to `TagEditorView`: multiline `TextEditor`
  for Pro users to edit `lyrics` content
- Save writes `USLT` tag back to file via `TagWriterService`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Track.swift`
  (modify — add `lyrics: String?`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaTagReaderAdapter.swift`
  (modify — map `USLT` from `TagBundle`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/LyricsView.swift`
  (new — read-only static display, all tiers)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Pro/Views/TagEditorView.swift`
  (modify — add Lyrics tab)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/TrackTests.swift`
  (modify — add `lyrics` field tests)

### Public API shape

```swift
// Track addition
var lyrics: String?   // USLT — default nil
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultLyrics_IsNil` | `Track(url:)` | read `lyrics` | `nil` |
| `testTrack_Lyrics_Codable_RoundTrip` | Track with `lyrics` set | encode → decode | `lyrics` matches original |
| `testLyrics_MappedFromTagBundle` | `TagBundle` with `lyrics` populated | `HarmoniaTagReaderAdapter.readMetadata` | `Track.lyrics` matches `TagBundle.lyrics` |
| `testLyrics_NilWhenTagBundleNil` | `TagBundle` with `lyrics == nil` | `HarmoniaTagReaderAdapter.readMetadata` | `Track.lyrics == nil` |
| `testSaveTagEdits_Lyrics_UpdatesTrack` | Track with `lyrics == nil` | `saveTagEdits` with new lyrics string | `playlist.tracks[0].lyrics == new value` |

### Done criteria
- ✅ `LyricsView` shows USLT lyrics for all users
- ✅ Empty state shown when `Track.lyrics == nil`
- ✅ Edit and save via Tag Editor writes USLT back to file (Pro only)
- ✅ TrackTests green
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-E): add USLT lyrics display and editing

- Add Track.lyrics (USLT tag, all tiers)
- Map USLT in HarmoniaTagReaderAdapter from TagBundle
- Add LyricsView: read-only static display (all tiers)
- Add Lyrics tab to TagEditorView (write via TagWriterService, Pro-gated)
- Add lyrics field tests to TrackTests
```

---

## Slice 9-F: Lyrics — LRC Synchronised Display (Pro)

### Goal
Display LRC-format synchronised lyrics with line-by-line auto-scrolling,
highlighting the current line during playback. Pro only.

### Scope
- New `LRCLine` model: `timestamp: TimeInterval`, `text: String`
- New `LRCParser`: parses `[mm:ss.xx]` format into `[LRCLine]`
- LRC data source (priority order):
  1. Sidecar `.lrc` file at the same path as the audio file
  2. Embedded SYLT tag (deferred to post-Slice 9 backlog)
- `AppState` loads sidecar `.lrc` in `play(trackID:)` if present;
  stores parsed lines in `@Published var lrcLines: [LRCLine]`
- `LyricsView` extended with synchronised mode: observes `currentTime`,
  highlights current line, auto-scrolls with `ScrollViewReader`
- Pro gate: synchronised mode calls `showPaywallIfNeeded()`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/LRCLine.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/LRCParser.swift`
  (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Views/LyricsView.swift`
  (modify — add synchronised mode)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `lrcLines`, load sidecar `.lrc` in `play(trackID:)`)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/LRCParserTests.swift`
  (new)

### Public API shape

```swift
// LRCLine
struct LRCLine: Equatable, Sendable {
    let timestamp: TimeInterval
    let text: String
}

// LRCParser
struct LRCParser {
    func parse(_ content: String) -> [LRCLine]
}

// AppState addition
@Published private(set) var lrcLines: [LRCLine] = []
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testParse_ValidLRC_ReturnsTwoLines` | `"[00:01.00]Hello\n[00:03.00]World"` | `parse()` | `count == 2`, timestamps 1.0 and 3.0 |
| `testParse_EmptyString_ReturnsEmpty` | `""` | `parse()` | `[]` |
| `testParse_InvalidTimestamp_LineSkipped` | `"[xx:xx]Bad\n[00:01.00]Good"` | `parse()` | `count == 1` |
| `testParse_LinesAreSortedByTimestamp` | Lines in reverse order in file | `parse()` | lines sorted ascending by `timestamp` |
| `testParse_BlankTextLine_Included` | `"[00:02.00]"` | `parse()` | `count == 1`, `text == ""` |

### Done criteria
- ✅ Sidecar `.lrc` file loaded automatically when track plays
- ✅ Current line highlighted and view scrolls in sync with `currentTime`
- ✅ Pro gate: Paywall shown for Free users
- ✅ LRCParserTests green
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-F): add LRC synchronised lyrics display (Pro)

- Add LRCLine model and LRCParser (parse [mm:ss.xx] format)
- Add AppState.lrcLines: load from sidecar .lrc in play(trackID:)
- Extend LyricsView: synchronised mode with auto-scroll and line highlight
- Pro-gate: showPaywallIfNeeded() before enabling synchronised mode
- Add LRCParserTests (5 cases)
```

---

## Slice 9-G: MPNowPlayingInfoCenter + MPRemoteCommandCenter (All Tiers)

### Goal
Integrate with macOS Now Playing media control centre: show artwork, title,
artist, duration, and currentTime; respond to remote play/pause/next/previous
commands.

### Scope
- New `NowPlayingService` protocol (Application Layer)
- New `MPNowPlayingAdapter` (Integration Layer — allowed to `import MediaPlayer`)
- `AppState` calls `nowPlayingService.update(...)` at:
  - `play(trackID:)` — on successful play start
  - `pause()` — on pause
  - `stop()` — clear Now Playing
  - polling loop — `currentTime` update every ~1 s
- Register `MPRemoteCommandCenter` handlers wired to `AppState` actions:
  play, pause, nextTrack, previousTrack, changePlaybackPosition
- Artwork provided as `MPMediaItemArtwork` from `Track.artworkData`
- `HarmoniaPlayerApp` injects `MPNowPlayingAdapter`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/NowPlayingService.swift`
  (new — protocol)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/MPNowPlayingAdapter.swift`
  (new — Integration Layer)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — inject `NowPlayingService`, call `update` at play/pause/stop/poll)
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift`
  (modify — inject `MPNowPlayingAdapter` into `AppState`)

### Public API shape

```swift
// NowPlayingService protocol
protocol NowPlayingService: AnyObject {
    func update(track: Track?, state: PlaybackState,
                time: TimeInterval, duration: TimeInterval)
    func registerRemoteCommands(
        onPlay: @escaping () async -> Void,
        onPause: @escaping () async -> Void,
        onNext: @escaping () async -> Void,
        onPrev: @escaping () async -> Void,
        onSeek: @escaping (TimeInterval) async -> Void
    )
    func clearNowPlaying()
}
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testNowPlaying_UpdateCalledOnPlay` | Track playing | `play(trackID:)` succeeds | `NowPlayingService.update` called with matching track and `.playing` state |
| `testNowPlaying_ClearCalledOnStop` | Playback active | `stop()` | `NowPlayingService.clearNowPlaying` called |
| `testNowPlaying_UpdateCalledOnPause` | Track playing | `pause()` | `NowPlayingService.update` called with `.paused` state |
| `testNowPlaying_RemotePlay_InvokesAppStatePlay` | Remote play command received | handler fires | `AppState.play()` invoked |
| `testNowPlaying_RemoteNext_InvokesPlayNextTrack` | Remote next command received | handler fires | `AppState.playNextTrack()` invoked |

### Done criteria
- ✅ macOS Now Playing widget shows correct title, artist, artwork, duration
- ✅ `currentTime` updates during playback in Now Playing widget
- ✅ Play/Pause/Next/Previous/Seek commands from widget work correctly
- ✅ Now Playing cleared when playback stops
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-G): integrate MPNowPlayingInfoCenter and MPRemoteCommandCenter

- Add NowPlayingService protocol and MPNowPlayingAdapter
- Wire update() calls in AppState: play, pause, stop, polling loop
- Register remote commands: play, pause, next, prev, seek
- Inject MPNowPlayingAdapter in HarmoniaPlayerApp
```

---

## Slice 9-H: Gapless Playback (Pro)

### Goal
Eliminate the silence gap between tracks during continuous playback.

### Scope
- When `currentTime` approaches `duration - gaplessPreloadThreshold` (default 5 s),
  `AppState` pre-loads the next track URL into a secondary `PlaybackService`
  instance in the background
- On natural completion (`trackDidFinishPlaying`), swap primary and secondary
  service references and call `play()` immediately — no engine restart
- `CoreFactory`: new `makeGaplessPlaybackServicePair()` returns two
  `PlaybackService` instances sharing the same `AVAudioEngineOutputAdapter`
  so the audio engine stays running across the handoff
- `CoreFeatureFlags`: add `supportsGapless: Bool { isProUnlocked }`
- Free tier: single `PlaybackService`, existing behaviour unchanged
- Pro gate: `showPaywallIfNeeded()` if user explicitly requests Gapless toggle

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreFactory.swift`
  (modify — add `makeGaplessPlaybackServicePair()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
  (modify — add `secondaryPlaybackService`, `gaplessPreloadThreshold`,
  `preloadNextTrackIfNeeded()`)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/CoreFeatureFlags.swift`
  (modify — add `supportsGapless`)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateGaplessTests.swift`
  (new)

### Public API shape

```swift
// CoreFeatureFlags addition
var supportsGapless: Bool { isProUnlocked }

// AppState additions (private)
private var secondaryPlaybackService: PlaybackService?
private let gaplessPreloadThreshold: TimeInterval = 5.0
private func preloadNextTrackIfNeeded() async
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testSupportsGapless_TrueForPro` | `isProUnlocked == true` | read `featureFlags.supportsGapless` | `true` |
| `testSupportsGapless_FalseForFree` | `isProUnlocked == false` | read `featureFlags.supportsGapless` | `false` |
| `testGaplessPreload_TriggeredNearEnd` | Pro user, 2 tracks, `currentTime` within 5 s of `duration` | polling fires | secondary service loaded with next track URL |
| `testGaplessPreload_NotTriggered_FreeTier` | Free user, 2 tracks | polling fires near end | `secondaryPlaybackService == nil` |
| `testGaplessPreload_NotTriggered_WhenNoNextTrack` | Pro user, 1 track (last in playlist) | polling fires near end | no secondary load attempted |

### Done criteria
- ✅ No audible gap between tracks during normal Pro playback
- ✅ Preload triggered at ~5 s before end of current track
- ✅ Free tier behaviour unchanged (single `PlaybackService`)
- ✅ Paywall shown if Free user explicitly toggles Gapless setting
- ✅ AppStateGaplessTests green
- ✅ All Slice 1–8 tests still green

### Commit message
```
feat(slice 9-H): implement gapless playback (Pro)

- Add CoreFeatureFlags.supportsGapless
- Add CoreFactory.makeGaplessPlaybackServicePair(): shared AVAudioEngineOutputAdapter
- Add AppState gapless preload logic with 5 s threshold
- preloadNextTrackIfNeeded() triggered from polling loop
- Pro-gate: Free tier uses single PlaybackService unchanged
- Add AppStateGaplessTests (5 cases)
```

---

## Slice 9 TDD Matrix

### Test principles
- All tests must be deterministic
- No audio device dependencies
- `MockIAPManager` and all `Fake*` types in test target only
- Test classes that test `AppState` must be `@MainActor`

---

### Slice 9-A — IAP

| Test | Given | When | Then |
|---|---|---|---|
| `testIsProUnlocked_DefaultIsFalse` | Fresh `MockIAPManager` | read `isProUnlocked` | `false` |
| `testShowPaywallIfNeeded_ReturnsTrueForFreeUser` | `isProUnlocked == false` | `showPaywallIfNeeded()` | returns `true`, `showPaywall == true` |
| `testShowPaywallIfNeeded_ReturnsFalseForProUser` | `isProUnlocked == true` | `showPaywallIfNeeded()` | returns `false`, `showPaywall == false` |
| `testLoad_FLAC_FreeTier_AddsToPlaylist` | Free, `.flac` URL | `load(urls:)` | `playlist.tracks.count == 1`, `showPaywall == false` |
| `testLoad_FLAC_ProTier_AddsToPlaylist` | Pro, `.flac` URL | `load(urls:)` | `playlist.tracks.count == 1` |
| `testLoad_UnsupportedFormat_BlockedWithAlert` | any tier, `.xyz` URL | `load(urls:)` | playlist empty, `skippedUnsupportedURLs.count == 1` |
| `testPlayGate_FLAC_FreeTier_ShowsPaywall` | Free, FLAC in playlist | `play(trackID:)` | `showPaywall == true` |
| `testPlayGate_FLAC_FreeTier_DoesNotPlay` | Free, FLAC in playlist | `play(trackID:)` | `loadCallCount == 0` |
| `testPaywallDismissedThisSession_DefaultIsFalse` | Fresh `AppState` | read `paywallDismissedThisSession` | `false` |
| `testAutoPlay_FLAC_DismissedSession_SilentSkip` | Free, dismissed, [MP3, FLAC, MP3] | `trackDidFinishPlaying()` from MP3[0] | plays MP3[2], no Paywall |
| `testAutoPlay_FLAC_NotDismissed_ShowsPaywall` | Free, not dismissed, [MP3, FLAC] | `trackDidFinishPlaying()` from MP3[0] | `showPaywall == true` |

---

### Slice 9-B — Tag Editor Basic Fields

| Test | Given | When | Then |
|---|---|---|---|
| `testShowTagEditor_Free_ShowsPaywall` | `isProUnlocked == false` | `showTagEditorIfAllowed(trackID:)` | `showPaywall == true`, `showTagEditor == false` |
| `testShowTagEditor_Pro_OpensEditor` | `isProUnlocked == true`, track in playlist | `showTagEditorIfAllowed(trackID:)` | `showTagEditor == true`, `tagEditorTrack != nil` |
| `testSaveTagEdits_UpdatesTrackTitle` | Track with title "Old" | `saveTagEdits(trackID:editedTrack:)` with title "New" | `playlist.tracks[0].title == "New"` |
| `testSaveTagEdits_UpdatesTrackArtist` | Track with artist "Old" | `saveTagEdits(trackID:editedTrack:)` with artist "New" | `playlist.tracks[0].artist == "New"` |

---

### Slice 9-C — Sort Fields

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultSortFields_AreAllEmpty` | `Track(url:)` | read all sort fields | all `""` |
| `testTrack_SortFields_Codable_RoundTrip` | Track with all sort fields set | encode → decode | all sort fields match original |
| `testSortFields_MappedFromTagBundle` | `TagBundle` with sort fields populated | `HarmoniaTagReaderAdapter.readMetadata` | `Track` sort fields match `TagBundle` values |
| `testSortFields_DefaultToEmpty_WhenTagBundleNil` | `TagBundle` with sort fields `nil` | `HarmoniaTagReaderAdapter.readMetadata` | `Track` sort fields all `""` |

---

### Slice 9-D — Artwork

| Test | Given | When | Then |
|---|---|---|---|
| `testSaveTagEdits_Artwork_UpdatesTrack` | Track with `artworkData == nil` | `saveTagEdits` with non-nil `artworkData` | `playlist.tracks[0].artworkData != nil` |
| `testSaveTagEdits_RemoveArtwork_ClearsTrack` | Track with `artworkData` set | `saveTagEdits` with `artworkData == nil` | `playlist.tracks[0].artworkData == nil` |

---

### Slice 9-E — USLT Lyrics

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultLyrics_IsNil` | `Track(url:)` | read `lyrics` | `nil` |
| `testTrack_Lyrics_Codable_RoundTrip` | Track with `lyrics` set | encode → decode | `lyrics` matches original |
| `testLyrics_MappedFromTagBundle` | `TagBundle` with `lyrics` populated | `HarmoniaTagReaderAdapter.readMetadata` | `Track.lyrics` matches `TagBundle.lyrics` |
| `testLyrics_NilWhenTagBundleNil` | `TagBundle` with `lyrics == nil` | `HarmoniaTagReaderAdapter.readMetadata` | `Track.lyrics == nil` |
| `testSaveTagEdits_Lyrics_UpdatesTrack` | Track with `lyrics == nil` | `saveTagEdits` with new lyrics string | `playlist.tracks[0].lyrics == new value` |

---

### Slice 9-F — LRC Parser

| Test | Given | When | Then |
|---|---|---|---|
| `testParse_ValidLRC_ReturnsTwoLines` | `"[00:01.00]Hello\n[00:03.00]World"` | `parse()` | `count == 2`, timestamps 1.0 and 3.0 |
| `testParse_EmptyString_ReturnsEmpty` | `""` | `parse()` | `[]` |
| `testParse_InvalidTimestamp_LineSkipped` | `"[xx:xx]Bad\n[00:01.00]Good"` | `parse()` | `count == 1` |
| `testParse_LinesAreSortedByTimestamp` | Lines in reverse order in file | `parse()` | lines sorted ascending by `timestamp` |
| `testParse_BlankTextLine_Included` | `"[00:02.00]"` | `parse()` | `count == 1`, `text == ""` |

---

### Slice 9-G — Now Playing

| Test | Given | When | Then |
|---|---|---|---|
| `testNowPlaying_UpdateCalledOnPlay` | Track playing | `play(trackID:)` succeeds | `NowPlayingService.update` called with matching track and `.playing` state |
| `testNowPlaying_ClearCalledOnStop` | Playback active | `stop()` | `NowPlayingService.clearNowPlaying` called |
| `testNowPlaying_UpdateCalledOnPause` | Track playing | `pause()` | `NowPlayingService.update` called with `.paused` state |
| `testNowPlaying_RemotePlay_InvokesAppStatePlay` | Remote play command received | handler fires | `AppState.play()` invoked |
| `testNowPlaying_RemoteNext_InvokesPlayNextTrack` | Remote next command received | handler fires | `AppState.playNextTrack()` invoked |

---

### Slice 9-H — Gapless

| Test | Given | When | Then |
|---|---|---|---|
| `testSupportsGapless_TrueForPro` | `isProUnlocked == true` | read `featureFlags.supportsGapless` | `true` |
| `testSupportsGapless_FalseForFree` | `isProUnlocked == false` | read `featureFlags.supportsGapless` | `false` |
| `testGaplessPreload_TriggeredNearEnd` | Pro user, 2 tracks, `currentTime` within 5 s of `duration` | polling fires | secondary service loaded with next track URL |
| `testGaplessPreload_NotTriggered_FreeTier` | Free user, 2 tracks | polling fires near end | `secondaryPlaybackService == nil` |
| `testGaplessPreload_NotTriggered_WhenNoNextTrack` | Pro user, 1 track (last in playlist) | polling fires near end | no secondary load attempted |

---

## Slice 9 Completion Gate

### Required

- ⬜ `StoreKitIAPManager` purchases and restores correctly
- ⬜ Paywall shown for all Pro-only actions (FLAC/DSD, Tag Editor, LRC Sync, Gapless)
- ⬜ `isProUnlocked` persists after purchase
- ⬜ Tag Editor opens for Pro users (⌘E / right-click)
- ⬜ Basic fields (Groups A+C) editable and saved to file
- ⬜ Sort fields editable and saved to file
- ⬜ Artwork viewable, replaceable, removable
- ⬜ USLT lyrics viewable by all users; editable via Tag Editor (Pro)
- ⬜ LRC synchronised display for Pro users
- ⬜ macOS Now Playing widget integrated for all users
- ⬜ Gapless playback for Pro users
- ⬜ All Slice 9 unit tests green
- ⬜ All Slice 1–8 tests still green

---

## Related Slices

- **Slice 5-A (Format Gating)** — FLAC/DSD gate already in `AppState.play(trackID:)`;
  9-A only needs to provide real `isProUnlocked == true`
- **Slice 6 (UI + Menu Bar)** — `HarmoniaPlayerCommands` extended with ⌘E shortcut in 9-B
- **Slice 7-G (Track model)** — Groups A–E fields are the editable fields in 9-B/C/E
- **Slice 7-H (File Info Panel)** — Tag Editor shares the same right-click trigger pattern
- **Slice 8-C (ReplayGain)** — same `applyVolume` pattern reused in 9-H gapless handoff