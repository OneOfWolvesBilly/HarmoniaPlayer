# HarmoniaPlayer Module Boundary (Apple / Swift)

> This document defines the **module boundaries** and **allowed dependencies** for
> the Apple / Swift implementation of HarmoniaPlayer.
>
> It is intended as a "contract" for contributors and reviewers, to keep the
> architecture clean and maintainable as the codebase grows.

---

## 1. Objectives

- Enforce a clear **separation of concerns** between UI, application logic,
  integration, and core services.
- Make it explicit which modules are allowed to depend on which others.
- Prevent Apple-specific details (AVFoundation, StoreKit, OSLog, etc.) from
  leaking into UI and application layers.
- Make HarmoniaPlayer a good example of a **Ports & Adapters** style app
  consuming HarmoniaCore-Swift.
- Ensure alignment with [HarmoniaCore Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md).

This document applies to the macOS / Swift implementation.

---

## 2. High-Level Module List

At a high level, the codebase is divided into the following logical modules.

> Note: These are **conceptual modules**; their physical mapping to targets,
> frameworks, or directories can vary as long as the boundaries are respected.

1. **UI Layer (Views)**
   - SwiftUI views under `Shared/Views/` and platform-specific view wrappers.
2. **Application Layer (State & Models)**
   - `AppState` (central observable state, split across 5 files)
   - `EQCoordinator` — `@MainActor` `ObservableObject` owning all EQ-related
     observable state. Lives in `Shared/Models/` parallel to `AppState`
     (state-bearing observable, not stateless service). Slice 9-K. See §4.3.
   - `NowPlayingCoordinator` — `@MainActor` class that owns NowPlaying
     wiring between AppState publishers, AppState action closures, and
     the system Now Playing surface via `NowPlayingService`. Lives in
     `Shared/Models/` parallel to `EQCoordinator` (lifecycle
     participant, not stateless service). Slice 9-L. See §4.5.
   - UI-facing models (`Track`, `Playlist`, `ViewPreferences`, `AudioFileItem`,
     `EQBand`, `EQBandState`, `EQPreset`, `EQPresets`,
     `LyricsLanguageVariant`, `LyricsSource`, `LyricsPreference`,
     `LyricsResolution`, etc.)
   - App-layer service protocols (`PlaybackService`, `TagReaderService`,
     `EQService`, `LyricsService`, `LyricsPreferenceStore`,
     `NowPlayingService`) — defined here so that `AppState` /
     coordinators can depend on them without importing platform
     frameworks.
   - Application services: `FileDropService`, `ExtendedAttributeService`, `M3U8Service`,
     `ErrorReportService`, `EQPersistenceStore`, `EQSchemaMigrator`,
     `SiblingFilePresenter` (pure Swift / Foundation utilities with no
     HarmoniaCore dependency).
   - Factory abstractions: `CoreFactory`, `CoreServiceProviding` protocol.
