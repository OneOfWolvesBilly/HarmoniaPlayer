# Slice 09 Micro-slices Specification

## Purpose

This document defines **Slice 9: StoreKit 2 IAP + v0.1 Free Preparation**
for HarmoniaPlayer.

Slice 9 builds the StoreKit 2 purchase infrastructure, freezes Pro features
for v0.1 Free release, and prepares infrastructure for the v0.2 Tag Editor.

> **Prerequisite:** HarmoniaCore TagBundle patch must be committed before any
> Slice 9 work begins. The patch adds `composer`, `trackTotal`, `discTotal`,
> `bpm`, `replayGainTrack`, `replayGainAlbum`, `comment` to `TagBundle` and
> updates `AVMetadataTagReaderAdapter` accordingly.

> **Prerequisite (9-B):** HarmoniaCore `AVMutableTagWriterAdapter` bug fix must
> be committed before 9-B work begins. Replace `removeItem` + `moveItem` with
> `replaceItemAt` for atomic file replacement.

---

## Slice 9 Overview

### Sub-slice summary

| Sub-slice | Content | Tier | Status |
|---|---|---|---|
| 9-A | StoreKit 2 IAP infra + Paywall (built, UI hidden) + v0.1 Free load gate | — | ✅ |
| Post-9-A | v0.1 freeze fixes + architecture cleanup (pre-9-B preparation) | Free | ✅ |
| 9-B | HarmoniaCore replaceItemAt fix + FileInfoView read-only + FileOriginService | Free | ✅ |
| 9-C | Codec + Encoding fields (TagBundle → Track → FileInfoView) | Free | ✅ |
| 9-D | FileInfoView `.sheet` → independent `WindowGroup` | Free | ✅ |
| 9-E | Fix polling loop CPU issue (`CancellationError` handling) | Free | ✅ |
| 9-F | Error reporting Phase 1 (`lastErrorDetail` + mailto) | Free | ✅ |
| 9-G | Play/Pause menu label investigation (`@FocusedObject` limitation) | Free | ✅ |
| 9-H | Fix MiniPlayer menu bar (hiddenTitleBar + focusedSceneValue) + remove expand button | Free | ✅ |
| 9-I | Fix Xcode warnings (cosmetic) | Free | ✅ |
| 9-J | Lyrics display (USLT + sidecar .lrc, full text) | Free | ⬜ |
| 9-K | Equalizer (10-band, global, custom presets) | Free | ⬜ |
| 9-L | macOS Now Playing integration (Control Center / lock screen / media keys) | Free | ⬜ |

### Goals (v0.1)

- Build StoreKit 2 purchase flow (`StoreKitIAPManager`) ✅
- Build Paywall sheet (`PaywallView`) — hidden in v0.1 ✅
- Gate FLAC/DSF/DFF at load time — blocked as unsupported ✅
- Add batch operation safety (`isPerformingBlockingOperation`, sub-batch save) ✅
- Add directory drag-and-drop with recursive scanning (`FileDropService`) ✅
- Fix HarmoniaCore tag writer to preserve xattr on file replacement
- Make FileInfoView read-only (source editing deferred to v0.2 Tag Editor)
- Define `FileOriginService` protocol (infrastructure for v0.2)
- Add Codec + Encoding to FileInfoView Technical section
- Convert FileInfoView from `.sheet` to independent `WindowGroup`
- Fix polling loop CPU issue (proper `CancellationError` handling)
- Add error reporting Phase 1 (mailto prefilled)
- Investigate Play/Pause menu label update reliability — verified resolved in Slice 8-A ✅
- Fix MiniPlayer menu bar becoming non-functional when main window is ordered out
- Fix Xcode warnings in test files

### Non-goals
- Pro paywall visible in v0.1 (deferred to v0.2)
- FLAC/DSD playback (deferred to v0.2)
- Tag editing UI (deferred to v0.2 — see Slice 10)

### Constraints
- `import HarmoniaCore` restricted to Integration Layer files only
- All Pro UI commented out but code preserved for v0.2 restore
- File origin (`kMDItemWhereFroms`) is filesystem metadata, not audio metadata —
  `FileOriginService` lives in Application Layer, not HarmoniaCore

### Dependencies
- Requires: Slice 8 complete
- Requires: HarmoniaCore TagBundle patch committed
- Requires: HarmoniaCore `AVMutableTagWriterAdapter` replaceItemAt fix (before 9-B)
- Requires: App Store Connect product ID configured (`harmoniaplayer.pro`)

---

## Slice 9-A: StoreKit 2 IAP Infrastructure + v0.1 Free Load Gate ✅

### Goal
Build the full StoreKit 2 IAP infrastructure and Paywall UI. Then freeze
all Pro features for v0.1 Free release: FLAC/DSF/DFF blocked at load time,
Pro UI hidden.

### Scope

#### StoreKit 2 infrastructure
- Extend `IAPManager` protocol: add `refreshEntitlements() async` and
  `purchasePro() async throws`
- Implement `StoreKitIAPManager` conforming to `IAPManager`:
  - `refreshEntitlements()` — verify existing purchases via
    `Transaction.currentEntitlement(for:)`
  - `purchasePro()` — StoreKit 2 `Product.purchase()` flow
  - `isProUnlocked: Bool` — persisted in `UserDefaults` as fast-read cache
  - `Transaction.updates` listener started in `init()`
- `HarmoniaPlayerApp` uses `StoreKitIAPManager` in production
- `AppState.featureFlags` changed to `private(set) var` — rebuilt after
  `purchasePro()` and `refreshEntitlements()`

#### Paywall UI (built, hidden in v0.1)
- New `PaywallView` sheet: lists Pro features, "Unlock Pro" button,
  "Restore Purchases" button, session skip checkbox
- `AppState.showPaywall: Bool`, `showPaywallIfNeeded() -> Bool`,
  `paywallDismissedThisSession: Bool`
- `MiniPlayerView`: track list popover, `bringMainWindowToFront`
  notification listener to close self before Paywall shows on main window
- `HarmoniaPlayerApp`: `.defaultLaunchBehavior(.suppressed)` +
  `didFinishLaunching` observer to prevent MiniPlayer auto-restoration

#### v0.1 Free load gate
- `AppState.freeFormats` / `proOnlyFormats` static sets for classification
- New `allowedFormats` computed property: v0.1 returns `freeFormats` only
- New `isURLSupported(_:)` uses `allowedFormats`
- `load(urls:)`: FLAC/DSF/DFF rejected, `skippedUnsupportedURLs` alert
- `importPlaylist(from:)`: `isURLSupported()` check + final `saveState()`
- Pro format gate in `play(trackID:)` commented out (unreachable)
- `trackDidFinishPlaying()` Pro format gate commented out (3 places)
- `openFilePicker` FLAC/DSF/DFF removed (commented out)
- "Upgrade to Pro" menu commented out
- Launch `refreshEntitlements` commented out

#### Batch operation safety
- New `isPerformingBlockingOperation: Bool` — set `true` / `defer false`
  in `load(urls:)` and `importPlaylist(from:)`
- Menu items disabled when flag is true; drop closures return `false`
- Sub-batch save every 5 tracks (`saveBatchSize`) for crash safety

#### Directory drag-and-drop
- New `FileDropService`: validates URLs, recursively expands directories
- `openFilePicker`: `canChooseDirectories = true`

### Files

- `Shared/Services/IAPManager.swift` (modify)
- `Shared/Services/FreeTierIAPManager.swift` (modify)
- `Shared/Services/StoreKitIAPManager.swift` (new)
- `Shared/Services/FileDropService.swift` (new)
- `Shared/Views/PaywallView.swift` (new)
- `Shared/Views/ContentView.swift` (modify)
- `Shared/Views/PlaylistView.swift` (modify)
- `macOS/Free/Views/MiniPlayerView.swift` (modify)
- `macOS/Free/Views/HarmoniaPlayerCommands.swift` (modify)
- `Shared/Models/AppState.swift` (modify)
- `Shared/Models/AppState+Playlist.swift` (modify)
- `Shared/Models/AppState+M3U8.swift` (modify)
- `macOS/Free/HarmoniaPlayerApp.swift` (modify)
- `{en,zh-Hant,ja}.lproj/Localizable.strings` (modify)

Test target:
- `FakeInfrastructure/MockIAPManager.swift` (modify)
- `SharedTests/IAPManagerTests.swift` (modify)
- `SharedTests/AppStateFormatGatingTests.swift` (modify)
- `SharedTests/IntegrationTests.swift` (modify)
- `SharedTests/AppStatePlayerlistTests.swift` (modify)
- `SharedTests/AppStatePersistenceTests.swift` (modify)
- `SharedTests/FileDropServiceTests.swift` (new)

### Public API shape

```swift
// IAPManager protocol
protocol IAPManager: AnyObject {
    var isProUnlocked: Bool { get }
    func refreshEntitlements() async
    func purchasePro() async throws
}

// StoreKitIAPManager
final class StoreKitIAPManager: IAPManager {
    private(set) var isProUnlocked: Bool   // didSet → UserDefaults
    private var updatesTask: Task<Void, Never>?
}

// AppState additions
@Published var showPaywall: Bool = false
@Published var paywallDismissedThisSession: Bool = false
@Published var skippedUnsupportedURLs: [URL] = []
@Published var isPerformingBlockingOperation: Bool = false

static let freeFormats: Set<String>    = ["mp3", "aac", "m4a", "wav", "aiff", "alac"]
static let proOnlyFormats: Set<String> = ["flac", "dsf", "dff"]
static var allowedFormats: Set<String> { freeFormats }
static let saveBatchSize = 5

@discardableResult
func showPaywallIfNeeded() -> Bool
func purchasePro() async throws
func refreshEntitlements() async

// FileDropService
struct FileDropService {
    func validate(_ urls: [URL]) -> [URL]
}
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testIsProUnlocked_DefaultIsFalse` | Fresh `MockIAPManager` | read `isProUnlocked` | `false` |
| `testShowPaywallIfNeeded_ReturnsTrueForFreeUser` | `isProUnlocked == false` | `showPaywallIfNeeded()` | returns `true`, `showPaywall == true` |
| `testShowPaywallIfNeeded_ReturnsFalseForProUser` | `isProUnlocked == true` | `showPaywallIfNeeded()` | returns `false`, `showPaywall == false` |
| `testPaywallDismissedThisSession_DefaultIsFalse` | Fresh `AppState` | read | `false` |
| `testLoad_UnsupportedFormat_BlockedWithAlert` | any tier, `.xyz` URL | `load(urls:)` | playlist empty, `skippedUnsupportedURLs.count == 1` |
| `testLoad_FLAC_FreeTier_Blocked` | Free, `.flac` URL | `load(urls:)` | playlist empty |
| `testIsPerformingBlockingOperation_TrueDuringLoad` | start `load(urls:)` | read flag | `true` |
| `testIsPerformingBlockingOperation_FalseAfterLoad` | `load(urls:)` completes | read flag | `false` |
| `testValidate_AudioFile_Accepted` | `.mp3` file URL | `validate([url])` | returns `[url]` |
| `testValidate_NonAudioFile_Rejected` | `.txt` file URL | `validate([url])` | returns `[]` |
| `testValidate_Directory_ExpandsRecursively` | directory with nested audio | `validate([dirURL])` | returns all audio files |
| `testValidate_Directory_SkipsHiddenFiles` | `.hidden.mp3` | `validate([dirURL])` | hidden file not in result |

Pro format gate tests (14 tests commented out, full bodies preserved for v0.2).

### Done criteria

- ✅ `StoreKitIAPManager` builds and conforms to `IAPManager`
- ✅ `Transaction.updates` listener running throughout app lifecycle
- ✅ `isProUnlocked` persisted in UserDefaults via didSet
- ✅ `featureFlags` rebuilt after `purchasePro()` / `refreshEntitlements()`
- ✅ `PaywallView` built (hidden in v0.1)
- ✅ FLAC/DSF/DFF blocked at load time via `allowedFormats`
- ✅ All Pro UI commented out
- ✅ `isPerformingBlockingOperation` prevents concurrent batch ops
- ✅ Sub-batch save every 5 tracks
- ✅ `FileDropService` recursively expands directories
- ✅ All v0.1 tests green
- ✅ All Slice 1–8 tests still green

