# HarmoniaPlayer Development Guide

> **Platform:** macOS 15.6+
> **Language:** Swift 6
> **Framework:** SwiftUI, HarmoniaCore-Swift (SPM)
>
> This guide walks a new contributor through setting up the development
> environment, understanding the cross-repo structure, and following the
> established conventions for HarmoniaPlayer.

---

## 1. Repository Structure

HarmoniaPlayer lives in a three-repo ecosystem:

### 1.1 Three Repositories

1. **[HarmoniaCore](https://github.com/OneOfWolvesBilly/HarmoniaCore)** — source-of-truth specification and implementation
   - Contains both `apple-swift/` and `linux-cpp/` (deferred) side by side
   - Platform-agnostic specifications in `docs/specs/`
   - This is where Swift audio engine development happens

2. **[HarmoniaCore-Swift](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift)** — standalone Swift Package
   - Created via `git subtree split` from `HarmoniaCore/apple-swift/`
   - Required because SPM cannot consume a subdirectory of a repository
   - Tagged releases define what HarmoniaPlayer pins for deployment

3. **[HarmoniaPlayer](https://github.com/OneOfWolvesBilly/HarmoniaPlayer)** (this repo) — macOS application
   - SwiftUI-based UI, application state, integration layer, tests
   - Depends on HarmoniaCore-Swift via SPM

### 1.2 Layout on disk

For local development, clone HarmoniaPlayer and HarmoniaCore **side by side**:

```
~/Projects/
├── HarmoniaCore/                    # Source repo (dev)
│   ├── apple-swift/                 # ← HarmoniaPlayer's SPM target in dev mode
│   │   ├── Package.swift
│   │   ├── Sources/HarmoniaCore/
│   │   └── Tests/HarmoniaCoreTests/
│   ├── linux-cpp/                   # (deferred)
│   └── docs/specs/
│
├── HarmoniaCore-Swift/              # Deploy package (only needed if tagging)
│   └── (subtree split of apple-swift/)
│
└── HarmoniaPlayer/                  # This repo
    └── App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj
```

Xcode resolves the SPM dependency as `../HarmoniaCore/apple-swift` relative
to `HarmoniaPlayer.xcodeproj`. In deploy mode the package resolves from the
pinned GitHub tag of HarmoniaCore-Swift — no local clone needed.

---

## 2. Prerequisites

- **macOS 15.6+**
- **Xcode 26 beta** (the project deployment target is `26.2` for SDK features; macOS runtime target is `15.6`)
- **Swift 6**
- **Git**

---

## 3. Setup

### 3.1 Clone

```bash
# Clone both repos side by side under the same parent directory
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/OneOfWolvesBilly/HarmoniaCore.git
git clone https://github.com/OneOfWolvesBilly/HarmoniaPlayer.git
```

### 3.2 Open in Xcode

```bash
cd ~/Projects/HarmoniaPlayer
open App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj
```

The scheme is **`HarmoniaPlayer`**. Build and run with ⌘R.

### 3.3 Verify HarmoniaCore is wired correctly

Build the project once. If HarmoniaCore cannot be resolved:

1. Xcode → File → Packages → Reset Package Caches
2. If still failing: Project settings → Package Dependencies → remove the broken entry → Add Local → navigate to `../HarmoniaCore/apple-swift`

Sanity check inside one of the Integration Layer files:

```swift
// [HP] Shared/Services/HarmoniaCoreProvider.swift
import HarmoniaCore

// These types should resolve:
let logger  = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "Playback")
let time    = MonotonicTimeAdapter()
let decoder = AVAssetReaderDecoderAdapter(logger: logger)
```

If this compiles, the SPM link is good.

---

## 4. Project Structure

```
HarmoniaPlayer/
├── App/
│   └── HarmoniaPlayer/
│       ├── HarmoniaPlayer.storekit               # StoreKit configuration (testing)
│       ├── HarmoniaPlayer.xcodeproj/
│       ├── HarmoniaPlayer/                       # Main app target
│       │   ├── Shared/                           # Platform-independent code
│       │   │   ├── Models/
│       │   │   │   ├── AppState.swift               # Properties, init, persistence
│       │   │   │   ├── AppState+Playlist.swift      # Playlist ops, undo/redo
│       │   │   │   ├── AppState+Playback.swift      # Transport, volume, ReplayGain
│       │   │   │   ├── AppState+Navigation.swift    # Next/previous, track-finish
│       │   │   │   ├── AppState+M3U8.swift          # M3U8 import/export
│       │   │   │   ├── AudioFileItem.swift          # Drag-and-drop Transferable
│       │   │   │   ├── CoreFeatureFlags.swift       # Free/Pro feature flags
│       │   │   │   ├── EQBand.swift                 # Static band config (Slice 9-K)
│       │   │   │   ├── EQBandState.swift            # Editable per-band state (Slice 9-K)
│       │   │   │   ├── EQCoordinator.swift          # @MainActor EQ observable (Slice 9-K)
│       │   │   │   ├── EQPreset.swift               # Named EQ configuration (Slice 9-K)
│       │   │   │   ├── EQPresets.swift              # Built-in presets (Slice 9-K)
│       │   │   │   ├── LyricsLanguageVariant.swift  # USLT language variant (Slice 9-J)
│       │   │   │   ├── LyricsPreference.swift       # Per-track lyrics preference (Slice 9-J)
│       │   │   │   ├── LyricsResolution.swift       # Lyrics availability + content (Slice 9-J)
│       │   │   │   ├── LyricsSource.swift           # .embedded / .lrc enum (Slice 9-J)
│       │   │   │   ├── NowPlayingCoordinator.swift  # @MainActor NowPlaying wiring (Slice 9-L)
│       │   │   │   ├── PlaybackError.swift          # Typed errors (no String payload)
│       │   │   │   ├── PlaybackState.swift          # idle/loading/playing/paused/stopped/error
│       │   │   │   ├── Playlist.swift               # Playlist model + sort state
│       │   │   │   ├── RepeatMode.swift             # off/all/one
│       │   │   │   ├── ReplayGainMode.swift         # off/track/album
│       │   │   │   ├── ShuffleMode.swift            # off/on
│       │   │   │   ├── Track.swift                  # Track model (Codable, Sendable)
│       │   │   │   └── ViewPreferences.swift        # Layout preferences
│       │   │   ├── Services/
│       │   │   │   ├── CoreFactory.swift                     # (App Layer) factory
│       │   │   │   ├── CoreServiceProviding.swift            # (App Layer) provider protocol
│       │   │   │   ├── EQPersistenceStore.swift              # (App Layer) UserDefaults EQ store (Slice 9-K)
│       │   │   │   ├── EQSchemaMigrator.swift                # (App Layer) EQ schema versioning (Slice 9-K)
│       │   │   │   ├── EQService.swift                       # (App Layer) EQ protocol (Slice 9-K)
│       │   │   │   ├── ExtendedAttributeService.swift        # xattr for kMDItemWhereFroms
│       │   │   │   ├── FileDropService.swift                 # URL validation + dir expand
│       │   │   │   ├── FreeTierIAPManager.swift              # Stub IAP (Free tier)
│       │   │   │   ├── HarmoniaCoreProvider.swift            # ⚠ Integration Layer
│       │   │   │   ├── HarmoniaEQAdapter.swift               # Integration Layer (closure-binding, no HarmoniaCore import) (Slice 9-K)
│       │   │   │   ├── HarmoniaPlaybackServiceAdapter.swift  # ⚠ Integration Layer
│       │   │   │   ├── HarmoniaTagReaderAdapter.swift        # ⚠ Integration Layer
│       │   │   │   ├── IAPManager.swift                      # IAPManager protocol + IAPError
│       │   │   │   ├── LyricsPreferenceStore.swift           # (App Layer) per-track lyrics prefs (Slice 9-J)
│       │   │   │   ├── LyricsService.swift                   # (App Layer) USLT + sidecar resolver (Slice 9-J)
│       │   │   │   ├── M3U8Service.swift                     # M3U8 parse/export
│       │   │   │   ├── MPNowPlayingAdapter.swift             # Integration Layer (imports MediaPlayer, not HarmoniaCore) (Slice 9-L)
│       │   │   │   ├── NowPlayingService.swift               # (App Layer) NowPlaying protocol (Slice 9-L)
│       │   │   │   ├── PlaybackService.swift                 # App-layer protocol (async)
│       │   │   │   ├── StoreKitIAPManager.swift              # StoreKit 2 implementation
│       │   │   │   └── TagReaderService.swift                # App-layer protocol (async)
│       │   │   └── Views/
│       │   │       ├── ContentView.swift                     # Root view
│       │   │       ├── EQView.swift                          # EQ window content (Slice 9-K)
│       │   │       ├── EQWindow.swift                        # EQ window wrapper (Slice 9-K)
│       │   │       ├── FileInfoView.swift                    # File Info panel
│       │   │       ├── LyricsPanel.swift                     # Lyrics display panel (Slice 9-J)
│       │   │       ├── PaywallView.swift                     # Pro paywall sheet
│       │   │       ├── PlaybackFocusedValues.swift           # FocusedValue for Commands
│       │   │       ├── PlayerView.swift                      # Main player
│       │   │       └── PlaylistView.swift                    # Playlist table + tab bar
│       │   ├── macOS/
│       │   │   └── Free/
│       │   │       ├── HarmoniaPlayerApp.swift               # @main entry
│       │   │       └── Views/
│       │   │           ├── HarmoniaPlayerCommands.swift
│       │   │           ├── MarqueeText.swift
│       │   │           ├── MiniPlayerView.swift
│       │   │           └── SettingsView.swift
│       │   ├── Assets.xcassets
│       │   ├── en.lproj/Localizable.strings
│       │   ├── zh-Hant.lproj/Localizable.strings
│       │   └── ja.lproj/Localizable.strings
│       ├── HarmoniaPlayerTests/
│       │   ├── FakeInfrastructure/
│       │   │   ├── FakeCoreProvider.swift                    # CoreServiceProviding double
│       │   │   ├── FakeNowPlayingService.swift               # NowPlayingService double (Slice 9-L)
│       │   │   ├── FakeTagReaderService.swift                # TagReaderService double
│       │   │   └── MockIAPManager.swift                      # IAPManager double
│       │   └── SharedTests/                                  # Unit tests (one per SUT)
│       └── HarmoniaPlayerUITests/
├── docs/
│   ├── api_reference.md
│   ├── architecture.md
│   ├── development_guide.md           ← this file
│   ├── documentation_strategy.md
│   ├── implementation_guide_swift.md
│   ├── module_boundary.md
│   ├── user_guide.md
│   ├── workflow.md
│   └── slice/
│       ├── HarmoniaPlayer_development_plan.md
│       └── slice_NN_micro.md
├── README.md
└── LICENSE
```

**Key rules:**
- `import HarmoniaCore` is **only** allowed in 3 files in `Shared/Services/` (marked ⚠ Integration Layer)
- `import MediaPlayer` is **only** allowed in `MPNowPlayingAdapter.swift` (Slice 9-L)
- `Shared/` contains all cross-platform code; `macOS/Free/` contains the entry point and macOS-only views
- Test doubles live in `FakeInfrastructure/`; test cases in `SharedTests/` (one file per system under test)

See [Module Boundaries](module_boundary.md) for enforcement rules.

---

## 5. HarmoniaCore Integration

### 5.1 The 3-file rule

Only these three files may `import HarmoniaCore`. Everything else in the app
depends on app-layer protocols:

| File | Purpose |
|------|---------|
| `[HP] HarmoniaCoreProvider.swift` | Constructs real HarmoniaCore services and platform adapters |
| `[HP] HarmoniaPlaybackServiceAdapter.swift` | Wraps `[HC] DefaultPlaybackService`; maps `CoreError` → `PlaybackError`; sync → async |
| `[HP] HarmoniaTagReaderAdapter.swift` | Wraps `[HC] TagReaderPort`; maps `TagBundle` → `Track` |

Any other file importing HarmoniaCore is a boundary violation.

> **Slice 9-K note:** `HarmoniaEQAdapter.swift` is in the Integration Layer
> too, but it does **not** `import HarmoniaCore`. It bridges the Core
> PlaybackService EQ control surface to `EQService` via three closures bound
> by `HarmoniaCoreProvider.makeEQService()`, so the Core type surface stays
> confined to the provider. The 3-file rule above is unchanged.

> **Slice 9-L note:** `MPNowPlayingAdapter.swift` is also in the Integration
> Layer but imports `MediaPlayer` (not `HarmoniaCore`). It bridges
> `NowPlayingService` to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
> — system surfaces, not the audio core. This is the only `import MediaPlayer`
> site in HarmoniaPlayer. The 3-file rule above is unchanged.

### 5.2 Dependency flow

```
SwiftUI Views
    ↓ @EnvironmentObject
AppState (@MainActor, ObservableObject)
    ↓ constructor-injected via CoreFactory
PlaybackService, TagReaderService   (app-layer protocols)
    ↓ implemented by
HarmoniaPlaybackServiceAdapter, HarmoniaTagReaderAdapter   (Integration Layer)
    ↓ wraps
DefaultPlaybackService, TagReaderPort   (HarmoniaCore-Swift)
    ↓ use
AVAssetReader, AVAudioEngine, AVMetadata*   (AVFoundation)
```

### 5.3 AppState wiring

AppState does **not** import HarmoniaCore. The `HarmoniaPlayerApp` entry point
constructs production dependencies and passes them into AppState's init:

```swift
// [HP] HarmoniaPlayerApp.swift
@main
struct HarmoniaPlayerApp: App {
    @StateObject private var appState = AppState(
        iapManager: StoreKitIAPManager(),
        provider:   HarmoniaCoreProvider()
    )
    // ...
}
```

Inside AppState:

```swift
@MainActor
final class AppState: ObservableObject {
    let playbackService: PlaybackService        // app-layer protocol
    let tagReaderService: TagReaderService      // app-layer protocol
    let fileDropService: FileDropService

    private let iapManager: IAPManager
    private(set) var featureFlags: CoreFeatureFlags

    @Published private(set) var isProUnlocked: Bool
    @Published var playlists: [Playlist]
    @Published var currentTrack: Track?
    @Published var playbackState: PlaybackState = .idle
    @Published var lastError: PlaybackError?

    init(
        iapManager: IAPManager,
        provider: CoreServiceProviding,
        userDefaults: UserDefaults = .standard,
        undoManager: UndoManager? = nil,
        lyricsPreferenceStore: LyricsPreferenceStore? = nil,
        eqCoordinator: EQCoordinator? = nil
    ) {
        self.iapManager   = iapManager
        self.featureFlags = CoreFeatureFlags(iapManager: iapManager)

        let coreFactory = CoreFactory(
            featureFlags: featureFlags,
            provider:     provider
        )
        self.playbackService  = coreFactory.makePlaybackService()
        self.tagReaderService = coreFactory.makeTagReaderService()
        self.fileDropService  = FileDropService()
        self.isProUnlocked    = iapManager.isProUnlocked
        // ... rest of init
    }
}
```

For the full adapter and provider implementations, see
[Implementation Guide (Swift)](implementation_guide_swift.md).

---

## 6. Cross-Repo Workflow

HarmoniaPlayer and HarmoniaCore are separate repos with their own commit
histories. Changes that span both repos must be coordinated.

### 6.1 Development mode: local path reference

For day-to-day development, the Xcode project references
`../HarmoniaCore/apple-swift` as a local SPM. This means:

- Editing a file in `HarmoniaCore/apple-swift/Sources/` and rebuilding
  HarmoniaPlayer picks up the change immediately — no re-resolve needed
- You can run HarmoniaCore's own `swift test` against `apple-swift/` while
  HarmoniaPlayer's tests run against the same working copy

### 6.2 Deploy mode: GitHub tag

For release builds, the SPM dependency is pinned to a tagged version of the
**HarmoniaCore-Swift** repo (not HarmoniaCore). The workflow is:

1. Commit + push changes in `HarmoniaCore`
2. Cut a tag on `HarmoniaCore` (e.g. `v0.3.0`)
3. `git subtree split` the `apple-swift/` directory into HarmoniaCore-Swift
4. Push the subtree-split branch + tag to HarmoniaCore-Swift
5. In HarmoniaPlayer, update the SPM pin to the new tag
6. Commit the updated `Package.resolved` in HarmoniaPlayer

This two-step tag flow (HarmoniaCore → HarmoniaCore-Swift) exists because
SPM cannot consume a subdirectory of a repository — HarmoniaCore-Swift is
the valid Package.swift root needed for remote resolution.

### 6.3 When to make a cross-repo change

A typical cross-repo fix flow:

1. Reproduce the issue in HarmoniaPlayer (usually surfaced by a failing test)
2. Trace through the Integration Layer adapter to locate the root cause —
   is it in `[HP]` adapter code or in `[HC]` service/adapter code?
3. If root cause is in HarmoniaCore: fix + test in HarmoniaCore first
4. Back in HarmoniaPlayer: add a test that verifies the adapter behaviour
   with the fixed core
5. Commit both repos separately (HarmoniaCore first, then HarmoniaPlayer)
6. If the change is release-blocking, follow the deploy workflow in 6.2

### 6.4 Commit formats

Both repos use conventional commits, but with repo-specific scopes:

**HarmoniaPlayer** (`type(scope): description`):
```
feat(slice 9-B): add tag editor basic fields
fix(slice 7): remove duplicate format gate in load(urls:)
```
- Scope is always the active slice
- Bullet points use `-` only; no prose paragraphs
- Spec commit precedes code commit (separate commits)

**HarmoniaCore** (standard conventional commits):
```
feat(ports): add TagWriterPort
fix(adapters): handle nil duration from AVURLAsset
refactor(services): rename PlaybackState.buffering to .loading
```
- Scope is the module (ports, adapters, services, models)

---

## 7. Sandbox File Access Patterns

Slice 9-M. HarmoniaPlayer ships with `ENABLE_APP_SANDBOX = YES` for App Store distribution. Two file-access scenarios occur and use different mechanisms:

### 7.1 User-selected primary files: security-scoped bookmarks

The user grants access by selecting an audio file via `NSOpenPanel` or drag-drop. The system issues an in-process sandbox extension on that URL. To persist this access across cold-launch:

1. Encode the URL with `URL.bookmarkData(options: [.withSecurityScope])`. This must happen while the in-process extension is active — `AppState.load(urls:)` wraps the body of its `for url in urls` loop with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` (paired via `defer` inside the loop body, which is per-iteration scope, not method scope) so the bookmark capture succeeds.
2. On decode, resolve with `URL(resolvingBookmarkData:options:)` using `[.withSecurityScope]` and capture `bookmarkDataIsStale: &stale`.
3. Call `startAccessingSecurityScopedResource()` on the resolved URL — `Track.isAccessible` is set to its return value. Do NOT call `stopAccessingSecurityScopedResource()` after success: the macOS sandbox requires an active extension at every read, and stopping releases the extension so PlaybackService open returns FigFile err=-12203 / "File Not Found". The extension is held for the URL's lifetime and released as a side effect when the Track value is dropped from the playlist (NSURL ref count → 0).
4. The resolved URL replaces the in-memory `Track.url`. On the next `JSONEncoder().encode(track)` pass, `URL.bookmarkData(.withSecurityScope)` regenerates the bookmark from the now-current URL — this implicitly handles `bookmarkDataIsStale = true` without an explicit refresh helper.

Legacy `.minimalBookmark` data (in case any made it to a development build) fails to resolve under `[.withSecurityScope]`; the decode path falls through to `urlPath` with `isAccessible = false`. No migration tool is shipped — v1.0.0 is HarmoniaPlayer's first public release.

### 8.2 Sibling files: Related Items + NSFileCoordinator

Sibling reads (e.g. `Foo.lrc` next to `Foo.flac`) cannot use the primary file's bookmark — `startAccessingSecurityScopedResource` does not extend access to siblings. Apple's first-class mechanism for this topology is **Related Items**:

1. Declare the sibling extension in `Info.plist` `CFBundleDocumentTypes`:
   ```xml
   <key>CFBundleTypeName</key>      <string>LRC Lyrics File</string>
   <key>CFBundleTypeExtensions</key> <array><string>lrc</string></array>
   <key>CFBundleTypeRole</key>      <string>Editor</string>
   <key>NSIsRelatedItemType</key>   <true/>
   ```
   `CFBundleTypeRole = Editor` is mandatory; `None` and `Viewer` cause the sandbox to silently refuse the related-item extension (Apple Developer Forum thread 14718).

2. At read site, register an `NSFilePresenter` whose `primaryPresentedItemURL` is the user-selected primary file and `presentedItemURL` is the candidate sibling:
   ```swift
   let presenter = SiblingFilePresenter(
       primaryItemURL: track.url,
       presentedItemURL: lrcURL
   )
   NSFileCoordinator.addFilePresenter(presenter)
   defer { NSFileCoordinator.removeFilePresenter(presenter) }
   ```

3. Issue a coordinated read:
   ```swift
   let coordinator = NSFileCoordinator(filePresenter: presenter)
   var coordError: NSError?
   var data: Data?
   coordinator.coordinate(readingItemAt: lrcURL, options: [], error: &coordError) { url in
       data = try? Data(contentsOf: url)
   }
   ```
   The sandbox issues a related-item extension for the duration of the coordinated block.

`SiblingFilePresenter` (`Shared/Services/SiblingFilePresenter.swift`) is a minimal `NSFilePresenter` conformance with three properties and a constructor — no behavioural callbacks. Each sibling extension that needs Related Items access requires its own `CFBundleDocumentTypes` entry with `NSIsRelatedItemType=YES` and `CFBundleTypeRole=Editor`.

### 8.3 What does NOT work

- **`Data(contentsOf: lrcURL)`** without coordinated read — fails with `NSCocoaErrorDomain Code=257` regardless of bookmarks.
- **Calling `startAccessingSecurityScopedResource` on the sibling URL** — this only works for security-scoped URLs (i.e. those resolved from a bookmark). Sibling URLs are not security-scoped; the call returns `false` and the read still fails.
- **`NSFileCoordinator` without an `NSFilePresenter` registered** — the sandbox refuses to issue a related-item extension; the system log prints `NSFileSandboxingRequestRelatedItemExtension: Failed to issue extension`.
- **`NSFileCoordinator` with `CFBundleTypeRole = None` or `Viewer`** — `addFilePresenter` silently fails; subsequent reads still error with Code=257 and no diagnostic output.

### 8.4 Error categorisation

`LyricsPanel`'s error UI uses the free function `lyricsErrorMessageKey(for: Error)` to map errors to user-facing messages. `Code=257` surfaces as `lyrics_file_inaccessible` ("Lyrics file is not accessible. Try removing and re-adding the track."); `LyricsServiceError.decodingFailed` and any other unrecognised error fall back to `lyrics_decode_failed`.

---

## 8. Testing

### 8.1 Test doubles

All test infrastructure lives in
`HarmoniaPlayerTests/FakeInfrastructure/`:

| Double | Replaces | Key features |
|--------|----------|--------------|
| `FakeCoreProvider` | `CoreServiceProviding` | Accepts injectable `FakePlaybackService`, `TagReaderService`, `FakeLyricsService`, `FakeEQService`, and `FakeNowPlayingService` stubs; records `makePlaybackService` / `makeTagReaderService` / `makeLyricsService` / `makeEQService` / `makeNowPlayingService` call counts |
| `FakePlaybackService` | `PlaybackService` | Call counts for every method; error stubs (`stubbedLoadError`, `stubbedPlayError`, `stubbedSeekError`); `resetCounts()` for post-setup tests |
| `FakeTagReaderService` | `TagReaderService` | Per-URL metadata stubs (`stubbedMetadata[url]`) and per-URL error stubs (`stubbedErrors[url]`); configurable `stubbedSchemaVersion` |
| `FakeLyricsService` | `LyricsService` | No-op fake: `resolveAvailability` returns `.none`, `resolveContent` throws `noEmbeddedLyrics`, `stripLRCTimestamps` returns input unchanged. Defined inline in `FakeCoreProvider.swift`, not a separate file (Slice 9-J). **Why a fake instead of `DefaultLyricsService`:** the real service triggers an Xcode 26 beta Swift runtime double-free when many short-lived instances coexist across the test suite — the fake sidesteps the toolchain bug entirely with no closure storage and no Locale dependency |
| `StubLyricsService` | `LyricsService` | Configurable stub for tests verifying AppState reactions to specific resolutions: `stubbedResolution` lets the test dictate `resolveAvailability` output; `resolveAvailabilityCallCount` and `lastResolvedTrack` for assertion. Also defined inline in `FakeCoreProvider.swift` (Slice 9-J). Same toolchain-bug-avoidance rationale as `FakeLyricsService` |
| `FakeEQService` | `EQService` | Call counts (`setEnabledCallCount`, `setPreampCallCount`, `setBandGainsCallCount`) plus last value captured (`lastSetEnabled`, `lastSetPreamp`, `lastSetBandGains`); defined inline in `FakeCoreProvider.swift`, not a separate file (Slice 9-K) |
| `FakeNowPlayingService` | `NowPlayingService` | Push call counters (`updateCurrentTrackCallCount` / `updatePlaybackStateCallCount` / `updateElapsedTimeCallCount` / `clearCallCount`) plus last-value captures (`lastUpdatedTrack` / `lastUpdatedState` / `lastUpdatedRate` / `lastUpdatedElapsed`) and `updatedElapsedHistory` array; pull-side callback properties (`onPlay` / `onPause` / `onTogglePlayPause` / `onNext` / `onPrevious` / `onStop` / `onSeek`) tests can invoke directly to simulate system commands. Standalone file in `FakeInfrastructure/` (Slice 9-L) |
| `MockIAPManager` | `IAPManager` | `purchaseResult` enum (`.success` / `.failure(IAPError)`); call counts for `refreshEntitlements` and `purchasePro` |

### 8.2 Test class conventions (Swift 6)

AppState is `@MainActor`, so test classes that use it must also be
`@MainActor` — XCTest runs `@MainActor`-isolated classes on the main actor
automatically, so individual test methods don't need `await MainActor.run {}`.

Per-test `UserDefaults` must use a unique `suiteName` to avoid cross-test
contamination, and must be cleaned up in `tearDown`:

```swift
@MainActor
final class AppStatePlaybackControlTests: XCTestCase {

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(
            iapManager:   iap,
            provider:     provider,
            userDefaults: testDefaults
        )
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPlayCallsServicePlay() async {
        // Seed a track (this calls play(trackID:) internally and bumps counts)
        await seedTracks()

        // Reset counts before the operation under test
        fakePlaybackService.resetCounts()

        await sut.play()

        XCTAssertEqual(fakePlaybackService.playCallCount, 1)
        XCTAssertEqual(sut.playbackState, .playing)
    }

    private func seedTracks() async {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await sut.load(urls: [url])
        if let first = sut.playlist.tracks.first {
            await sut.play(trackID: first.id)
        }
    }
}
```

Rules:
- One operation per test — setup helpers call `resetCounts()` before the
  assertion target so the count reflects the operation under test only
- Use `await` for every async AppState call — `play`, `pause`, `stop`,
  `seek`, `load`, `play(trackID:)`, `playNextTrack`, `playPreviousTrack`
- `final class` and unique `suiteName` per test

### 8.3 Running tests

```
Xcode: Product → Test (⌘U)
```

The Xcode project is not an SPM package, so `swift test` does not apply.

---

## 8. Coding Conventions

### 8.1 Swift 6 requirements

- `@MainActor` on `AppState`, all test classes that use AppState, and any
  UI-facing types
- `nonisolated deinit {}` on every inferred-`@MainActor` `final class`
  (Xcode 26 beta workaround for the `swift_task_deinitOnExecutorImpl` /
  `TaskLocal::StopLookupScope` crash). Applies to long-lived production
  classes too, not just test-deallocated ones — see §8.6 for the full
  rationale and inventory.
- `Sendable` on all models crossing actor boundaries (`Track`, `Playlist`,
  `PlaybackState`, `PlaybackError`, `ViewPreferences`, `CoreFeatureFlags`)

### 8.2 Access control

- Services on AppState are `let` (internal), not `private let` — Views
  access AppState, not the services directly, but the boundary is
  architectural, not enforced by Swift access modifiers
- `@Published` properties are `var` by default; use `private(set)` only
  when the View should never write (e.g. `isProUnlocked`)

### 8.3 SwiftUI patterns

- Views use `@EnvironmentObject private var appState: AppState`
- Button handlers wrap async AppState calls: `Task { await appState.play() }`
- Never inject services directly into a View

```swift
// ✓ Correct
struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
}

// ✗ Incorrect — boundary violation
struct PlayerView: View {
    let playbackService: PlaybackService
}
```

### 8.4 Error handling

The boundary does the mapping. AppState only sees `PlaybackError`:

```swift
// Inside [HP] HarmoniaPlaybackServiceAdapter (Integration Layer)
static func mapCoreError(_ error: CoreError) -> PlaybackError {
    switch error {
    case .notFound:        return .failedToOpenFile
    case .ioError:         return .failedToOpenFile
    case .unsupported:     return .unsupportedFormat
    case .decodeError:     return .failedToDecode
    case .invalidState:    return .invalidState
    case .invalidArgument: return .invalidArgument
    }
}

// Inside AppState — only sees PlaybackError, never CoreError
func play() async {
    do {
        try await playbackService.play()
        playbackState = .playing
    } catch {
        let mapped = mapToPlaybackError(error)
        lastError = mapped
        playbackState = .error(mapped)
    }
}

func mapToPlaybackError(_ error: Error) -> PlaybackError {
    if let playbackError = error as? PlaybackError { return playbackError }
    return .invalidState   // fallback for unexpected errors
}
```

No `String` payload crosses the module boundary. `PlaybackError` cases
are all pure typed codes.

### 8.5 Language rules

- Explanations, chat discussion: Traditional Chinese
- All Swift code, comments, commit messages, documentation: **English only**
- No competitor brand names anywhere in docs

### 8.6 `nonisolated deinit` pattern (Xcode 26 beta workaround)

The HarmoniaPlayer module is built with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which causes every `final class`
without an explicit isolation annotation to be **inferred** as `@MainActor`.
On Xcode 26 beta, the compiler-synthesised deinit on such a class routes
deallocation through `swift_task_deinitOnExecutorImpl`, and the runtime
double-frees TaskLocal storage during teardown
(`TaskLocal::StopLookupScope`), causing a crash.

**Mitigation:** declare an empty `nonisolated deinit { }` on every affected
class. Methods stay on the MainActor, but deallocation falls back to the
synchronous ARC path that does not touch TaskLocal storage.

```swift
@MainActor                       // explicit OR inferred — both apply
final class SomeObservable: ObservableObject {
    // … MainActor-isolated state and methods …

    nonisolated deinit { }       // forces synchronous ARC deallocation
}
```

**When the workaround IS needed.** Any class that is `@MainActor` (explicit
or inferred). The `final` modifier is independent — it does not change the
deinit behaviour. Four known production / test sites in HarmoniaPlayer:

| Class | File | Why |
|-------|------|-----|
| `AppState` | `Shared/Models/AppState.swift` | Explicit `@MainActor`; long-lived but still hits the bug on test teardown |
| `EQCoordinator` | `Shared/Models/EQCoordinator.swift` | Inferred `@MainActor`; long-lived but holds `EQService` reference that captures Core types |
| `HarmoniaEQAdapter` | `Shared/Services/HarmoniaEQAdapter.swift` | Inferred `@MainActor`; three escaping closures capture `HarmoniaCore.PlaybackService` — releasing them through the isolated deinit triggers the bug |
| `FakeEQService` | `HarmoniaPlayerTests/FakeInfrastructure/FakeCoreProvider.swift` | Inferred `@MainActor` in the main module's actor isolation; many short-lived test instances exercise the crash path repeatedly |

**When the workaround is NOT needed.** Classes already declared
`nonisolated`, structs, enums, and actors are unaffected because their
deinit is not `@MainActor`-isolated. Examples in HarmoniaPlayer:

- `nonisolated final class EQPersistenceStore` — no workaround needed
  (whole class is non-isolated)
- `nonisolated enum EQSchemaMigrator` — no instance, no deinit
- `struct EQBand` / `EQBandState` / `EQPreset` / `EQPresets` — value types

**Common mistake:** earlier in-source comments (now corrected) claimed *"if
the class has no explicit deinit body, the bug is avoided."* That was wrong.
The compiler-synthesised deinit on an inferred-`@MainActor` class still
hits the bug — only an **explicit `nonisolated deinit { }`** sidesteps it.
If you see such a comment in a stale branch, replace it with a reference to
this section.

When the upstream fix lands, this workaround can be removed in one sweep.
Until then, every new `@MainActor` `final class` added to the codebase
should ship with `nonisolated deinit { }` from the first commit.

---

## 9. Workflow

The project follows SDD → TDD red → confirm → TDD green → commit. The
detailed workflow and commit atomicity rules are in [Workflow](workflow.md).

### 9.1 Adding a feature (summary)

1. **Write the spec first** — `docs/slice/slice_NN_micro.md` with Goal,
   Scope, Files, API, TDD plan, Commit plan
2. **Commit the spec** separately from any code
3. **Write the failing tests** for the first commit in the plan
4. **Run tests — confirm red**
5. **Implement** — minimal code to make the tests pass
6. **Run tests — confirm green**
7. **Commit** with the format `feat(slice X-Y): description`
8. Repeat for each commit in the plan

Spec and code commits are always separate. One logical change per commit.

### 9.2 Debugging

- Logs: `OSLogAdapter` in HarmoniaCore emits to OSLog subsystem
  `HarmoniaPlayer` / category `Playback`. View in Console.app or Xcode Console.
- Useful breakpoints: `AppState.play()`, `AppState.play(trackID:)`,
  `AppState.load(urls:)`, `HarmoniaPlaybackServiceAdapter.mapCoreError`
- StoreKit: use `HarmoniaPlayer.storekit` configuration file for local IAP
  testing (Scheme → Edit Scheme → Run → Options → StoreKit Configuration)

### 9.3 Common issues

| Symptom | Likely cause |
|---------|--------------|
| "Cannot find type 'PlaybackService'" | Missing the import or confusing app-layer with `[HC]` — check file header |
| SPM resolution fails | HarmoniaCore not cloned side by side; reset package caches |
| Test crashes on deinit | Missing `nonisolated deinit {}` on a `@MainActor` class |
| `@MainActor` error in test | Add `@MainActor` to the whole test class, not individual methods |
| Duplicate state after purchase | Forgot to rebuild `featureFlags = CoreFeatureFlags(iapManager:)` |

---

## 10. Documentation References

### HarmoniaPlayer (this repo)

- [README](../README.md) — project overview
- [Architecture](architecture.md) — system design and C4 diagrams
- [API Reference](api_reference.md) — complete interface surface
- [Module Boundaries](module_boundary.md) — dependency rules
- [Implementation Guide (Swift)](implementation_guide_swift.md) — patterns and complete code examples
- [Workflow](workflow.md) — SDD → TDD → commit cycle
- [Documentation Strategy](documentation_strategy.md) — doc naming and update rules
- [User Guide](user_guide.md) — end-user feature documentation

### HarmoniaCore

- [Architecture Overview](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [Adapters Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/02_adapters.md)
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
- [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
- [Models Specification (CoreError, TagBundle)](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)

### HarmoniaCore-Swift

- [Swift Package README](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift/blob/main/README.md)

---

## 11. App Store Review Considerations

| Phase | Recommendation |
|-------|----------------|
| Initial submission | Ship Free functionality only. Paywall UI hidden in v1.0.0; Pro code paths reserved for v2.0.0. |
| After IAP approval | Enable visible Paywall and Pro feature entry points. |
| External payments | Never include external payment links (PayPal, Buy Me a Coffee) inside the app. Such links belong only in GitHub/README. |

---

## 12. Contact

For questions about HarmoniaPlayer development or the Harmonia Suite:

- **Email**: [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub**: [@OneOfWolvesBilly](https://github.com/OneOfWolvesBilly)