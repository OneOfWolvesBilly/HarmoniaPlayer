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
let clock   = MonotonicClockAdapter()
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
│       │   │   │   ├── ExtendedAttributeService.swift        # xattr for kMDItemWhereFroms
│       │   │   │   ├── FileDropService.swift                 # URL validation + dir expand
│       │   │   │   ├── FreeTierIAPManager.swift              # Stub IAP (Free tier)
│       │   │   │   ├── HarmoniaCoreProvider.swift            # ⚠ Integration Layer
│       │   │   │   ├── HarmoniaPlaybackServiceAdapter.swift  # ⚠ Integration Layer
│       │   │   │   ├── HarmoniaTagReaderAdapter.swift        # ⚠ Integration Layer
│       │   │   │   ├── IAPManager.swift                      # IAPManager protocol + IAPError
│       │   │   │   ├── M3U8Service.swift                     # M3U8 parse/export
│       │   │   │   ├── PlaybackService.swift                 # App-layer protocol (async)
│       │   │   │   ├── StoreKitIAPManager.swift              # StoreKit 2 implementation
│       │   │   │   └── TagReaderService.swift                # App-layer protocol (async)
│       │   │   └── Views/
│       │   │       ├── ContentView.swift                     # Root view
│       │   │       ├── FileInfoView.swift                    # File Info panel
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
        undoManager: UndoManager? = nil
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

## 7. Testing

### 7.1 Test doubles

All test infrastructure lives in
`HarmoniaPlayerTests/FakeInfrastructure/`:

| Double | Replaces | Key features |
|--------|----------|--------------|
| `FakeCoreProvider` | `CoreServiceProviding` | Accepts injectable `FakePlaybackService` and `TagReaderService` stubs; records `makePlaybackService` / `makeTagReaderService` call counts |
| `FakePlaybackService` | `PlaybackService` | Call counts for every method; error stubs (`stubbedLoadError`, `stubbedPlayError`, `stubbedSeekError`); `resetCounts()` for post-setup tests |
| `FakeTagReaderService` | `TagReaderService` | Per-URL metadata stubs (`stubbedMetadata[url]`) and per-URL error stubs (`stubbedErrors[url]`); configurable `stubbedSchemaVersion` |
| `MockIAPManager` | `IAPManager` | `purchaseResult` enum (`.success` / `.failure(IAPError)`); call counts for `refreshEntitlements` and `purchasePro` |

### 7.2 Test class conventions (Swift 6)

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

### 7.3 Running tests

```
Xcode: Product → Test (⌘U)
```

The Xcode project is not an SPM package, so `swift test` does not apply.

---

## 8. Coding Conventions

### 8.1 Swift 6 requirements

- `@MainActor` on `AppState`, all test classes that use AppState, and any
  UI-facing types
- `nonisolated deinit {}` on `@MainActor` classes deallocated in test
  contexts (Xcode 26 beta workaround for `TaskLocal::StopLookupScope` crash)
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
| Initial submission | Ship Free functionality only. Paywall UI hidden in v0.1; Pro code paths reserved for v0.2. |
| After IAP approval | Enable visible Paywall and Pro feature entry points. |
| External payments | Never include external payment links (PayPal, Buy Me a Coffee) inside the app. Such links belong only in GitHub/README. |

---

## 12. Contact

For questions about HarmoniaPlayer development or the Harmonia Suite:

- **Email**: [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub**: [@OneOfWolvesBilly](https://github.com/OneOfWolvesBilly)