### Commit message

```
feat(slice 9-A): add StoreKit 2 IAP infrastructure and v0.1 Free load gate

- Add StoreKitIAPManager with refreshEntitlements, purchasePro, Transaction.updates
- Add PaywallView sheet (hidden in v0.1)
- Add showPaywall, showPaywallIfNeeded, paywallDismissedThisSession to AppState
- Add freeFormats, proOnlyFormats, allowedFormats (v0.1: Free only)
- Block FLAC/DSF/DFF at load time via allowedFormats
- Comment out Pro UI: play gate, autoplay gate, Upgrade menu, refreshEntitlements
- Add isPerformingBlockingOperation with menu and drop disable
- Add sub-batch save every 5 tracks
- Add FileDropService with recursive directory expansion
- Add FileDropServiceTests
```

---

## Post-9-A: v0.1 Freeze Fixes + Architecture Cleanup ✅

Preparation fixes committed after 9-A and before 9-B. These address
architecture issues (Split A/B/C) and bug fixes discovered during v0.1
freeze testing. They are not part of any sub-slice's SDD scope —
they are reactive fixes that clean up technical debt before 9-B begins.

### Commits

```
chore(v0.1-freeze): comment out launch refreshEntitlements
chore(v0.1-freeze): comment out Upgrade to Pro menu item
feat(v0.1-freeze): add isPerformingBlockingOperation flag with menu and drop disable
feat(v0.1): support directory drop and selection in file picker
feat(v0.1-freeze): dynamic allowedFormats, hide Pro formats from load and import
docs(v0.1-freeze): update api_reference and slice_09_micro for v0.1 freeze
refactor: split AppState.swift into 5 extension files
refactor(slice 9): remove AVFoundation from HarmoniaTagReaderAdapter
refactor(slice 9): replace string-matching error mapping with typed PlaybackError codes
fix(slice 9): stop() clears currentTrack
fix(slice 9): promote selectedTrackIDs to AppState and update play() resolution
fix(slice 9): add .disabled() conditions to menu items matching PlayerView logic
feat(free): add artwork display section to FileInfoView
```

### Summary of changes

- **Split A:** Remove AVFoundation from `HarmoniaTagReaderAdapter` — all metadata
  reading delegated to HarmoniaCore
- **Split B:** Remove `PlaybackError.coreError(String)` — replaced with typed
  `.invalidState` / `.invalidArgument`; `CoreError → PlaybackError` mapping now
  in `HarmoniaPlaybackServiceAdapter.mapCoreError()`
- **Split C:** Split `AppState.swift` into 5 extension files for maintainability
- **Bug fixes:** `stop()` clears `currentTrack`; `selectedTrackIDs` promoted to
  `AppState` for `play()` selection resolution; menu `.disabled()` conditions
  aligned with `PlayerView` logic
- **Feature:** Artwork display added to `FileInfoView` (Free tier, read-only)

---

## Slice 9-B: FileInfoView Read-Only + FileOriginService

### Goal
Fix HarmoniaCore tag writer to preserve file attributes on write.
Make FileInfoView read-only (source editing deferred to v0.2 Tag Editor).
Define `FileOriginService` protocol as infrastructure for v0.2.

### Scope

#### HarmoniaCore bug fix
- `AVMutableTagWriterAdapter`: replace `removeItem` + `moveItem` with
  `replaceItemAt` for atomic file replacement preserving xattr, creation
  date, ACL, and ownership

#### FileInfoView read-only refactor
- Remove Source section Edit/Clear buttons and all editing state
- Add `languageBundle: Bundle` init parameter for L() localisation
- ContentView sheet call passes `appState.languageBundle`

#### FileOriginService (Application Layer)
- New `FileOriginService` protocol: `read(url:)`, `write(_:url:)`, `clear(url:)`
- New `FileOriginError` enum: `.writeFailed(String)`, `.clearFailed(String)`
- New `DarwinFileOriginAdapter` wraps existing `ExtendedAttributeService`
- `ExtendedAttributeService` retained as bottom-level Darwin utility
- Infrastructure only — `CoreServiceProviding` / `CoreFactory` /
  `HarmoniaCoreProvider` / `AppState` wiring is deferred to v0.2 along with
  Source editing (see "Deferred to v0.2" note below)

### Files

HarmoniaCore:
- `Adapters/AVMutableTagWriterAdapter.swift` (modify — `replaceItemAt`)
- `Tests/AVMutableTagWriterAdapterTests.swift` (modify — xattr + creation date tests)

HarmoniaPlayer:
- `Shared/Services/FileOriginService.swift` (new — protocol + `FileOriginError`)
- `Shared/Services/DarwinFileOriginAdapter.swift` (new)
- `Shared/Views/FileInfoView.swift` (modify — read-only, `languageBundle`)
- `Shared/Views/ContentView.swift` (modify — pass `languageBundle`)

Test target:
- `FakeInfrastructure/FakeFileOriginService.swift` (new)
- `SharedTests/FileOriginServiceTests.swift` (new)

### Public API shape

```swift
// FileOriginService protocol — Application Layer
protocol FileOriginService: AnyObject {
    func read(url: URL) -> [String]
    func write(_ sources: [String], url: URL) throws
    func clear(url: URL) throws
}

enum FileOriginError: Error, LocalizedError {
    case writeFailed(String)
    case clearFailed(String)
}
```

### TDD matrix

HarmoniaCore:

| Test | Given | When | Then |
|---|---|---|---|
| `testReplaceFile_PreservesXattr` | original file has xattr | `replaceFile(at:withTempFileAt:)` | xattr preserved on replaced file |
| `testReplaceFile_PreservesCreationDate` | original file has past creation date | `replaceFile(at:withTempFileAt:)` | creation date preserved (not reset to "now") |

> Note: these tests exercise the internal helper `replaceFile(at:withTempFileAt:)`
> that `write(url:tags:)` delegates the final file swap to. Testing the helper
> directly with plain `.bin` temp files avoids depending on an AVFoundation
> export session or a real audio fixture in the HarmoniaCore test target.

HarmoniaPlayer:

| Test | Given | When | Then |
|---|---|---|---|
| `testFileOriginRead_WhenPresent_ReturnsURLs` | xattr exists | `read(url:)` | returns URL array |
| `testFileOriginRead_WhenAbsent_ReturnsEmpty` | no xattr | `read(url:)` | returns `[]` |
| `testFileOriginWrite_PersistsValue` | empty file | `write(sources, url:)` → `read` | returns written value |
| `testFileOriginClear_RemovesAttribute` | xattr exists | `clear(url:)` → `read` | returns `[]` |
| `testFileOriginClear_WhenAbsent_DoesNotThrow` | no xattr | `clear(url:)` | does not throw |

### Done criteria

- ⬜ HarmoniaCore: `AVMutableTagWriterAdapter` uses `replaceItemAt`, xattr preserved
- ⬜ `FileOriginService` protocol defined in Application Layer
- ⬜ `DarwinFileOriginAdapter` wraps `ExtendedAttributeService`
- ⬜ `FileInfoView` read-only, Edit/Clear removed, `languageBundle` added
- ⬜ All 9-B TDD matrix tests green
- ⬜ All Slice 1–8 tests still green

### Commit order

```
1. fix(slice 9-B): HarmoniaCore — replace removeItem+moveItem with replaceItemAt
2. feat(slice 9-B): add FileOriginService protocol and DarwinFileOriginAdapter
3. refactor(slice 9-B): make FileInfoView read-only, remove source editing
```

Commit 1 is a HarmoniaCore repo commit. Commits 2–3 are HarmoniaPlayer.

### Deferred to v0.2

Because Source editing is read-only in v0.1 Free, the following items that
were originally planned inside 9-B are deferred to the v0.2 Tag Editor slice:

- `CoreServiceProviding` / `CoreFactory` / `HarmoniaCoreProvider` extended with
  `makeFileOriginService()`
- `AppState` receives `fileOriginService` via factory
- `FakeCoreProvider` adds `fileOriginServiceStub`
- `CoreFactoryTests` updates
- `testMakeFileOriginService_ReturnsNonNil`
- `saveSources()` / `clearSources()` alert-on-failure UX and the
  `testSaveSources_Failure_ShowsAlert` test

Commit 2 already lands the protocol, adapter, fake, and adapter tests, so the
v0.2 Tag Editor slice starts from a ready FileOriginService foundation.

---

## Slice 9-C: Codec + Encoding Fields

### Goal
Add Codec (e.g. AAC, MP3, ALAC) and Encoding (lossy/lossless) fields to
the metadata pipeline so FileInfoView's Technical section shows accurate
stream information instead of relying on file extension alone.

### Scope

#### HarmoniaCore TagBundle changes
- Add `codec: String?` to `TagBundle` (e.g. "AAC", "MP3", "ALAC", "PCM")
- Add `encoding: String?` to `TagBundle` (e.g. "lossy", "lossless")
- `AVMetadataTagReaderAdapter`: read codec from `AVAssetTrack.mediaType` /
  `formatDescriptions`; derive encoding from codec type

#### HarmoniaPlayer mapping
- `Track`: add `codec: String` (default `""`) and `encoding: String` (default `""`)
- `HarmoniaTagReaderAdapter`: map `TagBundle.codec` → `Track.codec`,
  `TagBundle.encoding` → `Track.encoding`
- `FileInfoView` Technical section: display Codec and Encoding rows
- `metadataVersion` bump so `refreshMetadataIfNeeded()` re-reads existing tracks

### Files

HarmoniaCore:
- `Models/TagBundle.swift` (modify — add `codec`, `encoding`)
- `Adapters/AVMetadataTagReaderAdapter.swift` (modify — read codec/encoding)
- `Tests/TagBundleTests.swift` (modify)

HarmoniaPlayer:
- `Shared/Models/Track.swift` (modify — add `codec`, `encoding`)
- `Shared/Services/HarmoniaTagReaderAdapter.swift` (modify — map fields)
- `Shared/Views/FileInfoView.swift` (modify — display rows)

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testTagBundle_Codec_DefaultNil` | empty TagBundle | read `codec` | `nil` |
| `testTrack_Codec_DefaultEmpty` | `Track(url:)` | read `codec` | `""` |
| `testCodec_MappedFromTagBundle` | TagBundle with `codec = "AAC"` | readMetadata | `Track.codec == "AAC"` |
| `testEncoding_MappedFromTagBundle` | TagBundle with `encoding = "lossy"` | readMetadata | `Track.encoding == "lossy"` |

### Done criteria

- ⬜ HarmoniaCore: `TagBundle` has `codec` and `encoding` fields
- ⬜ `AVMetadataTagReaderAdapter` reads codec/encoding from AVFoundation
- ⬜ `Track` has `codec` and `encoding`; mapped in `HarmoniaTagReaderAdapter`
- ⬜ `FileInfoView` Technical section displays Codec and Encoding
- ⬜ `metadataVersion` bumped; existing tracks re-read on launch
- ⬜ All tests green

### Commit order

```
1. feat(HarmoniaCore): add codec and encoding fields to TagBundle and AVMetadataTagReaderAdapter
2. feat(slice 9-C): map codec and encoding to Track and display in FileInfoView
```

---

## Slice 9-D: FileInfoView `.sheet` → `WindowGroup`

### Goal
Convert FileInfoView from a modal `.sheet` to an independent `WindowGroup`
so it can be dragged, resized, and kept open during playback. Enables
multi-track comparison by opening multiple info windows.

### Scope
- Replace `.sheet(item: $appState.fileInfoTrack)` with a `WindowGroup`
  identified by track ID
- FileInfoView becomes a standalone window: resizable, draggable, non-modal
- Support multiple simultaneous FileInfoView windows (one per track)
- Window title shows track display name
- Close via ⌘W or window close button

### Files

- `Shared/Views/FileInfoView.swift` (modify — standalone window adaptations)
- `Shared/Views/ContentView.swift` (modify — remove `.sheet`, use `openWindow`)
- `macOS/Free/HarmoniaPlayerApp.swift` (modify — add `WindowGroup` for FileInfo)
- `Shared/Models/AppState.swift` (modify — adjust `fileInfoTrack` / `showFileInfo` logic)

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testShowFileInfo_SetsTrack` | Track in playlist | `showFileInfo(trackID:)` | `fileInfoTrack` set |
| `testShowFileInfo_InvalidID_NoOp` | No matching track | `showFileInfo(trackID: random)` | `fileInfoTrack == nil` |