3. **Integration Layer** (only place where `import HarmoniaCore` or other system-bridge frameworks are allowed)
   - `HarmoniaCoreProvider` — constructs HarmoniaCore services, wires ports to adapters.
   - `HarmoniaPlaybackServiceAdapter` — wraps HarmoniaCore `DefaultPlaybackService`,
     maps `CoreError` → `PlaybackError`.
   - `HarmoniaTagReaderAdapter` — wraps `TagReaderPort`, maps `TagBundle` → `Track`.
   - `HarmoniaEQAdapter` — bridges Core PlaybackService EQ control surface
     (`setEQEnabled` / `setEQPreamp` / `setEQBandGains`) to `EQService` via closure
     binding. **Does NOT `import HarmoniaCore` by design**; closures are bound
     by `HarmoniaCoreProvider.makeEQService()` so the Core type surface stays
     confined to the provider. Counts as Integration Layer placement but does
     not consume one of the three HarmoniaCore-import slots.
   - `MPNowPlayingAdapter` — bridges `NowPlayingService` to
     `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. Slice 9-L. Sole
     `import MediaPlayer` site in HarmoniaPlayer; does not `import
     HarmoniaCore` because it bridges to a system-level macOS surface, not
     the audio core.
   - `IAPManager` protocol + `StoreKitIAPManager` (macOS Pro unlock) + `FreeTierIAPManager` (stub).
4. **Core Services (HarmoniaCore-Swift)**
   - `PlaybackService` - High-level audio service
5. **Ports (HarmoniaCore-Swift)**
   - Abstract interfaces: `DecoderPort`, `AudioOutputPort`, `TagReaderPort`, `ClockPort`, `LoggerPort`, `FileAccessPort`, `TagWriterPort`, `EQPort`
6. **Platform Adapters (HarmoniaCore-Swift)**
   - `AVAssetReaderDecoderAdapter`
   - `AVAudioEngineOutputAdapter`
   - `AVAudioUnitEQAdapter`
   - `AVMetadataTagReaderAdapter`
   - `AVMutableTagWriterAdapter`
   - `MonotonicClockAdapter`
   - `OSLogAdapter`
   - `NoopLogger`
   - `SandboxFileAccessAdapter`

HarmoniaCore-Swift and its adapters live in a **separate package**. From the
HarmoniaPlayer perspective, they are external dependencies.

**See HarmoniaCore Ports & Adapters:**
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
- [Adapters Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/02_adapters.md)

---

## 3. Allowed Dependencies

### 3.1 Overview Diagram

```mermaid
flowchart LR
    views[UI Layer
(SwiftUI Views)]
    app[Application Layer
(AppState, UI models,
app-layer service protocols)]
    integration[Integration Layer
(CoreFactory, IAPManager,
Adapter Wrappers)]
    services[Core Services
(PlaybackService)]
    ports[Ports
(DecoderPort, AudioOutputPort,
TagReaderPort, etc.)]
    adapters[Platform Adapters
(AV* / OSLog / Clock)]

    views --> app
    app --> integration
    integration --> services
    integration --> ports
    services --> ports
    ports --> adapters
```

### 3.2 Rules

1. **UI Layer** may depend on:
   - Application Layer (AppState, UI models).
   - Standard Apple frameworks (SwiftUI, Combine, Foundation) for rendering and binding.

   UI Layer **must not**:
   - Import HarmoniaCore-Swift directly.
   - Import or reference platform adapters.
   - Call `PlaybackService` or ports directly.
   - Access any audio-related code.

2. **Application Layer** may depend on:
   - HarmoniaPlayer UI models.
   - Integration Layer abstractions (`CoreFactory` interface, `IAPManager` interface).
   - **PlaybackService interface only** (not concrete implementations).
   - **TagReaderService interface** for metadata reading.
   - **EQService interface** for equaliser control (Slice 9-K).
   - **LyricsService interface** for USLT + sidecar `.lrc` resolution (Slice 9-J).
   - **LyricsPreferenceStore interface** for per-track lyrics preference persistence (Slice 9-J).

   Application Layer **must not**:
   - Instantiate platform adapters directly.
   - Call AVFoundation APIs directly.
   - Import OSLog, StoreKit, or other Apple-specific frameworks, except through
     small, well-defined interfaces.
   - Directly use HarmoniaCore Ports (DecoderPort, AudioOutputPort, TagReaderPort, etc.).

3. **Integration Layer** may depend on:
   - Core service interfaces and their concrete implementations.
   - **All HarmoniaCore-Swift ports and platform adapters**.
   - System-bridge frameworks required to wire to system surfaces
     (e.g. StoreKit for IAP, MediaPlayer for system Now Playing).

   Integration Layer **must not**:
   - Contain UI rendering logic (no SwiftUI views).
   - Manipulate SwiftUI layout or view state directly.
   - Expose HarmoniaCore Ports or Adapters to Application Layer.

4. **Core Services (HarmoniaCore-Swift)** may depend on:
   - Ports (protocols) that abstract decoding, audio output, logging, and clocks.
   - Pure Swift utility types.

   Core Services **must not**:
   - Depend on SwiftUI, AppKit, or any UI framework.
   - Depend on IAP or licensing logic.
   - Know about Free vs Pro product variants.

5. **Platform Adapters (HarmoniaCore-Swift)** may depend on:
   - AVFoundation, AudioToolbox, OSLog, and other Apple-specific frameworks.
   - HarmoniaCore-Swift port protocols.

   Platform Adapters **must not**:
   - Import SwiftUI.
   - Know anything about `AppState` or application state.
   - Embed business decisions about Free vs Pro.

---

## 4. Special Cases and Clarifications

### 4.1 TagReaderService Usage

**AppState uses TagReaderService (not TagReaderPort directly) for metadata reading.**

**Rationale:** Metadata reading is needed during file import to populate Track models.
TagReaderService is an application-level abstraction that wraps HarmoniaCore's TagReaderPort.

**Usage Pattern:**
```swift
// In AppState
@MainActor
final class AppState: ObservableObject {
    let tagReaderService: TagReaderService
    
