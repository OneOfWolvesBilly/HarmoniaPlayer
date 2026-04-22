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
| 9-B | HarmoniaCore replaceItemAt fix + FileInfoView read-only + FileOriginService | Free | v0.1 |
| 9-C | Codec + Encoding fields (TagBundle → Track → FileInfoView) | Free | v0.1 |
| 9-D | FileInfoView `.sheet` → independent `WindowGroup` | Free | v0.1 |
| 9-E | Fix polling loop CPU issue (`CancellationError` handling) | Free | v0.1 |
| 9-F | Error reporting Phase 1 (`lastErrorDetail` + mailto) | Free | v0.1 |
| 9-G | Play/Pause menu label investigation (`@FocusedObject` limitation) | Free | ✅ (resolved by 8-A) |
| 9-H | MiniPlayer focus propagation fix (MiniPlayerView `.focusedSceneObject` + `.focusedValue`) | Free | v0.1 |
| 9-I | Fix Xcode warnings (cosmetic) | Free | v0.1 |

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

See also: Slice 9-H for the MiniPlayer-window case where the same
pattern must be re-registered on the second scene.

---

## Slice 9-H: MiniPlayer Focus Propagation Fix

### Goal

Fix MiniPlayer menu bar failure: when the main window is `orderOut`
during MiniPlayer activation, `HarmoniaPlayerCommands` loses access
to `AppState` and `PlaybackState` because only `ContentView`
registers them via `.focusedSceneObject` / `.focusedValue`. Result:
menu bar items become disabled or unresponsive while MiniPlayer is
the key window.

### Root cause

`ContentView` propagates `appState` via `.focusedSceneObject` and
`playbackState` via `.focusedValue`, which is why the main window
menu bar works (Slice 8-A). Slice 8-B added `MiniPlayerView` and the
second `Window` scene but did not register these values into the
SwiftUI focus system. When MiniPlayer becomes the key window,
`HarmoniaPlayerCommands` reads `nil` from `@FocusedObject` and
`@FocusedValue`, disabling all playback menu items.

### Change

Add two modifiers to `MiniPlayerView.body`, mirroring the pattern
already in `ContentView`:

```swift
.focusedSceneObject(appState)
.focusedValue(\.playbackState, appState.playbackState)
```

### Scope

- ✅ `MiniPlayerView.swift` body modifier additions
- ❌ No changes to `HarmoniaPlayerApp.swift`, `ContentView.swift`,
  `HarmoniaPlayerCommands.swift`, or `PlaybackFocusedValues.swift`
- ❌ No changes to `AppState` or HarmoniaCore

### TDD matrix

Not applicable. SwiftUI focus system propagation requires real
window server key-window state; Swift Testing / XCTest cannot
reliably simulate cross-scene focus transitions. Verification is
manual real-device testing.

### Done criteria

- ⬜ `MiniPlayerView` exposes `appState` via `.focusedSceneObject`
- ⬜ `MiniPlayerView` exposes `playbackState` via `.focusedValue`
- ⬜ Manual test: open MiniPlayer, Playback menu items are enabled
- ⬜ Manual test: Play/Pause menu label reflects live state in MiniPlayer mode
- ⬜ Manual test: switching back to main window preserves menu behavior
- ⬜ No regressions to main window menu behavior

### Commit message

```
fix(slice 9-h): propagate AppState and playbackState from MiniPlayer view

- Slice 8-B added the MiniPlayer Window scene but did not register
  appState and playbackState into the SwiftUI focus system. When
  MiniPlayer becomes the key window (main window ordered out),
  HarmoniaPlayerCommands sees nil for @FocusedObject and
  @FocusedValue, and menu bar Playback items become disabled or
  unresponsive.
- Add .focusedSceneObject(appState) and
  .focusedValue(\.playbackState, ...) to MiniPlayerView.body,
  mirroring the pattern established in ContentView by Slice 8-A.
```

---

## Slice 9-I: Fix Xcode Warnings (Cosmetic)

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

- ⬜ No Xcode warnings from these two test files
- ⬜ Test coverage unchanged
- ⬜ All tests green

### Commit message

```
fix(slice 9-i): resolve "Switch condition evaluates to a constant" warnings

- Refactor switch statements in PlaybackErrorTests and PlaybackStateTests
```