### Done criteria

- ⬜ FileInfoView opens as independent non-modal window
- ⬜ Window is draggable and resizable
- ⬜ Multiple FileInfoView windows can be open simultaneously
- ⬜ Main window remains interactive while FileInfoView is open
- ⬜ All tests green

### Commit message

```
feat(slice 9-D): convert FileInfoView from sheet to independent WindowGroup

- Replace .sheet(item:) with WindowGroup identified by track ID
- Support multiple simultaneous FileInfoView windows
- Window is resizable, draggable, non-modal
```

---

## Slice 9-E: Fix Polling Loop CPU Issue

### Goal
Replace `try? await Task.sleep` in the polling loop with proper `do/catch`
for `CancellationError` to prevent unnecessary CPU usage when polling
should have stopped.

### Scope
- In `AppState+Playback.swift` `startPolling()`: replace `try? await Task.sleep`
  with `do { try await Task.sleep } catch { break }` so cancellation
  cleanly exits the loop
- Verify `stopPolling()` is called when `playbackState` transitions to `.stopped`
- Verify polling task is cancelled on `stop()` and `play(trackID:)` reload

### Files

- `Shared/Models/AppState+Playback.swift` (modify — polling loop)

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testStopPolling_CancelsTask` | Playing with active polling | `stop()` | `pollingTask` cancelled |
| `testPolling_StopsOnCancellation` | Active polling | cancel `pollingTask` | loop exits cleanly |

### Done criteria

- ⬜ `Task.sleep` cancellation handled with `do/catch`, not `try?`
- ⬜ `stopPolling()` called on `.stopped` transition
- ⬜ No residual CPU usage after stop
- ⬜ All tests green

### Commit message

```
fix(slice 9-E): replace try? await Task.sleep with proper CancellationError handling in polling loop

- Use do/catch instead of try? so CancellationError exits the loop cleanly
- Verify stopPolling() called when playbackState transitions to .stopped
```

---

## Slice 9-F: Error Reporting Phase 1

### Goal
Add a basic error reporting mechanism so users can send diagnostic
information when playback fails. Phase 1 uses a prefilled mailto link —
no network calls, no PII, no telemetry.

### Scope

- Add `lastErrorDetail: String?` to `AppState` — captures a one-line
  diagnostic summary when `lastError` is set, in the format
  `"<errorCode>: <track.url.path>"` or `"<errorCode>: (no active track)"`
  for error sites without a known track (e.g. `seek()` catch)
- All four error sites in `AppState+Playback.swift` set `lastErrorDetail`:
  `play()` catch, `seek()` catch, `play(trackID:)` inaccessibility gate,
  `play(trackID:)` load/play catch
- `clearLastError()` also clears `lastErrorDetail`
- New `ErrorReportService` (Application Layer, pure struct):
  builds a `mailto:` URL from detail string + app version + macOS version.
  Does not perform I/O — only URL construction, unit-testable in isolation.
- "Report Issue" button added to the **playback-error alert** in
  `ContentView` (i.e. the alert triggered by `lastError != nil` excluding
  `.failedToOpenFile`). The `file-not-found alert` (auto-dismiss 3 s) is
  **not** modified — its short lifetime makes a manual button impractical,
  and the user already knows the file is missing.
- Button action calls `NSWorkspace.shared.open(_:)` on the mailto URL:
  - To: `harmonia.audio.project+harmonia_player@gmail.com`
  - Subject: `[HarmoniaPlayer] Error Report` (not localized)
  - Body: detail line + app version + macOS version (not localized — easier
    for triage across all users)
- New localized string `alert_report_issue_button` (en / zh-Hant / ja)

### Design rationale: subject and body not localized

The mailto subject (`[HarmoniaPlayer] Error Report`) and body (detail +
versions) are intentionally kept in English for every locale. Reasons:

1. Error triage is done by the developer reading incoming mail; a uniform
   language simplifies filtering, searching, and pattern matching across
   reports from all locales
2. `lastErrorDetail` itself already embeds a non-localized error code
   string (e.g. `failedToDecode`) — localizing the surrounding body while
   keeping the error code English would be inconsistent
3. File paths in the detail are not translatable regardless of UI locale
4. Only the **button label** (`alert_report_issue_button`) is presented
   to the user in-app, and that one is localized

### Files

HarmoniaPlayer:
- `Shared/Models/AppState.swift` (modify — add `@Published var lastErrorDetail: String?`,
  clear in `clearLastError()`)
- `Shared/Models/AppState+Playback.swift` (modify — set `lastErrorDetail` at
  all four error sites)
- `Shared/Services/ErrorReportService.swift` (new — pure struct, URL builder)
- `Shared/Views/ContentView.swift` (modify — "Report Issue" button on
  playback-error alert)
- `Resources/en.lproj/Localizable.strings` (add `alert_report_issue_button`)
- `Resources/zh-Hant.lproj/Localizable.strings` (add)
- `Resources/ja.lproj/Localizable.strings` (add)

Test target:
- `HarmoniaPlayerTests/SharedTests/AppStateErrorHandlingTests.swift`
  (modify — add `lastErrorDetail` tests)
- `HarmoniaPlayerTests/SharedTests/ErrorReportServiceTests.swift` (new)

### Public API shape

```swift
// AppState additions
@Published var lastErrorDetail: String?   // format: "<errorCode>: <path-or-noTrack>"

// AppState+Playback internal helper
private func makeErrorDetail(code: PlaybackError, track: Track?) -> String
// Examples:
//   makeErrorDetail(code: .failedToDecode, track: t)  -> "failedToDecode: /Users/x/song.mp3"
//   makeErrorDetail(code: .invalidState,   track: nil) -> "invalidState: (no active track)"

// ErrorReportService — Application Layer, pure struct
struct ErrorReportService {
    static let reportEmail = "harmonia.audio.project+harmonia_player@gmail.com"
    static let subjectLine = "[HarmoniaPlayer] Error Report"

    /// Builds a mailto URL with the given detail and runtime versions.
    /// Returns nil only if URLComponents fails to produce a URL (should not
    /// happen with valid inputs).
    static func buildMailtoURL(
        detail: String,
        appVersion: String,
        osVersion: String
    ) -> URL?
}
```

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testLastErrorDetail_PlayTrackDecodeFailure_ContainsCodeAndPath` | `play(trackID:)` throws `.failedToDecode` | error occurs | `lastErrorDetail` contains `"failedToDecode"` and `track.url.path` |
| `testLastErrorDetail_InaccessibleTrack_ContainsCodeAndPath` | `play(trackID:)` with inaccessible track | gate trips | `lastErrorDetail` contains `"failedToOpenFile"` and `track.url.path` |
| `testLastErrorDetail_SeekFailure_ContainsCodeAndNoTrack` | `seek()` catch path | error occurs | `lastErrorDetail` contains error code and `"(no active track)"` |
| `testLastErrorDetail_ClearedOnClearLastError` | `lastErrorDetail` set | `clearLastError()` | `lastErrorDetail == nil` |
| `testErrorReportService_BuildMailtoURL_ContainsToSubjectBody` | detail + versions | `buildMailtoURL()` | url.scheme == "mailto"; path is reportEmail; queryItems include subject and body |
| `testErrorReportService_BuildMailtoURL_EncodesSpecialChars` | body with `&` and newline | `buildMailtoURL()` | `absoluteString` contains `%26` and `%0A` |

### Done criteria

- ⬜ Error alert shows "Report Issue" button on playback-error alert
- ⬜ Mailto opens Mail.app with prefilled subject, body, and recipient
- ⬜ `lastErrorDetail` set at all four error sites in `AppState+Playback`
- ⬜ `lastErrorDetail` cleared when error is dismissed via `clearLastError()`
- ⬜ `ErrorReportService.buildMailtoURL` unit-tested in isolation
- ⬜ All tests green

### Commit order

```
1. feat(slice 9-F): add ErrorReportService with mailto URL builder
2. feat(slice 9-F): add lastErrorDetail to AppState and Report Issue alert button
```

Commit 1 is pure new code — service + its unit tests. No AppState changes.
Commit 2 wires `lastErrorDetail` into AppState error sites, adds the
ContentView button, and adds the localized string.

---

## Slice 9-G: Play/Pause Menu Label Investigation ✅

### Status

**Closed — resolved retroactively by Slice 8-A.**

### Background

At the time Slice 9-G was scoped, the Play/Pause menu bar label was
suspected to update unreliably because `@FocusedObject` does not
reliably re-evaluate a `Commands` body when a `@Published` property
of the focused object changes.

### Resolution

Slice 8-A already applied the SwiftUI-recommended workaround:

- `Shared/Views/PlaybackFocusedValues.swift` defines
  `PlaybackStateFocusedKey` carrying `PlaybackState` as a scalar value.
- `ContentView` propagates live state via
  `.focusedValue(\.playbackState, appState.playbackState)`.
- `HarmoniaPlayerCommands` reads it via
  `@FocusedValue(\.playbackState) private var focusedPlaybackState`.
- `playPauseLabel` is driven by `focusedPlaybackState`, not by
  `appState?.playbackState` observed through `@FocusedObject`.

This matches the pattern recommended in WWDC23 "SwiftUI cookbook for
focus": a scalar `FocusedValue` re-evaluates Commands reliably on
every state change, whereas `@FocusedObject` property observation
inside Commands can miss updates.

### Verification

Real-world manual testing after Slice 8-A landed confirmed the menu
bar Play/Pause label updates correctly on every state transition
(play → pause → stop → play, including cross-application focus
changes in the main window). No further code change is required for
v0.1.

### Files touched by Slice 8-A (retrospective reference)

- `Shared/Views/PlaybackFocusedValues.swift` (added)
- `Shared/Views/ContentView.swift` (`.focusedValue` propagation)
- `macOS/Free/Views/HarmoniaPlayerCommands.swift` (`@FocusedValue` adoption)

### Done criteria

- ✅ Play/Pause menu label updates correctly when playback state changes
- ✅ Root cause and adopted workaround documented
- ✅ No open `@FocusedObject` reliability issue remaining in v0.1

### Future considerations

If a future slice needs additional scalar state propagated to Commands
(e.g. Repeat mode or Shuffle state label live updates), extend
`PlaybackFocusedValues.swift` with additional `FocusedValueKey` types
rather than adding more `@FocusedObject`-observed properties.

See also: Slice 9-H for a related menu-bar symptom in the
MiniPlayer window.

---

## Slice 9-H: Fix MiniPlayer Menu Bar and Remove Expand Button

### Goal

Make the macOS menu bar Playback menu functional and correctly
labelled while MiniPlayer is the key window, and remove the
redundant expand button. The original `Window` scene used
`.windowStyle(.plain)`, which renders a borderless panel whose
underlying `NSWindow` returns `NO` from `canBecomeKeyWindow`. With
no key window, the SwiftUI focus system cannot propagate `AppState`
or `PlaybackState` to `HarmoniaPlayerCommands`, so all Playback
menu items render disabled while MiniPlayer is foreground. In
addition, the expand button in `playlistPickerRow` duplicates
behaviour already provided by the window's close button
(`WindowCloseObserver` brings the main window to front when
MiniPlayer closes).

### Prerequisite investigation

Confirmed via Apple documentation and independent macOS 15.6+
manual testing:

1. **`.windowStyle(.plain)` blocks `canBecomeKeyWindow`.** The
   `NSWindow` SwiftUI creates for `.plain` scenes overrides
   `canBecomeKeyWindow` to return `false`, producing the runtime
   log `-[NSWindow makeKeyWindow] ... returned NO from
   -[NSWindow canBecomeKeyWindow]`. With no key window the SwiftUI
   focus system has no active view chain, so every `@FocusedObject`
   / `@FocusedValue` / `@FocusedSceneValue` reads `nil` in
   `HarmoniaPlayerCommands`.