    func load(urls: [URL]) async {
        for url in urls {
            do {
                let track = try await tagReaderService.readMetadata(for: url)
                playlists[activePlaylistIndex].tracks.append(track)
            } catch {
                let track = Track(url: url)
                playlists[activePlaylistIndex].tracks.append(track)
                lastError = .failedToOpenFile
            }
        }
        saveState()
    }
}
```

**Not allowed:**
```swift
// ❌ AppState must NOT use Ports directly
let tagReader: TagReaderPort = factory.makeTagReader()  // FORBIDDEN
```

### 4.2 Error Mapping

**Pattern:** `HarmoniaPlaybackServiceAdapter` (Integration Layer) maps `CoreError` → `PlaybackError`
at the boundary. AppState never sees `CoreError` directly.

```swift
// In HarmoniaPlaybackServiceAdapter (Integration Layer)
static func mapCoreError(_ error: CoreError) -> PlaybackError {
    switch error {
    case .notFound:         return .failedToOpenFile
    case .unsupported:      return .unsupportedFormat
    case .decodeError:      return .failedToDecode
    case .ioError:          return .failedToOpenFile
    case .invalidState:     return .invalidState
    case .invalidArgument:  return .invalidArgument
    }
}

// In AppState (Application Layer) — simplified fallback only
func mapToPlaybackError(_ error: Error) -> PlaybackError {
    if let playbackError = error as? PlaybackError { return playbackError }
    return .invalidState
}
```

**See:** [HarmoniaCore Error Models](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)

### 4.3 EQ Coordinator Placement and Signal Chain Wiring

Slice 9-K introduced three boundary nuances that warrant explicit clarification.

**(a) Why `EQCoordinator` lives in `Shared/Models/`, not `Shared/Services/`.**
`EQCoordinator` is a `@MainActor` `ObservableObject` that owns five `@Published`
properties (`isEnabled`, `bandGains`, `preamp`, `currentPresetName`,
`customPresets`). It is *state-bearing*, not a stateless utility — the same
reason `AppState` lives in `Shared/Models/`. By contrast, `EQPersistenceStore`
and `EQSchemaMigrator` are stateless and live in `Shared/Services/`. The
"Models vs Services" split inside the Application Layer is therefore:
observable state owners → Models, pure utilities and protocol implementations
→ Services. AppState holds a single `let eqCoordinator: EQCoordinator`
reference; views read EQ state via `appState.eqCoordinator.…` and AppState
itself has no EQ-specific `@Published` properties.

**(b) Why `HarmoniaEQAdapter` does not consume one of the three import slots.**
The Integration Layer rule "`import HarmoniaCore` is restricted to three
production files" still holds: `HarmoniaCoreProvider`,
`HarmoniaPlaybackServiceAdapter`, `HarmoniaTagReaderAdapter`.
`HarmoniaEQAdapter` lives in `Shared/Services/` for organisational reasons
(grouped with the other adapter wrappers) but is bound to the HarmoniaCore EQ
control surface via three closure hooks supplied by
`HarmoniaCoreProvider.makeEQService()`. Closures keep all `HarmoniaCore.*`
type references confined to the provider, so `HarmoniaEQAdapter` itself does
not `import HarmoniaCore`. This is what makes `EQServiceTests` able to verify
forward semantics without crossing the module boundary.

**(c) Same-instance constraint at `HarmoniaCoreProvider`.**
The `EQPort` instance constructed in `buildCore()` MUST be passed to BOTH the
`AudioOutputPort` adapter AND `DefaultPlaybackService`:

- `AudioOutputPort` splices the EQ node into the live audio chain during
  `configure(...)`.
- `DefaultPlaybackService` forwards the control surface
  (`setEQEnabled` / `setEQPreamp` / `setEQBandGains`) to the same node.

If two distinct `EQPort` instances were created (one for audio splice, one
for control), slider movements would mutate a node that is not in the audio
chain and have no audible effect. `HarmoniaCoreProvider` further caches the
constructed `HarmoniaCore.PlaybackService` in `sharedCore` so
`makeEQService()` reuses the same service instance created by
`makePlaybackService(isProUser:)`. AppState init calls `makePlaybackService`
first, so both factories operate on the same audio chain. See §6.3 for the
full constructor pattern.

### 4.4 Lyrics State and Tag Mapping

Slice 9-J introduced three boundary nuances that warrant explicit clarification.
This section is structured to parallel §4.3 so the EQ vs lyrics design
choices can be read side by side.

**(a) Why lyrics state lives directly on `AppState`, not in a parallel coordinator.**
Unlike EQ, which has five `@Published` properties plus preset / clamping /
custom-state / persistence logic that justify a dedicated `EQCoordinator`,
lyrics state in 9-J consists of only two `@Published` properties on
`AppState` — `showLyrics: Bool` and `lyricsResolution: LyricsResolution?` —
plus five mutator methods (`toggleLyrics`, `recheckLyrics`, `setLyricsSource`,
`setLyricsLanguage`, `setLyricsEncoding`). There is no preset model, no
clamping, and no in-memory aggregation across tracks; the only persisted
data is per-track `LyricsPreference` handled by `LyricsPreferenceStore`.
Pulling this into a `LyricsCoordinator` would add a layer without removing
state from `AppState`, so the design keeps it inline. If the lyrics surface
grows (multi-language editing, dynamic karaoke timing), splitting out a
coordinator becomes the same kind of refactor that produced `EQCoordinator`
and would follow §4.3(a)'s rule of thumb.

**(b) Why `LyricsService` does not wrap a HarmoniaCore port.**
`TagReaderService` wraps `HarmoniaCore.TagReaderPort` because reading audio
metadata is fundamentally a HarmoniaCore concern. `LyricsService` is
different on both inputs:

- USLT lyrics arrive on `Track.lyrics` already mapped from
  `TagBundle.lyrics` by `HarmoniaTagReaderAdapter` — by the time
  `LyricsService` sees them, they are pure Application Layer values.
- Sidecar `.lrc` files are file-system artefacts beside the audio file.
  Reading them is `Foundation`-only (`FileManager` + `Data` + encoding
  detection). HarmoniaCore offers no value here because there is no
  cross-platform decoding logic to share.

Consequently `LyricsService` lives entirely in the Application Layer and
`DefaultLyricsService` does not `import HarmoniaCore`. This also keeps the
"three import slots" rule from §4.3(b) intact — adding lyrics did not
require a new Integration Layer file.

**(c) `LyricsLanguageVariant` mapping at the boundary.**
`HarmoniaCore.LyricsLanguageVariant` and HP `LyricsLanguageVariant` are
intentionally parallel types with the same shape (`languageCode: String?` +
`text: String`). The mapping happens inside `HarmoniaTagReaderAdapter` —
already one of the three Integration Layer files allowed to
`import HarmoniaCore` — extending the existing `TagBundle → Track`
translation. AppState and views never see the HarmoniaCore type. This is
the same pattern as §4.1 TagReaderService usage; lyrics simply add a new
field to the mapping without changing the boundary topology.

### 4.5 NowPlaying Coordinator Placement and System Surface Wiring

Slice 9-L introduced two boundary nuances that warrant explicit clarification.

**(a) Why `NowPlayingCoordinator` lives in `Shared/Models/`, not
`Shared/Services/`.** Same reason as `EQCoordinator` (§4.3(a)) and `AppState`:
a `@MainActor` lifecycle participant owning Combine subscriptions and
holding AppState action closures via `[weak self]` capture is not a
stateless utility. Unlike `EQCoordinator`, `NowPlayingCoordinator` does
not declare any `@Published` properties — its responsibility is wiring
glue, not state ownership — but the same "lifecycle participant"
classification applies because publishers and closures are bound at
construction and live the AppState lifetime.

**(b) Why `MPNowPlayingAdapter` lives in `Shared/Services/` despite
being the only `import MediaPlayer` site.** Integration Layer placement
is by responsibility, not by HarmoniaCore involvement. `MPNowPlayingAdapter`
bridges the application-layer `NowPlayingService` protocol to a system
macOS surface (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`) — the
same shape of bridging that `HarmoniaPlaybackServiceAdapter` does for
HarmoniaCore. The Integration Layer therefore now hosts two flavours of
adapter: those that bridge to HarmoniaCore (3 files, the original `import
HarmoniaCore` slots) and those that bridge to system frameworks
(`MPNowPlayingAdapter` for MediaPlayer, future Linux equivalents to
MPRIS would slot in here). AppState and views never see the underlying
framework type.