2. **`.focusedValue(_:_:)` requires an inner focused view.** Apple
   documentation: "SwiftUI will set the value of FocusedValue to
   `nil` as soon as the view loses the focus. You can use the
   focusedSceneValue view modifier whenever you need to share
   focused value between views in different scenes." MiniPlayer
   contains only Button and Slider controls with no naturally
   focused view, so `.focusedValue` never propagates here. The
   scene-scoped `.focusedSceneValue(_:_:)` must be used instead.
3. **`.focusedSceneObject(_:)` is already scene-scoped,** so it
   propagates correctly once the window is allowed to become key.
   No change to its call site is needed beyond adding the modifier
   to `MiniPlayerView.body`.

### Root cause

Two independent issues combine to disable the menu bar in
MiniPlayer mode:

- **Window style blocks focus entirely.** `HarmoniaPlayerApp`
  configures the MiniPlayer scene with `.windowStyle(.plain)`,
  which forbids the window from becoming key. When the main
  window is `orderOut` during MiniPlayer activation, no window is
  key, the focus system has no active view chain, and
  `@FocusedObject appState` in `HarmoniaPlayerCommands` reads
  `nil`. Every Playback menu item's `.disabled(playlistIsEmpty)`
  computes to `true` because `appState?.playlist.tracks.isEmpty
  != false` is `true` when `appState` is `nil`.
- **`.focusedValue` is the wrong API for this scene.** Even after
  the window can become key, exposing `playbackState` via
  `.focusedValue(\.playbackState, ...)` from `MiniPlayerView.body`
  still reads `nil` in `HarmoniaPlayerCommands`, because
  `.focusedValue` is view-scope and requires an inner focused view.
  MiniPlayer has no naturally focused view, so the Play/Pause
  label stays stuck on "Play" even while playback is active.

### Change

1. **`HarmoniaPlayerApp.swift`**: change the MiniPlayer scene
   modifier from `.windowStyle(.plain)` to
   `.windowStyle(.hiddenTitleBar)`. Preserves the minimal-chrome
   look while allowing `canBecomeKeyWindow = true`.

2. **`MiniPlayerView.swift`** (body tail): add two scene-scoped
   focus modifiers so `HarmoniaPlayerCommands` can read them when
   MiniPlayer is the key window:
   ```swift
   .focusedSceneObject(appState)
   .focusedSceneValue(\.playbackState, appState.playbackState)
   ```
   Note: `.focusedSceneValue`, not `.focusedValue` — the latter is
   view-scope and does not propagate in MiniPlayer's view tree.

3. **`MiniPlayerView.swift`** (`playlistPickerRow`): remove the
   expand button (`rectangle.expand.vertical` Image + `.help`
   tooltip + `closeMiniPlayer()` action). Its behaviour is fully
   covered by the window's close button via `WindowCloseObserver`.
   Replace the removed button with a 30pt-wide `Color.clear`
   balance spacer on the left side so the playlist menu stays
   horizontally centred (mirroring the existing right-side balance
   spacer). `closeMiniPlayer()` itself is retained because the
   `.bringMainWindowToFront` notification observer still calls it
   when a Pro-format gate triggers.

4. **Localizable.strings** (en, zh-Hant, ja): remove the
   `"mini_player_expand"` key, which becomes unused after change 3.

### Scope

- ✅ `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift`
  — one line change (window style)
- ✅ `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/Views/MiniPlayerView.swift`
  — body tail modifiers + expand button removal + balance spacer
- ✅ `App/HarmoniaPlayer/HarmoniaPlayer/en.lproj/Localizable.strings`
  — remove `"mini_player_expand"`
- ✅ `App/HarmoniaPlayer/HarmoniaPlayer/zh-Hant.lproj/Localizable.strings`
  — remove `"mini_player_expand"`
- ✅ `App/HarmoniaPlayer/HarmoniaPlayer/ja.lproj/Localizable.strings`
  — remove `"mini_player_expand"`
- ❌ No changes to `ContentView.swift` (its existing `.focusedValue`
  still works because `PlaylistView`'s List provides an inner
  focused view)
- ❌ No changes to `HarmoniaPlayerCommands.swift` or
  `PlaybackFocusedValues.swift`
- ❌ No changes to `AppState` or HarmoniaCore
- ❌ No changes to `WindowDragArea`, `FloatingWindowController`, or
  `WindowCloseObserver`

### TDD matrix

Not applicable. SwiftUI focus system behaviour,
`canBecomeKeyWindow` semantics, and `NSEventTrackingRunLoopMode`
interactions require a real window server and cannot be simulated
in Swift Testing / XCTest. Verification is manual real-device
testing, already completed during spec investigation.

### Done criteria

- ✅ `HarmoniaPlayerApp` applies `.windowStyle(.hiddenTitleBar)` to
  the MiniPlayer `Window` scene
- ✅ `MiniPlayerView.body` applies `.focusedSceneObject(appState)`
  and `.focusedSceneValue(\.playbackState, ...)`
- ✅ Expand button removed from `playlistPickerRow`; left-side
  balance spacer added so the playlist menu stays centred
- ✅ `"mini_player_expand"` key removed from all three
  `Localizable.strings` files
- ✅ Manual test: open MiniPlayer, play a track, open Playback
  menu → all items are enabled
- ✅ Manual test: Play/Pause menu label reflects live state in
  MiniPlayer mode (shows "Pause" when playing, "Play" when paused)
- ✅ Manual test: red close button on MiniPlayer returns user to
  the main window
- ✅ Manual test: switching back to main window preserves menu
  behaviour (no regression in main window)
- ✅ Manual test: cold launch without MiniPlayer → main window
  menu still works as before

### Commit message

```
fix(slice 9-h): make MiniPlayer menu bar functional and remove expand button

- Root cause 1: the MiniPlayer Window scene used .windowStyle(.plain),
  which makes its NSWindow return NO from canBecomeKeyWindow. With
  the main window ordered out during MiniPlayer activation, no
  window is key, the SwiftUI focus system has no active view chain,
  and HarmoniaPlayerCommands reads nil for @FocusedObject. All
  Playback menu items render disabled.
- Root cause 2: Slice 8-B attempted to expose playbackState via
  .focusedValue(\.playbackState, ...) inside MiniPlayerView.body,
  but .focusedValue is view-scope and requires an inner focused
  view. MiniPlayer contains only buttons and sliders, so the value
  never propagates; the Play/Pause label stays wrong even once
  focus works.
- Change HarmoniaPlayerApp MiniPlayer scene to
  .windowStyle(.hiddenTitleBar) so canBecomeKeyWindow is true; the
  minimal-chrome visual is preserved.
- Add .focusedSceneObject(appState) and
  .focusedSceneValue(\.playbackState, ...) to MiniPlayerView.body
  so both modifiers are scene-scope and propagate once the window
  can become key.
- Remove the expand button from playlistPickerRow. Its
  close-and-return behaviour is fully covered by the window close
  button (WindowCloseObserver already brings the main window to
  front). Add a mirrored 30pt Color.clear balance spacer on the
  left so the playlist menu stays centred.
- Remove the now-unused "mini_player_expand" key from en, zh-Hant,
  and ja Localizable.strings.
```

---

## Slice 9-I: Fix Xcode Warnings (Cosmetic) ✅

### Goal
Fix the "Switch condition evaluates to a constant" warnings in
`PlaybackErrorTests` and `PlaybackStateTests`.

### Scope
- Review the switch statements that trigger the warning
- Refactor to eliminate the constant-condition pattern while preserving
  test coverage

### Files

- `HarmoniaPlayerTests/SharedTests/PlaybackErrorTests.swift` (modify)
- `HarmoniaPlayerTests/SharedTests/PlaybackStateTests.swift` (modify)

### Done criteria

- ✅ No Xcode warnings from these two test files
- ✅ Test coverage unchanged
- ✅ All tests green

### Commit message

```
fix(slice 9-i): resolve "Switch condition evaluates to a constant" warnings

- Refactor switch statements in PlaybackErrorTests and PlaybackStateTests
```

---

## Slice 9-J: Lyrics Display (USLT + sidecar .lrc) ⬜

### Goal

Display embedded USLT lyrics or sidecar `.lrc` file content as **full text**
(no synchronized scrolling, timestamps fully stripped), with user-selectable
encoding and per-track source memory. All tiers.

### Prerequisite Investigation

API and reference-implementation findings that informed this slice's design.

**1. AVFoundation USLT reading**

- `AVMetadataKey.id3MetadataKeyUnsynchronizedLyric` reads the standard ID3
  USLT frame.
- ID3v2 USLT frame structure: text encoding + 3-byte language code (ISO 639-2)
  + content descriptor + lyrics text.
- ID3v2.4 permits multiple USLT frames per file, distinguished by language
  code and content descriptor.
- AVFoundation exposes per-item sub-fields via `AVMetadataItem.extraAttributes`
  — same mechanism HarmoniaCore reader already uses for TXXX (see
  `AVMetadataTagReaderAdapter.swift` L472–475).

**2. AVFoundation USLT writing**

- No official Apple example or documentation for `AVMutableMetadataItem`
  writing USLT specifically.
- Third-party Swift libraries (ID3TagEditor) implement direct ID3 USLT write;
  AVFoundation write support is uncertain.
- 9-J does not write USLT. v0.2 Tag Editor lyrics editing may require TagLib
  adapter.

**3. Sidecar `.lrc` filename conventions (foobar2000 OpenLyrics behaviour)**

- Default save filename format: `[%artist% - ][%title%]` (i.e.
  `Artist - Title.lrc`), not file basename.
- Search extensions: both `.lrc` and `.txt`.
- These conventions are popular but not industry-standard. 9-J targets
  file-basename convention only (decision B-1; v0.15 backlog).

**4. ID3 lyrics frame in foobar2000 (writes)**

- foobar2000 OpenLyrics writes ID3 lyrics as TXXX frames named `LYRICS` /
  `SYNCEDLYRICS` / `UNSYNCEDLYRICS` / `UNSYNCED LYRICS` — not the standard
  `USLT` frame.
- Reading these requires TXXX with description match, not USLT.
- 9-J reads only standard USLT (decision A-1; v0.15 backlog for foobar2000
  compatibility).

**5. Multi-language USLT data model**

- A single MP3 may contain English + Chinese + Japanese USLT, each as a
  separate frame.
- Single-string `lyrics: String?` model collapses these to whichever
  AVFoundation returns first (effectively random selection).
- 9-J adopts array-of-variants model (decision C-2):
  `lyrics: [LyricsLanguageVariant]?`.

**6. Swift `String.Encoding` API path for GB18030 / Big5**

- Swift `String.Encoding` exposes `.utf8`, `.utf16`, `.shiftJIS`,
  `.isoLatin1` as public constants.
- **GB18030 and Big5 are NOT public Swift constants.** Implementation
  must construct them via
  `CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.<name>.rawValue))`
  using `CFStringEncodings.GB_18030_2000` and `CFStringEncodings.big5`.
- `LyricsService` wraps these as `static let gb18030` / `static let big5`
  helpers (one-time conversion).
- Verified via CotEditor (macOS reference encoder/decoder
  implementation), which uses the same approach.

**Sources:**

- ID3v2 spec: https://id3.org/id3v2.3.0
- foobar2000 OpenLyrics docs:
  https://wiki.hydrogenaudio.org/index.php?title=Foobar2000:Components/OpenLyrics_(foo_openlyrics)
- foo_openlyrics Issue #115 (write log evidence):
  https://github.com/jacquesh/foo_openlyrics/issues/115
- Apple AVMetadataKey:
  https://developer.apple.com/documentation/avfoundation/avmetadatakey/id3metadatakeyunsynchronizedlyric
- Apple CFStringEncoding / CFStringConvertEncodingToNSStringEncoding:
  https://developer.apple.com/documentation/corefoundation/cfstringencoding
- CotEditor source (encoding constants prior art):
  https://github.com/coteditor/CotEditor

### Scope

- HarmoniaCore: `TagBundle.lyrics: [LyricsLanguageVariant]?` added;
  `AVMetadataTagReaderAdapter` reads ALL USLT frames (one variant per frame,
  language code extracted from `extraAttributes`).
- HarmoniaPlayer Integration: `HarmoniaTagReaderAdapter` maps
  `TagBundle.lyrics` to `Track.lyrics`.
- HarmoniaPlayer Application:
  - `Track.lyrics: [LyricsLanguageVariant]?` added.
  - `LyricsLanguageVariant` model (new): `languageCode: String?` (ISO 639-2,
    nil when undeclared), `text: String` (raw, not yet stripped).
  - `LyricsService` protocol: resolves lyrics from embedded USLT or
    sidecar `.lrc` file, with variant filename search, language selection,
    and encoding handling.
  - `LyricsPreferenceStore`: per-track source + language + encoding
    preference, UserDefaults-backed.
  - `AppState`: `@Published var showLyrics: Bool`,
    `@Published var lyricsResolution: LyricsResolution?`, plus toggle,
    language setter, and preference setters.
- HarmoniaPlayer UI:
  - `PlayerView`: lyrics toggle button, hidden when
    `lyricsResolution == nil`.
  - `LyricsPanel`: Source picker + Language picker (visible when
    source=.embedded AND availableLanguages.count > 1) + Encoding picker
    (visible when source=.lrc) + scrollable text area.

### Source priority and resolution order

**Default source priority when preference not set:**
1. sidecar `.lrc` (any variant — see sidecar search order below)
2. embedded USLT (if multiple language variants present, prefer system locale match; otherwise first variant in file order)
3. no lyrics → button hidden

**Sidecar `.lrc` search order:**
1. `<same-dir>/<filename>.lrc`  (e.g. `song.lrc` for `song.mp3`)
2. `<same-dir>/<filename-with-ext>.lrc`  (e.g. `song.mp3.lrc`)
3. `<same-dir>/Lyrics/<filename>.lrc`
4. `<same-dir>/lyrics/<filename>.lrc`

First match wins. No recursive search beyond these fixed paths.

**User override:** Source picker in `LyricsPanel` lets user switch between
Embedded and LRC file (auto) when both available. Choice is persisted.

### Custom source selection (NOT in 9-J)

Custom file selection (`LRC file (custom)` and
`Embedded from another file (custom)`) is **deferred to v0.15**,
implemented together as a single sub-slice using `NSOpenPanel`. The
`LyricsPreference` schema in 9-J reserves a `customPath: String?` field
for forward compatibility but never writes to it.

### Encoding strategy

- **Auto detection order:** UTF-8 → UTF-16 (BOM) → GB18030 → Big5 →
  Shift-JIS → ISO-8859-1.
- **Swift `String.Encoding` API path:** `.utf8`, `.utf16`, `.shiftJIS`,
  and `.isoLatin1` are public Swift constants and used directly.
  **`.gb18030` and `.big5` are not exposed as public Swift constants**
  and must be constructed via `CFStringConvertEncodingToNSStringEncoding`:
  ```swift
  let gb18030 = String.Encoding(rawValue:
      CFStringConvertEncodingToNSStringEncoding(
          CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
  let big5 = String.Encoding(rawValue:
      CFStringConvertEncodingToNSStringEncoding(
          CFStringEncoding(CFStringEncodings.big5.rawValue)))
  ```
  `LyricsService` exposes these as static helpers
  (`LyricsService.gb18030` / `LyricsService.big5`) to avoid repeated
  conversion. CotEditor (macOS reference encoder/decoder implementation)
  uses the same approach.
- **Manual selection:** full `String.availableStringEncodings` list,
  sorted by `String.localizedName(of:)`, presented alphabetically.
- Sidecar `.lrc` and embedded USLT each track their own encoding
  preference per file. Embedded USLT's encoding is normally declared in
  the ID3 frame header, but user may override.

### Timestamp handling (.lrc files)

- **All `[mm:ss.xx]` timestamps are stripped from display text.**
- **All `[tag:value]` metadata headers** (e.g. `[ti:title]`,
  `[ar:artist]`, `[al:album]`, `[by:lyricist]`, `[offset:]`) **are also
  stripped.**
- Only the plain text after timestamps is shown.
- Blank lines in the original file are preserved (for stanza breaks).
- Timestamp parsing logic is retained internally for future v0.15
  synchronized scrolling upgrade, but not surfaced in 9-J UI.

### Persistence