**Why no `NowPlayingPort` in HarmoniaCore.** `MediaPlayer.framework` is
Apple-only. Linux has no equivalent — its system Now Playing surface is
MPRIS over D-Bus, with a fundamentally different shape. Pushing
`NowPlayingPort` into HarmoniaCore would either restrict it to Apple
platforms (defeating HarmoniaCore's cross-platform purpose) or force a
common abstraction over two unrelated APIs (defeating HarmoniaCore's
"Apple audio engine alignment" purpose). The application-layer
`NowPlayingService` protocol is the cross-platform abstraction; each
platform target supplies its own adapter conforming to it.

---

### 4.6 Sandbox and Sibling-File Access Boundary

The macOS App Sandbox blocks reads of files that are siblings of the
user-selected primary file (e.g. `Foo.lrc` next to `Foo.flac`) even when
the primary file's security-scoped bookmark is active —
`startAccessingSecurityScopedResource` does not extend access to siblings.
Apple's first-class mechanism for this topology is **Related Items**:
declare the sibling extension in `CFBundleDocumentTypes` with
`NSIsRelatedItemType=YES`, then read via `NSFileCoordinator` registered
with an `NSFilePresenter` whose `primaryPresentedItemURL` is the
user-selected primary file (Slice 9-M).

**Boundary placement.** The implementation lives entirely in the
Application Layer:

- `SiblingFilePresenter` (`Shared/Services/SiblingFilePresenter.swift`)
  is a minimal `NSFilePresenter` conformance — three properties and a
  constructor, no behavioural callbacks. Pure Foundation, no
  HarmoniaCore dependency.
- `LyricsService` calls `NSFileCoordinator.coordinate(readingItemAt:)`
  with a `SiblingFilePresenter` instance directly, on its own
  Foundation surface. It does **not** forward this call through any
  HarmoniaCore port.

**Why this does not violate the `import HarmoniaCore` restriction.**
Sandbox and Related Items are macOS platform I/O concerns, not audio
core concerns. HarmoniaCore is an Apple/Linux cross-platform audio
abstraction; pushing sandbox-specific file coordination into a Core
port would either restrict the port to Apple (defeating the cross-
platform contract) or force a degenerate abstraction over Linux's
unrelated file-access model. Foundation's `NSFileCoordinator` and
`NSFilePresenter` are platform APIs the Application Layer is allowed
to use directly, exactly the same way it uses `FileManager`,
`URLSession`, or `JSONDecoder`.

**Reuse plan.** `SiblingFilePresenter` is the single reuse point for
all future sibling-file features:

- Slice 10-C (Pro): cover-art `.jpg` / `.png` / `.bmp` siblings —
  each extension adds its own `CFBundleDocumentTypes` entry in its
  own slice; the presenter class is shared.
- Slice 10-D (Pro): lyrics write-back — same presenter, but uses
  `NSFileCoordinator.coordinate(writingItemAt:)`.
- CUE sheet slice (Pro): `.cue` siblings — same pattern.

**Note on `FileAccessPort` / `SandboxFileAccessAdapter`.** These exist
in HarmoniaCore but are unrelated to sibling-file Related Items. They
target a different I/O layer (seekable random-access decoder I/O, not
user-grant persistence) and are currently unwired. Cleanup deferred
to a dedicated HC slice.

---

## 5. Forbidden Dependencies (Examples)

These are examples of **explicitly forbidden** dependencies to keep the
architecture clean.

1. **Views importing HarmoniaCore-Swift**
   - ❌ `PlayerView` must not call `PlaybackService.play()` directly.
   - ✅ It should call `appState.play()` via `@EnvironmentObject`.

2. **AppState creating platform adapters**
   - ❌ `AppState` must not create `AVAudioEngineOutputAdapter`.
   - ✅ `CoreFactory` builds the service graph and injects `PlaybackService`.

3. **Views importing StoreKit or IAPManager**
   - ❌ SwiftUI views must not call StoreKit APIs directly.
   - ✅ They may observe exposed state such as `isProUnlocked` forwarded by `AppState`.

4. **Core services knowing about Free vs Pro**
   - ❌ `PlaybackService` must not perform product checks.
   - ✅ `AppState` decides which `PlaybackService` configuration to use based on
     `IAPManager.isProUnlocked`.

5. **Adapters accessing SwiftUI state**
   - ❌ `OSLogAdapter` must not depend on any view or `AppState`.
   - ✅ It only logs messages passed by services.

6. **AppState directly using audio Ports**
   - ❌ `AppState` must not use `DecoderPort`, `AudioOutputPort`, `ClockPort`, `LoggerPort`, or `TagReaderPort`.
   - ✅ `AppState` uses `TagReaderService` (application-level abstraction) for metadata reading.
     `HarmoniaTagReaderAdapter` (Integration Layer) wraps `TagReaderPort`.

7. **Views containing drag-and-drop business logic**
   - ❌ `PlaylistView` must not validate URLs or call `load(urls:)` directly from a drop closure.
   - ✅ It should call `appState.handleFileDrop(urls:)` which delegates to `FileDropService`.

8. **AudioFileItem using FileRepresentation for import**
   - ❌ `FileRepresentation(importedContentType:)` gives a temporary file copy that is
     deleted after the callback, causing playback failures.
   - ✅ Use `ProxyRepresentation(exporting:importing:)` to receive the original file URL.

9. **Application Layer importing MediaPlayer**
   - ❌ `NowPlayingCoordinator` must not call `MPNowPlayingInfoCenter`
     directly.
   - ✅ It calls methods on `NowPlayingService`, whose production
     implementation `MPNowPlayingAdapter` (Integration Layer) is the
     only file that imports `MediaPlayer`.

---

## 6. Boundary Examples

### 6.1 UI -> AppState

```swift
struct PlayerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack {
            PlaylistView()
            TransportControlsView(
                isPlaying: appState.playbackState == .playing,
                onPlay: { Task { await appState.play() } },
                onPause: { Task { await appState.pause() } },
                onStop: { Task { await appState.stop() } }
            )
        }
    }
}
```

- `PlayerView` has **no knowledge** of `PlaybackService` or `DecoderPort`.
- It only talks to `AppState`.

### 6.2 AppState -> CoreFactory -> Services

```swift
@MainActor
final class AppState: ObservableObject {
    let playbackService: PlaybackService
    let tagReaderService: TagReaderService

    init(iapManager: IAPManager, provider: CoreServiceProviding, ...) {
        let featureFlags = CoreFeatureFlags(iapManager: iapManager)
        let coreFactory = CoreFactory(featureFlags: featureFlags, provider: provider)
        self.playbackService = coreFactory.makePlaybackService()
        self.tagReaderService = coreFactory.makeTagReaderService()
    }

    func play() async {
        do {
            try await playbackService.play()
            playbackState = .playing
        } catch {
            let mapped = mapToPlaybackError(error)
            playbackState = .error(mapped)
            lastError = mapped
        }
    }
}
```

**Note:** AppState is split across multiple files:
- `AppState.swift` — properties, init, persistence
- `AppState+Playlist.swift` — playlist operations, management, undo/redo
- `AppState+Playback.swift` — transport controls, track selection
- `AppState+Navigation.swift` — next/previous, trackDidFinishPlaying
- `AppState+M3U8.swift` — M3U8 import/export

- `AppState` does not know **how** services are built, only that they conform to their interfaces.
- `AppState` uses `TagReaderService`, not `TagReaderPort` directly.

### 6.3 CoreFactory -> HarmoniaCoreProvider -> HarmoniaCore-Swift

`CoreFactory` delegates to a `CoreServiceProviding` implementation. It does not
construct adapters directly:

```swift
struct CoreFactory {
    let featureFlags: CoreFeatureFlags
    private let provider: CoreServiceProviding

    func makePlaybackService() -> PlaybackService {
        let isProUser = featureFlags.supportsFLAC
        return provider.makePlaybackService(isProUser: isProUser)
    }

    func makeTagReaderService() -> TagReaderService {
        return provider.makeTagReaderService()
    }

    func makeLyricsService() -> LyricsService {
        return provider.makeLyricsService()
    }

    func makeNowPlayingService() -> NowPlayingService {
        return provider.makeNowPlayingService()
    }
}
```

`HarmoniaCoreProvider` (Integration Layer) is the only class that constructs
real HarmoniaCore adapters. It also caches the constructed
`HarmoniaCore.PlaybackService` so `makePlaybackService(isProUser:)` and
`makeEQService()` operate on the same audio chain (the EQ node injected at
construction time must be the node that EQ control surface mutates):

```swift
final class HarmoniaCoreProvider: CoreServiceProviding {

    private var sharedCore: HarmoniaCore.PlaybackService?

    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        let core = buildCore()
        self.sharedCore = core
        return HarmoniaPlaybackServiceAdapter(core: core)
    }

    func makeTagReaderService() -> TagReaderService {
        HarmoniaTagReaderAdapter(port: AVMetadataTagReaderAdapter())
    }

    func makeLyricsService() -> LyricsService {
        // Pure Application Layer — no HarmoniaCore type to bind, so no
        // closure-binding pattern is needed (unlike makeEQService below).
        // See §4.4(b) for the rationale.
        DefaultLyricsService()
    }

    func makeEQService() -> EQService {
        // Closure binding: HarmoniaEQAdapter does not import HarmoniaCore.
        let core = sharedCore ?? buildCore()
        self.sharedCore = core
        return HarmoniaEQAdapter(
            setEnabled:   { core.setEQEnabled($0)   },
            setPreamp:    { core.setEQPreamp($0)    },
            setBandGains: { core.setEQBandGains($0) }
        )
    }

    func makeNowPlayingService() -> NowPlayingService {
        // System surface adapter; does not bind to HarmoniaCore.
        return MPNowPlayingAdapter()
    }

    private func buildCore() -> HarmoniaCore.PlaybackService {
        let logger  = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "Playback")
        let clock   = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let eq      = AVAudioUnitEQAdapter()
        // The same `eq` instance is handed to both the audio output adapter
        // (which splices its node into the real signal chain during
        // configure) AND DefaultPlaybackService (which forwards the EQ
        // control surface). Sharing one instance is what makes
        // setEQEnabled / setEQPreamp / setEQBandGains audible — see §4.3(c).
        let audio   = AVAudioEngineOutputAdapter(logger: logger, eq: eq)
        return DefaultPlaybackService(
            decoder: decoder, audio: audio, clock: clock, logger: logger, eq: eq
        )
    }
}
```

- All platform-specific details are contained here.
- The rest of the app only sees `PlaybackService`, `TagReaderService`,
  `EQService`, and `NowPlayingService` interfaces.
- The `eq` instance must be constructed **before** `audio` so the audio
  adapter can adopt it during initialisation. Reversing the order would
  compile but leave the audio chain without an EQ node.

---

## 7. Testing Strategy and Boundaries

The module boundaries strongly influence how tests should be written.

1. **UI Layer**
   - Tested with SwiftUI snapshot tests or view inspection.
   - Use mocked `AppState`.

2. **Application Layer**
   - Tested with unit tests using mocked `PlaybackService`, `TagReaderService`, and `IAPManager`.
   - Ensure business rules (e.g. format gating, playlist operations) are covered.

3. **Integration Layer**
   - Tested with integration tests that build real `CoreFactory` graphs but may
     still mock OS-level concerns when possible.

4. **Core Services and Adapters**
   - Primarily tested in the HarmoniaCore-Swift repository.
   - HarmoniaPlayer should rely on those tests and treat the package as a
     tested dependency.
   - **See:** [HarmoniaCore Testing Strategy](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md#testing-strategy)

---

## 8. Enforcement Checklist

When reviewing code, check these rules:

**UI Layer:**
- [ ] No imports of `HarmoniaCore`
- [ ] No direct calls to `PlaybackService`
- [ ] No access to Ports or Adapters
- [ ] Only depends on `AppState` and UI models

**Application Layer:**
- [ ] Uses `PlaybackService` interface only
- [ ] Uses `TagReaderService` for metadata reading (not `TagReaderPort`)
- [ ] Uses `EQService` for equaliser control (not direct EQ adapter / not `EQPort`)
- [ ] Uses `LyricsService` for lyrics resolution
- [ ] Uses `LyricsPreferenceStore` for per-track lyrics preference persistence (not direct UserDefaults access for `hp.lyrics.prefs.*`)
- [ ] No direct use of any HarmoniaCore Ports
- [ ] No AVFoundation, StoreKit, or OSLog imports
- [ ] Errors are mapped to `PlaybackError` (typed, no String payloads)
- [ ] Drag-and-drop URL validation goes through `FileDropService`
- [ ] `AudioFileItem.transferRepresentation` uses `ProxyRepresentation`, not `FileRepresentation` for import

**Integration Layer:**
- [ ] No SwiftUI imports
- [ ] No UI state manipulation
- [ ] Properly wires Ports to Adapters
- [ ] Contains all platform-specific code
- [ ] `CoreError` → `PlaybackError` mapping in `HarmoniaPlaybackServiceAdapter`
- [ ] `TagBundle` → `Track` mapping in `HarmoniaTagReaderAdapter` (no AVFoundation)

**HarmoniaCore-Swift Usage:**
- [ ] Services are obtained through `CoreFactory`
- [ ] No direct adapter instantiation outside Integration Layer
- [ ] Free vs Pro decisions made in AppState, not in Core

---

## 9. Migration Path (If Violations Exist)

If existing code violates these boundaries:

1. **Identify the violation** - Which layer depends on what it shouldn't?
2. **Create the proper interface** - Add to AppState or CoreFactory
3. **Inject the dependency** - Pass it through constructor
4. **Remove the direct dependency** - Replace with injected interface
5. **Add tests** - Ensure the refactored code works

Example:
```swift
// ❌ Before: View directly uses PlaybackService
struct PlayerView: View {
    let playbackService: PlaybackService
}

// ✅ After: View uses AppState
struct PlayerView: View {
    @EnvironmentObject var appState: AppState
}
```

---

## 10. Summary

- **Views** depend on AppState only.
- **AppState** depends on CoreFactory / IAPManager / PlaybackService interface / TagReaderService interface.
- **CoreFactory** depends on HarmoniaCore-Swift services, ports, and platform adapters.
- **Platform adapters** depend on Apple frameworks and HarmoniaCore-Swift port
  protocols.
- **Free vs Pro decisions** live in the app (AppState + IAPManager), not in the core engine.
- **TagReaderService** is an application-level abstraction that wraps HarmoniaCore's TagReaderPort.
- **EQService** is bound to the shared `HarmoniaCore.PlaybackService` EQ control
  surface via closure binding inside `HarmoniaCoreProvider`. `HarmoniaEQAdapter`
  itself does not import HarmoniaCore — the closure-binding pattern keeps the
  Core type surface confined to the provider.
- **LyricsService** is pure Application Layer — `DefaultLyricsService` does
  not import HarmoniaCore. USLT lyrics arrive on `Track.lyrics` already
  mapped by `HarmoniaTagReaderAdapter` from `TagBundle.lyrics`; sidecar
  `.lrc` files are read directly via `Foundation` with encoding detection.
  See §4.4 for the boundary rationale.
- **NowPlayingService** is pure Application Layer — `NowPlayingCoordinator`
  routes AppState publishers and action closures to `NowPlayingService`
  push and pull surfaces. The production implementation
  `MPNowPlayingAdapter` is the only file in HarmoniaPlayer that imports
  `MediaPlayer`. See §4.5 for the boundary rationale.

Any pull request that crosses these boundaries (e.g. a view that imports
HarmoniaCore-Swift, or an adapter that accesses SwiftUI, or AppState using audio Ports)
should be rejected or refactored to restore the module separation.

---

## 11. Cross-References

**HarmoniaCore Architecture:**
- [Ports & Adapters Pattern](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
- [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)

**HarmoniaPlayer Documentation:**
- [Architecture](architecture.md) - System-level architecture
- [API Reference](api_reference.md) - Interface definitions
- [Implementation Guide (Swift)](implementation_guide_swift.md) - Swift-specific patterns
- [Development Guide](development_guide.md) - Setup and guidelines