- **UserDefaults key:** `hp.lyrics.prefs.<absolute-file-path>[#track=<n>]`
  - Non-CUE tracks: no `#track=` suffix
    (e.g. `hp.lyrics.prefs./Music/song.mp3`)
  - CUE virtual tracks: `#track=<n>` suffix for each virtual track
    (e.g. `hp.lyrics.prefs./Music/Album.flac#track=3`)
  - Key generation function handles both cases; CUE support is latent
    in 9-J (Track model's `cueTrackNumber` is added in Phase 3a) and
    activates when CUE ships in v0.15.
- **Value (Codable):**

  ```swift
  struct LyricsPreference: Codable {
      var source: LyricsSource     // .embedded | .lrc
      var encoding: String         // IANA charset name, "auto" = detect
      var languageCode: String?    // ISO 639-2; applies when source = .embedded; nil = auto (locale match)
      var customPath: String?      // reserved for v0.15, always nil in 9-J
  }
  ```

- **Scope:** preferences are keyed by file path (and CUE track number
  when applicable), shared across all playlists. Same file in playlist
  A and playlist B uses identical preference.

### Button visibility — resolution pipeline (β strategy)

To avoid button flicker on track change:

1. **On track load** (not playback start): synchronously check USLT
   availability (already in `Track.lyrics` from tag read) AND check
   sidecar `.lrc` existence (`FileManager.fileExists` across the 4
   variant paths).
2. Set `lyricsResolution.hasAny: Bool` based on these two cheap checks.
3. Button visibility binds to `hasAny`.
4. **On button tap or panel open**: lazily read actual content (USLT
   text from Track, or `.lrc` file via `String(contentsOf:encoding:)`)
   with encoding detection. This is the slow path (ms-range for `.lrc`
   reads).

**Future v0.15 γ upgrade note:** full preload — read next track's
lyrics content (not just existence) when current track nears end.
Requires `PlaybackService.preloadNext()` API in HarmoniaCore (Phase 3a
deliverable) and HarmoniaPlayer-side preload orchestration. 9-J
deliberately stops at β to keep this slice focused.

### Files

**HarmoniaCore**

- `apple-swift/Sources/HarmoniaCore/Models/TagBundle.swift` (modify)
  — add `lyrics: [LyricsLanguageVariant]?`
- `apple-swift/Sources/HarmoniaCore/Models/LyricsLanguageVariant.swift`
  (new) — same shape as the HarmoniaPlayer-side struct
- `apple-swift/Sources/HarmoniaCore/Adapters/AVMetadataTagReaderAdapter.swift`
  (modify) — read ALL USLT frames
  (key `AVMetadataKey.id3MetadataKeyUnsynchronizedLyric`); for each item,
  extract language code from `extraAttributes` and produce one
  `LyricsLanguageVariant`; collect into `TagBundle.lyrics`

**HarmoniaPlayer — Integration Layer**

- `Shared/Services/HarmoniaTagReaderAdapter.swift` (modify)
  — map `TagBundle.lyrics` to `Track.lyrics`

**HarmoniaPlayer — Application Layer**

- `Shared/Models/Track.swift` (modify) — add `lyrics: [LyricsLanguageVariant]?`
  (default nil)
- `Shared/Models/LyricsSource.swift` (new)

  ```swift
  enum LyricsSource: String, Codable {
      case embedded
      case lrc
  }
  ```

- `Shared/Models/LyricsLanguageVariant.swift` (new)

  ```swift
  struct LyricsLanguageVariant: Codable, Equatable {
      let languageCode: String?  // ISO 639-2; nil if undeclared
      let text: String           // raw text, not yet stripped
  }
  ```

- `Shared/Models/LyricsPreference.swift` (new) — Codable struct
  (see above)
- `Shared/Models/LyricsResolution.swift` (new)

  ```swift
  struct LyricsResolution {
      let hasAny: Bool                    // fast check result
      let currentSource: LyricsSource?
      let availableSources: Set<LyricsSource>
      let availableLanguages: [String?]   // language codes available for current source
      let currentLanguage: String?        // selected language; nil if not applicable
      let content: String?                // resolved content for current source+language; nil until lazy-loaded
  }
  ```

- `Shared/Services/LyricsService.swift` (new) — protocol + default impl
  - `resolveAvailability(for: Track) -> LyricsResolution`
    (fast, sync)
  - `resolveContent(for: Track, source: LyricsSource, languageCode: String?, encoding: String?) throws -> String`
    (slow, async)
  - `stripLRCTimestamps(_ raw: String) -> String`  (pure function)
  - `detectEncoding(of: Data) -> String.Encoding`
    (auto-detect fallback chain)
- `Shared/Services/LyricsPreferenceStore.swift` (new)
  - `key(for: Track) -> String`  (handles `#track=` for CUE)
  - `load(for: Track) -> LyricsPreference?`
  - `save(_ pref: LyricsPreference, for: Track)`
- `Shared/Models/AppState.swift` (modify)
  - inject `LyricsService` + `LyricsPreferenceStore`
  - `@Published var showLyrics: Bool`
  - `@Published var lyricsResolution: LyricsResolution?`
  - `toggleLyrics()`
  - `setLyricsSource(_: LyricsSource)`
  - `setLyricsLanguage(_ languageCode: String?)`
  - `setLyricsEncoding(_: String)`
  - call `lyricsService.resolveAvailability(for:)` on currentTrack
    change
- `Shared/Services/CoreServiceProviding.swift` (modify)
  — add `makeLyricsService()` factory
- `Shared/Services/CoreFactory.swift` (modify) — wire `LyricsService`
- `Shared/Services/HarmoniaCoreProvider.swift` (modify)
  — construct default `LyricsService`

**HarmoniaPlayer — UI**

- `Shared/Views/LyricsPanel.swift` (new)
  - Source picker (SegmentedControl or Menu, only shows available
    sources)
  - Language picker (visible when source=.embedded AND
    availableLanguages.count > 1)
  - Encoding picker (Auto + full localized list from
    `String.availableStringEncodings`; visible when source=.lrc)
  - `ScrollView { Text(content) }` for content
- `Shared/Views/PlayerView.swift` (modify)
  - lyrics toggle button, conditional on
    `lyricsResolution?.hasAny == true`
  - embed `LyricsPanel` when `showLyrics`

**Tests** (`HarmoniaPlayerTests/SharedTests/`)

- `LyricsServiceTests.swift` (new)
- `LyricsPreferenceStoreTests.swift` (new)
- `LRCStripTests.swift` (new)
- `EncodingDetectionTests.swift` (new)
- `AppStateLyricsTests.swift` (new)

**Localisation** (en / zh-Hant / ja)

- `lyrics_toggle_button_label`
- `lyrics_source_picker_label`
- `lyrics_source_embedded`
- `lyrics_source_lrc`
- `lyrics_language_picker_label`
- `lyrics_encoding_picker_label`
- `lyrics_encoding_auto`
- `lyrics_parse_failed`

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testTrack_DefaultLyrics_IsNil` | new `Track(url:)` | read `lyrics` | `nil` |
| `testUSLT_MappedFromTagBundle` | `TagBundle(lyrics: [LyricsLanguageVariant(languageCode: "eng", text: "hello")])` | `HarmoniaTagReaderAdapter.readMetadata` | `Track.lyrics?.first?.text == "hello"` |
| `testUSLT_MultipleFramesProduceMultipleVariants` | MP3 with 2 USLT frames (eng + chi) | reader | `Track.lyrics` returns 2 variants with correct language codes |
| `testUSLT_SingleFrameWithoutLanguageProducesOneVariant` | MP3 with 1 USLT frame, no language declared | reader | 1 variant, `languageCode == nil` |
| `testResolveAvailability_EmbeddedMultiLang_ListsAllLanguages` | Track with 2 USLT variants | `resolveAvailability` | `availableLanguages` contains both codes |
| `testResolveAvailability_PicksSystemLocaleFirst` | Track with eng+chi variants, system locale = zh | `resolveAvailability` | `currentLanguage == "chi"` |
| `testResolveAvailability_FallsBackToFirstWhenNoLocaleMatch` | Track with eng+chi variants, system locale = ja | `resolveAvailability` | `currentLanguage` == first variant's code |
| `testAppState_SetLanguage_UpdatesContent` | embedded source, 2 language variants loaded | `setLyricsLanguage(other)` | `content` updates to other variant text |
| `testPreferenceStore_PersistsLanguageCode` | save preference with `languageCode = "chi"` | reload store | loaded preference `languageCode == "chi"` |
| `testLRCStrip_RemovesTimestamps` | `"[00:12.00]line1\n[00:15.50]line2"` | `stripLRCTimestamps` | `"line1\nline2"` |
| `testLRCStrip_RemovesMetadataTags` | `"[ti:title]\n[ar:artist]\n[00:12.00]line"` | `stripLRCTimestamps` | `"line"` (blank lines preserved as-is) |
| `testLRCStrip_KeepsBlankLines` | `"[00:12]a\n\n[00:15]b"` | `stripLRCTimestamps` | `"a\n\nb"` |
| `testEncodingDetection_UTF8` | valid UTF-8 `.lrc` bytes | `detectEncoding` | `.utf8` |
| `testEncodingDetection_GB18030Fallback` | GB18030 bytes (fails UTF-8) | `detectEncoding` | `.gb18030` |
| `testEncodingDetection_Big5Fallback` | Big5 bytes | `detectEncoding` | `.big5` |
| `testEncodingDetection_ShiftJISFallback` | Shift-JIS bytes | `detectEncoding` | `.shiftJIS` |
| `testSidecarSearch_SameFilename` | `song.mp3` + `song.lrc` | `LyricsService.resolveAvailability` | finds `song.lrc` |
| `testSidecarSearch_FilenameWithExt` | `song.mp3` + `song.mp3.lrc` (no `song.lrc`) | `resolveAvailability` | finds `song.mp3.lrc` |
| `testSidecarSearch_LyricsSubdir` | `song.mp3` + `Lyrics/song.lrc` | `resolveAvailability` | finds subdir file |
| `testSidecarSearch_PrefersDirectFirst` | both `song.lrc` + `song.mp3.lrc` exist | `resolveAvailability` | returns `song.lrc` |
| `testResolveAvailability_PrefersLRCWhenNoPref` | USLT + `.lrc` both present, no pref | `resolveAvailability` | `.currentSource == .lrc` |
| `testResolveAvailability_FallsBackToEmbeddedNoLRC` | USLT only | `resolveAvailability` | `.currentSource == .embedded` |
| `testResolveAvailability_HasAnyFalseWhenNothing` | no USLT, no `.lrc` | `resolveAvailability` | `.hasAny == false` |
| `testResolveContent_EmbeddedReturnsUSLT` | Track with USLT | `resolveContent(.embedded)` | returns USLT string |
| `testResolveContent_LRCStripsTimestamps` | `.lrc` with timestamps | `resolveContent(.lrc)` | timestamps removed |
| `testResolveContent_UsesPreferredEncoding` | `.lrc` in Big5, pref = Big5 | `resolveContent(.lrc, "big5")` | decoded correctly |
| `testPreferenceStore_NonCueKey` | Track without `cueTrackNumber` | `key(for:)` | `"hp.lyrics.prefs./path/song.mp3"` |
| `testPreferenceStore_CueKey` | Track with `cueTrackNumber = 3` | `key(for:)` | `"hp.lyrics.prefs./path/Album.flac#track=3"` |
| `testPreferenceStore_PersistsAcrossSessions` | save, recreate store | load | equal values |
| `testPreferenceStore_SharedAcrossPlaylists` | same path, 2 playlists | save in A, load in B | equal values |
| `testAppState_ToggleLyrics_FlipsVisibility` | `showLyrics == false` | `toggleLyrics()` | `true` |
| `testAppState_OnTrackChange_UpdatesResolution` | change currentTrack | publisher fires | `lyricsResolution` reflects new track |

### Done criteria

- ⬜ `PlayerView` shows lyrics toggle button only when
  `lyricsResolution?.hasAny == true`
- ⬜ Tapping button toggles `LyricsPanel` visibility
- ⬜ Panel shows full-text USLT content for MP3 with embedded lyrics
- ⬜ Panel shows stripped `.lrc` content (no `[mm:ss.xx]`, no
  `[tag:value]` metadata) for track with sidecar file
- ⬜ Sidecar search finds all 4 variant paths (`song.lrc`,
  `song.mp3.lrc`, `Lyrics/song.lrc`, `lyrics/song.lrc`)
- ⬜ Source picker switches between Embedded and LRC when both available
- ⬜ Encoding Auto correctly decodes UTF-8 / GB18030 / Big5 / Shift-JIS
- ⬜ Encoding manual selection overrides Auto and persists
- ⬜ Preferences persist across app launches
- ⬜ Same file across playlists shares preference
- ⬜ Preference key format: non-CUE uses path only;
  CUE virtual tracks use `#track=<n>` suffix
- ⬜ Track with multi-language USLT (e.g. eng + chi + jpn) shows all in
  language picker
- ⬜ Language picker visible only when source=.embedded AND
  availableLanguages.count > 1
- ⬜ Default language selection prefers system locale, falls back to first
  available variant
- ⬜ Selected language persists across launches per file
- ⬜ Button visibility check is sync/fast (no flicker on track change)
- ⬜ All Slice 1–9 previous tests still green
- ⬜ All new tests green

### Non-goals (explicit)

- **No SYLT reading.** Deferred to v0.15.
- **No synchronized scrolling / line highlighting.** Deferred to v0.15.
- **No custom file selection** (`LRC file (custom)`,
  `Embedded from another file (custom)`). Deferred to v0.15.
- **No USLT content splitting.** A single USLT blob containing lyrics
  for multiple songs is displayed as-is; no heuristic splitting (format
  has no standard for segmentation, user must pre-split into separate
  files).
- **No lyrics editing.** Deferred to v0.2 Tag Editor.
- **No TXXX-frame lyrics reading** (frames `LYRICS` / `UNSYNCEDLYRICS` /
  `UNSYNCED LYRICS` / `SYNCEDLYRICS`, written by foobar2000). Deferred
  to v0.15.
- **No alternative sidecar filename formats** (e.g. `Artist - Title.lrc`,
  `.txt` extension). Deferred to v0.15.
- **No language code extraction from .lrc files.** LRC `[la:xxx]` metadata
  header is stripped, not parsed. Deferred to v0.15.
- **No full content preload on track change** (β strategy only; γ full
  preload deferred to v0.15 after Phase 3a adds HarmoniaCore preload
  API).

### Related future work

- **Phase 3a (HarmoniaCore refactor):** add
  `PlaybackService.preloadNext()` API serving both v0.2 gapless
  playback and v0.15 lyrics γ-strategy preload.
- **v0.15 lyrics expansion (planned):**
  - **foobar2000 TXXX compatibility**: read TXXX frames `LYRICS`,
    `UNSYNCEDLYRICS`, `UNSYNCED LYRICS`, `SYNCEDLYRICS`. These merge into
    the existing `[LyricsLanguageVariant]` array with `languageCode = nil`
    (TXXX has no standard language slot). 9-J's reader extension point: a
    single `readEmbeddedLyrics(items:) -> [LyricsLanguageVariant]`
    function — v0.15 adds TXXX branches without touching `Track`,
    `LyricsService`, `AppState`, or UI.
  - **Alternative sidecar filenames**: add `<artist> - <title>.lrc` and
    `.txt` extension variants. 9-J's `LyricsService` extension point:
    keep sidecar search paths as a
    `private let sidecarSearchPaths: [...]` array of path-builder
    closures. v0.15 appends entries; no callers change.
  - **LRC language tag**: parse `[la:xxx]` metadata header in `.lrc`,
    populate `LyricsLanguageVariant.languageCode` for sidecar source.
- **v0.15:** SYLT reading, synchronized line scrolling, custom file
  selection (both LRC custom and Embedded-from-another-file custom),
  γ-strategy full preload.
- **v0.2:** gapless playback built on Phase 3a preload API, lyrics
  editing in Tag Editor.

---

## Slice 9-K: Equalizer (10-band) ⬜

### Goal

Provide a 10-band parametric equalizer with built-in presets and custom
preset support, accessible via Window menu as a separate EQ window. All
tiers (Free).

### Scope

**HarmoniaCore:**
- New `EQPort` protocol (audio chain DSP node abstraction).
- New `AVAudioUnitEQAdapter` implementing `EQPort` using
  `AVAudioUnitEQ` (10 bands, parametric type, fixed Q = 0.7071).
- `DefaultPlaybackService` inserts EQ node into the audio chain
  between decoder and audio output.
- `PlaybackService` exposes EQ control surface
  (`setEQEnabled(_:)`, `setEQPreamp(_:)`, `setEQBandGains(_:)`).

**HarmoniaPlayer Application:**
- New `EQService` protocol (Application Layer abstraction over
  HarmoniaCore EQ).
- `AppState`: EQ state (`eqEnabled`, `eqBands[10]`, `preamp`,
  `currentPresetName`, `customPresets[]`).
- EQ is **global state** (v0.1 scope — not per-track, not
  per-playlist).
- EQ + ReplayGain coexistence: preamp and ReplayGain track gain are
  combined additively before final output gain.

**HarmoniaPlayer Integration:**
- New `HarmoniaEQAdapter` bridging Core's `EQPort`-controlling API to
  `EQService` protocol.
- `CoreServiceProviding` adds `makeEQService()`.

**HarmoniaPlayer UI:**
- New `EQView`: 10 vertical sliders + preamp slider + preset picker +
  enable toggle + "Save as Preset…" button + "Delete Preset" button.
- Window menu: new "Equalizer" entry (⌘⌥E shortcut, matching macOS
  Music.app convention).
- New EQ Window via `WindowGroup` (separate window, like FileInfoView
  pattern).

### Frequency bands (10-band ISO standard)

```
Band  Frequency  Default Gain
 1    32 Hz        0 dB
 2    64 Hz        0 dB
 3    125 Hz       0 dB
 4    250 Hz       0 dB
 5    500 Hz       0 dB
 6    1 kHz        0 dB
 7    2 kHz        0 dB
 8    4 kHz        0 dB
 9    8 kHz        0 dB
10    16 kHz       0 dB
```

- Gain range per band: −12 dB to +12 dB (clamped in adapter).
- Preamp range: −12 dB to +12 dB (clamped in adapter).
- Q factor: fixed 0.7071 (Butterworth), not user-adjustable in 9-K.

### Built-in presets

Names presented in localised form via key lookup; underlying band
values are fixed numerical arrays. User cannot edit built-in presets
— selecting a built-in preset and modifying any band switches state
to "Unsaved/Custom".

| Preset | Description |
|---|---|
| Flat | All bands 0 dB |
| Rock | Boost low + high, scoop mids |
| Pop | Boost mids and high |
| Jazz | Gentle boost low + high, flat mids |
| Classical | Slight boost low, flat mids/high |
| Vocal | Boost mid (1k–4k), reduce extremes |
| Bass Boost | Boost low (32–250 Hz) |
| Treble Boost | Boost high (4k–16k Hz) |

Exact dB values defined as Swift constants in
`Shared/Models/EQPresets.swift`.

### Custom presets

- User can save current band/preamp configuration as a custom preset
  with a user-given name.
- User can delete custom presets (built-in presets cannot be deleted).
- Custom presets persisted in UserDefaults as Codable array.
- No naming collision with built-in presets (validation rejects on
  save).

### EQ + ReplayGain interaction

Both EQ preamp and ReplayGain produce a master gain adjustment in dB.
They combine **additively** before final volume application:

```
finalGain_dB = volume_dB + replayGain_trackGain_dB + eqPreamp_dB
```

This is documented behaviour. Tests verify the additive combination.

### Persistence (with schema versioning)

Forward-compatible schema with explicit version field. 9-K introduces
schema version **1**. Future slices (e.g. v0.15 per-track EQ, v0.15/v0.2
user-adjustable Q) will bump version and migrate via `EQSchemaMigrator`.

**UserDefaults keys:**

```
hp.eq.schemaVersion: Int           // 9-K = 1
hp.eq.enabled: Bool
hp.eq.preamp: Float                // dB
hp.eq.bands: Data                  // Codable [EQBandState], 10 elements
hp.eq.currentPresetName: String?   // nil = "Unsaved/Custom"
hp.eq.customPresets: Data          // Codable [EQPreset]
```

**Codable types:**

```swift
struct EQBandState: Codable {
    var gain: Float          // -12...+12 dB
    var q: Float             // reserved for future; 9-K always 0.7071
}

struct EQPreset: Codable {
    var name: String
    var bands: [EQBandState]
    var preamp: Float
    var isBuiltin: Bool
}
```

**Migration strategy:**

On load, `EQPersistenceStore` reads `hp.eq.schemaVersion`:
- Missing / nil → fresh install, no migration needed, initialise
  with defaults and write version 1.
- 1 → current, load directly.
- > 1 (future) → delegate to `EQSchemaMigrator.migrate(from:to:)`.

9-K ships `EQSchemaMigrator` skeleton but contains no migration logic
(only version 1 exists). Future slices will add migration steps.

### Files

**HarmoniaCore**

- `apple-swift/Sources/HarmoniaCore/Ports/EQPort.swift` (new)

  ```swift
  public protocol EQPort {
      var isEnabled: Bool { get set }
      var preamp: Float { get set }       // dB, -12...+12
      var bandGains: [Float] { get set }  // 10 elements, dB, -12...+12
      func attach(to engine: AVAudioEngine, after: AVAudioNode) throws
  }
  ```

- `apple-swift/Sources/HarmoniaCore/Adapters/AVAudioUnitEQAdapter.swift`
  (new) — wraps `AVAudioUnitEQ(numberOfBands: 10)`, sets parametric
  type per band with ISO frequencies, Q = 0.7071. Clamps gain and
  preamp to ±12 dB.
- `apple-swift/Sources/HarmoniaCore/Services/PlaybackService.swift`
  (modify) — add control surface:
  `setEQEnabled(_: Bool)`,
  `setEQPreamp(_: Float)`,
  `setEQBandGains(_: [Float])`.
- `apple-swift/Sources/HarmoniaCore/Services/DefaultPlaybackService.swift`
  (modify) — inject `EQPort` via constructor; insert EQ node into
  audio chain in `load(url:)`.

**HarmoniaPlayer — Integration Layer**

- `Shared/Services/HarmoniaEQAdapter.swift` (new) — bridges Core
  PlaybackService EQ control surface to `EQService` protocol.

**HarmoniaPlayer — Application Layer**

- `Shared/Models/EQBand.swift` (new) — frequency + default gain.
- `Shared/Models/EQBandState.swift` (new) — Codable gain + q.
- `Shared/Models/EQPreset.swift` (new) — Codable preset record.
- `Shared/Models/EQPresets.swift` (new) — static built-in preset
  array.
- `Shared/Services/EQService.swift` (new) — protocol:
  `setEnabled(_:)`, `setPreamp(_:)`, `setBandGains(_:)`.
- `Shared/Services/EQPersistenceStore.swift` (new) — UserDefaults
  load/save for EQ state and custom presets, schema version
  checking.
- `Shared/Services/EQSchemaMigrator.swift` (new) — skeleton for
  future migration logic; 9-K contains only version 1 identity.
- `Shared/Models/AppState.swift` (modify)
  - inject `EQService` + `EQPersistenceStore`
  - `@Published var eqEnabled: Bool`
  - `@Published var eqBands: [Float]` (10 values)
  - `@Published var preamp: Float`
  - `@Published var currentPresetName: String?`
  - `@Published var customPresets: [EQPreset]`
  - `setEQEnabled(_:)`, `setEQBand(index:gain:)`, `setEQPreamp(_:)`,
    `selectPreset(_:)`, `saveAsCustomPreset(name:)`,
    `deleteCustomPreset(_:)`
- `Shared/Services/CoreServiceProviding.swift` (modify) — add
  `makeEQService()` factory.
- `Shared/Services/CoreFactory.swift` (modify) — wire `EQService`.
- `Shared/Services/HarmoniaCoreProvider.swift` (modify) — construct
  default EQ service stack.

**HarmoniaPlayer — UI**

- `Shared/Views/EQView.swift` (new)
  - 10 vertical sliders (one per band, label = frequency)
  - Preamp vertical slider (left of bands)
  - Enable toggle (top)
  - Preset picker (top, dropdown)
  - "Save as Preset…" button (alert with name input)
  - "Delete Preset" button (only enabled for custom presets)
- `Shared/Views/EQWindow.swift` (new) — WindowGroup wrapper,
  following FileInfoView pattern.
- `macOS/HarmoniaPlayerApp.swift` (modify) — register EQ
  WindowGroup + add Window menu entry "Equalizer" (⌘⌥E).
- `Shared/Views/HarmoniaPlayerCommands.swift` (modify) — add
  `.focusedSceneValue` for "Equalizer" command.

**Tests — HarmoniaPlayer** (`HarmoniaPlayerTests/SharedTests/`)

- `EQServiceTests.swift` (new)
- `EQPersistenceStoreTests.swift` (new)
- `EQPresetsTests.swift` (new)
- `EQSchemaMigratorTests.swift` (new)
- `AppStateEQTests.swift` (new)
- `EQReplayGainInteractionTests.swift` (new)

**Tests — HarmoniaCore** (`Tests/HarmoniaCoreTests/`)

- `AVAudioUnitEQAdapterTests.swift` (new) — band attachment + gain
  setting + isEnabled toggle + clamping.

**Localisation** (en / zh-Hant / ja)

- `eq_window_title`
- `eq_enabled_toggle`
- `eq_preamp_label`
- `eq_band_label_32hz` … `eq_band_label_16khz` (10 keys)
- `eq_preset_picker_label`
- `eq_preset_flat`, `eq_preset_rock`, `eq_preset_pop`,
  `eq_preset_jazz`, `eq_preset_classical`, `eq_preset_vocal`,
  `eq_preset_bass_boost`, `eq_preset_treble_boost`
- `eq_preset_save_button`
- `eq_preset_save_dialog_title`
- `eq_preset_save_dialog_placeholder`
- `eq_preset_delete_button`
- `eq_preset_name_collision_alert`
- `menu_equalizer`

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testEQPort_DefaultIsDisabled` | new `AVAudioUnitEQAdapter` | read `isEnabled` | `false` |
| `testEQPort_DefaultBandsAreFlat` | new adapter | read `bandGains` | all 10 values == 0 |
| `testEQPort_SetBandGain_Updates` | adapter, set band[3] = 6 | read `bandGains[3]` | `6` |
| `testEQPort_SetPreamp_Updates` | adapter, set preamp = -3 | read `preamp` | `-3` |
| `testEQPort_GainClamping_LowBound` | set band[0] = -20 | read `bandGains[0]` | `-12` (clamped) |
| `testEQPort_GainClamping_HighBound` | set preamp = 20 | read `preamp` | `12` (clamped) |
| `testPlaybackService_LoadInsertsEQNode` | `load(url:)` | inspect audio chain | EQ node present between decoder and output |
| `testEQService_PassesThroughToPort` | `EQService.setEnabled(true)` | `EQPort` | `isEnabled == true` |
| `testEQPersistence_RoundTrip` | save state, recreate store | load | values match |
| `testEQPersistence_WritesSchemaVersion` | save any state | read `hp.eq.schemaVersion` | `1` |
| `testEQPersistence_FreshInstall_NoMigrationNeeded` | empty UserDefaults | load | returns defaults, writes version 1 |
| `testEQSchemaMigrator_Version1_IsIdentity` | state at version 1 | `migrate(from:1, to:1)` | unchanged |
| `testEQPresets_FlatBuiltinExists` | builtin presets array | find "Flat" | exists, all bands 0 |
| `testEQPresets_RockHasExpectedShape` | builtin "Rock" | inspect bands | low + high boosted, mid scooped (specific dB values) |
| `testAppState_SelectBuiltinPreset_AppliesGains` | AppState | `selectPreset("Rock")` | `eqBands` matches preset, `eqService.bandGains` matches |
| `testAppState_ModifyBand_MarksAsCustomState` | preset selected | modify band[2] | `currentPresetName == nil` |
| `testAppState_SaveCustomPreset_AppendsToList` | unsaved state | `saveAsCustomPreset("My EQ")` | `customPresets` contains it |
| `testAppState_SaveCustomPreset_RejectsBuiltinName` | unsaved state | `saveAsCustomPreset("Rock")` | throws / returns failure |
| `testAppState_DeleteCustomPreset_RemovesFromList` | custom preset exists | `deleteCustomPreset("My EQ")` | not in list |
| `testAppState_DeleteBuiltin_Rejected` | builtin "Rock" | `deleteCustomPreset("Rock")` | rejected, list unchanged |
| `testEQReplayGainInteraction_AdditiveCombination` | preamp = -3, RG = -2, volume = 0 | compute final gain | `-5` dB |
| `testEQDisabled_BypassesEntirely` | `eqEnabled = false`, all bands = 6 | playback | EQ node passes through (no gain change) |

### Done criteria

- ⬜ HarmoniaCore `EQPort` protocol defined
- ⬜ `AVAudioUnitEQAdapter` implements 10-band ISO parametric EQ with
  fixed Q = 0.7071
- ⬜ `DefaultPlaybackService` inserts EQ node into audio chain on load
- ⬜ `EQView` displays 10 vertical sliders + preamp + preset picker
- ⬜ Window menu has "Equalizer" entry with ⌘⌥E shortcut
- ⬜ Selecting built-in preset applies gains to audio in real-time
- ⬜ Modifying any band switches preset state to "Unsaved/Custom"
  (`currentPresetName == nil`)
- ⬜ "Save as Preset" creates new custom preset; rejects built-in
  name collision
- ⬜ Custom presets persist across app launches
- ⬜ Built-in presets cannot be deleted
- ⬜ Disabling EQ bypasses processing entirely (verified via test)
- ⬜ EQ preamp + ReplayGain combine additively
- ⬜ Gain values clamped to ±12 dB (band) and ±12 dB (preamp)
- ⬜ `hp.eq.schemaVersion` written as `1` on any save
- ⬜ Fresh install triggers no migration, initialises with defaults
- ⬜ All Slice 1–9 previous tests still green
- ⬜ All new tests green

### Non-goals (explicit)

- **No 31-band EQ.** 10-band is final scope.
- **No spectrum visualiser** (real-time FFT display). Future work.
- **No preset import/export to file.** UserDefaults only. Future work.
- **No per-track EQ memory.** EQ is global in v0.1. Future work
  (v0.15 / v0.2) will migrate schema.
- **No frequency response curve visualisation.** Slider-only UI.
- **No Q factor / bandwidth user control.** Fixed Butterworth
  Q = 0.7071 in 9-K. Future (v0.15 / v0.2) may expose Q control via
  schema version bump.
- **No automatic EQ via DRC** (Dynamic Range Control). Future work.

### Related future work

- **Phase 3a (HarmoniaCore refactor):** `EQPort` architecture may be
  generalised to a wider `AudioProcessorChain` supporting multiple
  insertable processors (EQ, fade, future HarmoniaAlarm needs).
- **v0.15:** consider per-track EQ memory (schema version 2,
  migration writes per-track keys `hp.eq.track.<path>...`); consider
  user-adjustable Q (schema version 3); preset import/export.
- **v0.2 (Pro):** spectrum visualiser, optional 31-band advanced EQ
  (Pro-only decision deferred), DRC.
- **HarmoniaAlarm:** alarm sound rarely needs EQ; `EQPort` being an
  optional processor in the audio chain means HarmoniaAlarm can skip
  instantiating it cleanly.

---

## Slice 9-L: macOS Now Playing Integration ⬜

### Goal

Integrate HarmoniaPlayer with macOS system media center so playback is
visible and controllable from Control Center, lock screen, Bluetooth
headphones (AirPods), keyboard media keys, and Siri. All tiers (Free).

### Scope

**HarmoniaPlayer Application Layer:**
- New `NowPlayingService` protocol (Application Layer abstraction).
- Methods: `updateCurrentTrack(_:)`, `updatePlaybackState(_:rate:)`,
  `updateElapsedTime(_:)`, `clear()`.
- Command callbacks registered via protocol: `onPlay`, `onPause`,
  `onTogglePlayPause`, `onNext`, `onPrevious`, `onStop`,
  `onSeek(_:)`.

**HarmoniaPlayer Integration Layer:**
- New `MPNowPlayingAdapter` (`import MediaPlayer`, macOS-only)
  implementing `NowPlayingService`.
- Pushes metadata to `MPNowPlayingInfoCenter.default().nowPlayingInfo`.
- Registers command handlers on `MPRemoteCommandCenter.shared()`.
- Loads artwork as `MPMediaItemArtwork` from track image data.

**HarmoniaPlayer AppState integration:**
- `AppState` injects `NowPlayingService`.
- Calls `updateCurrentTrack(_:)` on `currentTrack` change.
- Calls `updatePlaybackState(_:rate:)` on `playbackState` change.
- Calls `updateElapsedTime(_:)` throttled from existing 1 Hz
  `currentTime` polling loop.
- Calls `clear()` on stop and on `currentTrack = nil`.
- Wires command callbacks to existing AppState methods.

### Command map

| System command | AppState method |
|---|---|
| `MPRemoteCommand.playCommand` | `AppState.play()` |
| `MPRemoteCommand.pauseCommand` | `AppState.pause()` |
| `MPRemoteCommand.togglePlayPauseCommand` | `AppState.togglePlayPause()` |
| `MPRemoteCommand.nextTrackCommand` | `AppState.next()` |
| `MPRemoteCommand.previousTrackCommand` | `AppState.previous()` |
| `MPRemoteCommand.changePlaybackPositionCommand` | `AppState.seek(to:)` |
| `MPRemoteCommand.stopCommand` | `AppState.stop()` |

Commands explicitly NOT wired in 9-L: `skipForwardCommand`,
`skipBackwardCommand`, `ratingCommand`, `likeCommand`, `dislikeCommand`.

### Now Playing info fields

| Key | Source |
|---|---|
| `MPMediaItemPropertyTitle` | `track.title` |
| `MPMediaItemPropertyArtist` | `track.artist` |
| `MPMediaItemPropertyAlbumTitle` | `track.album` |
| `MPMediaItemPropertyPlaybackDuration` | `track.duration` |
| `MPMediaItemPropertyArtwork` | `track.artworkData` (when present) |
| `MPNowPlayingInfoPropertyElapsedPlaybackTime` | `currentTime` (1 Hz polling) |
| `MPNowPlayingInfoPropertyPlaybackRate` | `1.0` (playing) / `0.0` (paused/stopped) |
| `MPNowPlayingInfoPropertyMediaType` | `.audio` |

### Update cadence

- **On track change:** update title / artist / album / duration /
  artwork immediately (single batch).
- **On playback state change:** update `playbackRate` immediately.
- **Elapsed time:** piggyback on existing 1 Hz `currentTime` polling
  loop (no independent timer). Updates only the
  `elapsedPlaybackTime` key, not the full info dict.
- **On stop:** clear the entire info dict
  (`nowPlayingInfo = nil`).

**Pause behaviour:** pausing does **not** clear the widget. Widget
remains visible with paused state (rate = 0.0) so user can resume
playback from widget. Matches macOS Music.app behaviour.

### Artwork handling

- If `track.artworkData` is non-nil: decode to `NSImage`, wrap in
  `MPMediaItemArtwork` using the `boundsSize` + `requestHandler`
  pattern, push to info dict.
- If nil: omit the `MPMediaItemPropertyArtwork` key entirely
  (system shows generic audio icon).
- No artwork cache — pushed fresh on each `updateCurrentTrack`.
  Memory cost negligible for typical album artwork sizes.

### Lifecycle

- `NowPlayingService` constructed once at app launch via
  `CoreServiceProviding.makeNowPlayingService()`.
- Command handlers registered in adapter `init` and **never
  unregistered** during app lifetime. This ensures Bluetooth
  headphones / media keys / Siri work any time after app launch,
  regardless of current playback state.
- Adapter observes `NSApplicationWillTerminate` and clears
  `nowPlayingInfo` on quit to avoid stale widget info after app
  close.

### Testing strategy

**Adapter itself is NOT unit-tested.** `MPNowPlayingInfoCenter` and
`MPRemoteCommandCenter` are system singletons — any test touching them
would create cross-test state pollution. Adapter correctness is
verified via manual QA using the Done criteria checklist.

AppState wiring correctness IS unit-tested via `FakeNowPlayingService`.

This testing strategy is re-evaluated during Phase 3a HarmoniaCore
refactor (if `NowPlayingService` interface grows or system integration
changes warrant deeper automated testing).

### Files

**HarmoniaPlayer — Application Layer**

- `Shared/Services/NowPlayingService.swift` (new)

  ```swift
  protocol NowPlayingService: AnyObject {
      func updateCurrentTrack(_ track: Track?)
      func updatePlaybackState(_ state: PlaybackState, rate: Double)
      func updateElapsedTime(_ seconds: Double)
      func clear()

      var onPlay: (() -> Void)? { get set }
      var onPause: (() -> Void)? { get set }
      var onTogglePlayPause: (() -> Void)? { get set }
      var onNext: (() -> Void)? { get set }
      var onPrevious: (() -> Void)? { get set }
      var onStop: (() -> Void)? { get set }
      var onSeek: ((Double) -> Void)? { get set }
  }
  ```

**HarmoniaPlayer — Integration Layer**

- `Shared/Services/MPNowPlayingAdapter.swift` (new, `import MediaPlayer`)
  - Implements `NowPlayingService`
  - Manages `MPNowPlayingInfoCenter` info dict
  - Registers `MPRemoteCommandCenter` handlers in `init`
  - Observes `NSApplicationWillTerminate` to clear on quit

**HarmoniaPlayer — AppState**

- `Shared/Models/AppState.swift` (modify)
  - inject `NowPlayingService` via constructor
  - wire command callbacks in `init`
    (`nowPlayingService.onPlay = { [weak self] in self?.play() }` etc.)
  - observe `$currentTrack` → call `updateCurrentTrack(_:)`
  - observe `$playbackState` → call `updatePlaybackState(_:rate:)`
  - in existing polling loop → call `updateElapsedTime(_:)` at 1 Hz
- `Shared/Services/CoreServiceProviding.swift` (modify) — add
  `makeNowPlayingService()` factory
- `Shared/Services/CoreFactory.swift` (modify) — wire service
- `Shared/Services/HarmoniaCoreProvider.swift` (modify) — construct
  default `MPNowPlayingAdapter`

**Tests** (`HarmoniaPlayerTests/SharedTests/`)

- `AppStateNowPlayingTests.swift` (new) — uses `FakeNowPlayingService`
  to verify AppState calls correct methods at correct times

**Test Fakes** (`HarmoniaPlayerTests/Fakes/`)

- `FakeNowPlayingService.swift` (new) — records calls for assertion

**Localisation**

- None. System widgets use system-localised labels. No user-facing UI
  strings introduced by this slice.

### TDD matrix

| Test | Given | When | Then |
|---|---|---|---|
| `testAppState_OnTrackChange_CallsUpdateCurrentTrack` | fake NP service, change currentTrack | publisher fires | `updateCurrentTrack` called with new track |
| `testAppState_OnTrackChangeToNil_CallsClear` | currentTrack set, then set to nil | publisher fires | `clear()` called |
| `testAppState_OnPlay_UpdatesPlaybackState` | paused state | `play()` | `updatePlaybackState(.playing, rate: 1.0)` called |
| `testAppState_OnPause_UpdatesPlaybackState` | playing | `pause()` | `updatePlaybackState(.paused, rate: 0.0)` called |
| `testAppState_OnPause_DoesNotClear` | playing | `pause()` | `clear()` NOT called |
| `testAppState_OnStop_ClearsNowPlaying` | playing | `stop()` | `clear()` called |
| `testAppState_Polling_UpdatesElapsedTime` | playing, polling tick | time advances | `updateElapsedTime(_:)` called with current time |
| `testAppState_OnPlayCommand_InvokesPlay` | NP service `onPlay` invoked externally | callback fires | `AppState.play()` executes |
| `testAppState_OnPauseCommand_InvokesPause` | `onPause` invoked | callback fires | `AppState.pause()` executes |
| `testAppState_OnNextCommand_InvokesNext` | `onNext` invoked | callback fires | `AppState.next()` executes |
| `testAppState_OnPrevCommand_InvokesPrevious` | `onPrevious` invoked | callback fires | `AppState.previous()` executes |
| `testAppState_OnSeekCommand_InvokesSeek` | `onSeek(42.0)` invoked | callback fires | `AppState.seek(to: 42.0)` executes |
| `testAppState_OnTogglePlayPause_Toggles` | playing state, `onTogglePlayPause` | callback fires | state becomes paused |
| `testAppState_OnStopCommand_InvokesStop` | playing, `onStop` invoked | callback fires | `AppState.stop()` executes |

### Done criteria

**Unit test criteria (automated):**

- ⬜ AppState calls `updateCurrentTrack` on track change
- ⬜ AppState calls `updatePlaybackState` on play / pause / stop
- ⬜ AppState calls `updateElapsedTime` during polling
- ⬜ AppState calls `clear` on stop and on `currentTrack = nil`
- ⬜ `pause()` does NOT clear (widget remains visible)
- ⬜ Command callbacks (play / pause / next / prev / seek /
  togglePlayPause / stop) correctly trigger corresponding AppState
  methods
- ⬜ All Slice 1–9 previous tests still green
- ⬜ All new tests green

**Manual QA criteria (system integration):**

- ⬜ With HarmoniaPlayer playing, Control Center shows title /
  artist / album / artwork
- ⬜ Tapping play / pause in Control Center controls HarmoniaPlayer
- ⬜ Tapping next / previous in Control Center advances HarmoniaPlayer
- ⬜ Dragging the progress slider in Control Center seeks HarmoniaPlayer
- ⬜ With HarmoniaPlayer playing and Mac locked, lock screen shows
  playback widget (macOS 14+)
- ⬜ AirPods / Bluetooth headphones single-press toggles play / pause
- ⬜ AirPods double-press advances to next track
- ⬜ Keyboard media keys (F7/F8/F9) control playback
- ⬜ "Hey Siri, pause music" pauses HarmoniaPlayer
- ⬜ "Hey Siri, next song" advances HarmoniaPlayer
- ⬜ Quitting HarmoniaPlayer clears Control Center widget (no stale
  info)

### Non-goals (explicit)

- **No CarPlay integration.** Requires separate
  `MPPlayableContentManager` + entitlements. HarmoniaPlayer is a
  desktop app, not in-vehicle scope.
- **No custom Siri intents.** System defaults via
  `MPRemoteCommandCenter` only.
- **No rating / like / dislike commands.** Not applicable to
  file-based player (streaming-service concepts).
- **No skipForward / skipBackward custom intervals.** Use next /
  previous only; music is not consumed in 15-second skips.
- **No chapter navigation.** Track model has no chapter metadata
  concept.
- **No queue preview.** Control Center will not show "Up Next" list.
  `MPNowPlayingInfoPropertyPlaybackQueueIndex` /
  `MPNowPlayingInfoPropertyPlaybackQueueCount` NOT populated in 9-L.
- **Not cross-platform.** MediaPlayer framework is Apple-only.
  HarmoniaPlayer's Linux/C++ counterpart will need its own MPRIS
  implementation; separate slice in Linux repo.

### Related future work

- **Phase 3a (HarmoniaCore refactor):** no direct impact.
  `NowPlayingService` stays in HarmoniaPlayer — HarmoniaCore is UI /
  system-framework agnostic per module boundary rules. Re-evaluate
  testing strategy at that time (if interface grows or integration
  changes warrant deeper automated testing).
- **v0.15:** re-evaluate the six Non-goals above to see whether
  user feedback, Pro feature planning, or scope changes justify
  adding any of them. Also consider user-configurable elapsed-time
  polling frequency (currently fixed 1 Hz). Consider populating
  `PlaybackQueueIndex` / `PlaybackQueueCount` for richer widget
  info.
- **v0.2 (Pro):** chapter navigation if chapter metadata support
  lands. Rating / like if Pro tier adds library-like features
  (unlikely given file-based positioning).
- **HarmoniaAlarm:** will likely use `MPNowPlayingInfoCenter`
  differently (alarm-specific UI) or skip entirely. No shared code
  expected.
- **Linux/C++ HarmoniaPlayer:** requires MPRIS (Media Player Remote
  Interface Specification) implementation. Separate slice in the
  Linux repo.