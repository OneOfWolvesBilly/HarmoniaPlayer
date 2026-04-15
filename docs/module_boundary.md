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

This document applies to the Apple / Swift implementation only. Linux / C++
UI implementations will have corresponding module boundary documents in their
own repositories.

---

## 2. High-Level Module List

At a high level, the codebase is divided into the following logical modules.

> Note: These are **conceptual modules**; their physical mapping to targets,
> frameworks, or directories can vary as long as the boundaries are respected.

1. **UI Layer (Views)**
   - SwiftUI views under `Shared/Views/` and platform-specific view wrappers.
2. **Application Layer (State & ViewModels)**
   - `AppState` (central observable state)
   - ViewModels (e.g. `PlaybackViewModel`)
   - UI-facing models (`Track`, `Playlist`, `ViewPreferences`, `AudioFileItem`, etc.)
   - App-layer service protocols (`PlaybackService`, `TagReaderService`,
     `TagWriterService`) — these are defined in the Application Layer so that
     `AppState` can depend on them without importing HarmoniaCore.
   - Application services: `FileDropService`, `ExtendedAttributeService`, `M3U8Service`
     (pure Swift utilities with no HarmoniaCore dependency).
3. **Integration Layer**
   - `CoreFactory` for constructing services via `CoreServiceProviding`.
   - `HarmoniaCoreProvider` — the production `CoreServiceProviding` implementation
     that builds real HarmoniaCore services.
   - Adapter wrappers that bridge HarmoniaCore ports to app-layer protocols:
     `HarmoniaPlaybackServiceAdapter`, `HarmoniaTagReaderAdapter`,
     `HarmoniaTagWriterAdapter`.
   - `IAPManager` (macOS-only Pro unlock handling via StoreKit 2).
   - **`import HarmoniaCore` is permitted only in Integration Layer files.**
4. **Core Services (HarmoniaCore-Swift)**
   - `PlaybackService` - High-level audio service
5. **Ports (HarmoniaCore-Swift)**
   - Abstract interfaces: `DecoderPort`, `AudioOutputPort`, `TagReaderPort`,
     `TagWriterPort`, `ClockPort`, `LoggerPort`, `FileAccessPort`
6. **Platform Adapters (HarmoniaCore-Swift)**
   - `AVAssetReaderDecoderAdapter`
   - `AVAudioEngineOutputAdapter`
   - `AVMetadataTagReaderAdapter`
   - `AVMutableMetadataTagWriterAdapter`
   - `MonotonicClockAdapter`
   - `OSLogAdapter`
   - `SandboxFileAccessAdapter`
   - Future Apple-specific adapters.

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
(AppState, ViewModels,
UI models)]
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
   - Application Layer (AppState, ViewModels, UI models).
   - Standard Apple frameworks (SwiftUI, Combine, Foundation) for rendering and binding.

   UI Layer **must not**:
   - Import HarmoniaCore-Swift directly.
   - Import or reference platform adapters.
   - Call `PlaybackService` or ports directly.
   - Access any audio-related code.

2. **Application Layer** may depend on:
   - HarmoniaPlayer UI models and ViewModels.
   - Integration Layer abstractions (`CoreFactory` interface, `IAPManager` interface).
   - App-layer service protocols (e.g. `PlaybackService`, `TagReaderService`,
     `TagWriterService`) injected via constructor or environment.

   Application Layer **must not**:
   - Import HarmoniaCore-Swift.
   - Instantiate platform adapters directly.
   - Call AVFoundation APIs directly.
   - Import OSLog, StoreKit, or other Apple-specific frameworks, except through
     small, well-defined interfaces.
   - Directly use HarmoniaCore Ports (DecoderPort, AudioOutputPort, TagReaderPort, etc.).
   - Use HarmoniaCore model types (e.g. `TagBundle`) directly.

3. **Integration Layer** may depend on:
   - Core service interfaces and their concrete implementations.
   - **All HarmoniaCore-Swift ports and platform adapters**.
   - Platform-specific frameworks required to wire services (e.g. StoreKit).

   Integration Layer **must not**:
   - Contain UI rendering logic (no SwiftUI views).
   - Manipulate SwiftUI layout or view state directly.
   - Expose HarmoniaCore Ports, Adapters, or model types to Application Layer.

4. **Core Services (HarmoniaCore-Swift)** may depend on:
   - Ports (protocols) that abstract decoding, audio output, logging, and clocks.
   - Pure Swift utility types.

   Core Services **must not**:
   - Depend on SwiftUI, AppKit, UIKit, or any UI framework.
   - Depend on IAP or licensing logic.
   - Know about Free vs Pro product variants.

5. **Platform Adapters (HarmoniaCore-Swift)** may depend on:
   - AVFoundation, AudioToolbox, OSLog, and other Apple-specific frameworks.
   - HarmoniaCore-Swift port protocols.

   Platform Adapters **must not**:
   - Import SwiftUI.
   - Know anything about `AppState` or ViewModels.
   - Embed business decisions about Free vs Pro.

---

## 4. Special Cases and Clarifications

### 4.1 App-Layer Service Protocols

**AppState uses app-layer service protocols (`PlaybackService`, `TagReaderService`,
`TagWriterService`), never HarmoniaCore ports or types directly.**

**Rationale:** The app-layer protocols are defined in the Application Layer using
app-layer types (e.g. `Track`). Integration Layer adapter wrappers
(`HarmoniaTagReaderAdapter`, `HarmoniaTagWriterAdapter`) handle the mapping
between app-layer types and HarmoniaCore types (e.g. `Track ↔ TagBundle`)
internally.

**Usage Pattern:**
```swift
@MainActor
final class AppState: ObservableObject {
    let playbackService: PlaybackService
    let tagReaderService: TagReaderService

    init(iapManager: IAPManager, provider: CoreServiceProviding) {
        let flags = CoreFeatureFlags(iapManager: iapManager)
        let factory = CoreFactory(flags: flags, provider: provider)
        self.playbackService = factory.makePlaybackService()
        self.tagReaderService = factory.makeTagReaderService()
    }
}
```

**Not allowed:**
```swift
// ❌ AppState must NOT use HarmoniaCore Ports directly
let tagReader: TagReaderPort = ...  // FORBIDDEN

// ❌ AppState must NOT use HarmoniaCore model types
let bundle: TagBundle = ...  // FORBIDDEN
```

### 4.2 Error Mapping

**Pattern:** Integration Layer adapter wrappers translate HarmoniaCore errors
to app-layer typed errors. No string payloads cross the module boundary.

```swift
// In HarmoniaPlaybackServiceAdapter (Integration Layer)
private func mapCoreError(_ error: CoreError) -> PlaybackError {
    switch error {
    case .notFound:
        return .invalidArgument
    case .unsupported:
        return .invalidState
    // ... typed mapping, no String payloads
    }
}
```

**See:** [HarmoniaCore Error Models](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)

---

## 5. Forbidden Dependencies (Examples)

These are examples of **explicitly forbidden** dependencies to keep the
architecture clean.

1. **Views importing HarmoniaCore-Swift**
   - ❌ `NowPlayingView` must not call `PlaybackService.play()` directly.
   - ✅ It should call `AppState.play()` or a ViewModel method.

2. **AppState creating platform adapters**
   - ❌ `AppState` must not create `AVAudioEngineOutputAdapter`.
   - ✅ `CoreFactory` builds the service graph and injects services.

3. **Views importing StoreKit or IAPManager**
   - ❌ SwiftUI views must not call StoreKit APIs directly.
   - ✅ They may observe exposed state such as `isProUnlocked` forwarded by `AppState`.

4. **Core services knowing about Free vs Pro**
   - ❌ `PlaybackService` must not perform product checks.
   - ✅ `AppState` gates Pro-only actions (e.g. format checks in `play(trackID:)`)
     based on `featureFlags` derived from `IAPManager`.

5. **Adapters accessing SwiftUI state**
   - ❌ `OSLogAdapter` must not depend on any view or `AppState`.
   - ✅ It only logs messages passed by services.

6. **Application Layer importing HarmoniaCore types**
   - ❌ `AppState` must not use `TagBundle`, `CoreError`, or any HarmoniaCore type.
   - ✅ Integration Layer adapter wrappers (e.g. `HarmoniaTagWriterAdapter`)
     handle `Track → TagBundle` mapping internally.

7. **Views containing drag-and-drop business logic**
   - ❌ `PlaylistView` must not validate URLs or call `load(urls:)` directly from a drop closure.
   - ✅ It should call `appState.handleFileDrop(urls:)` which delegates to `FileDropService`.

8. **AudioFileItem using FileRepresentation for import**
   - ❌ `FileRepresentation(importedContentType:)` gives a temporary file copy that is
     deleted after the callback, causing playback failures.
   - ✅ Use `ProxyRepresentation(exporting:importing:)` to receive the original file URL.

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
                onPlay: { appState.play() },
                onPause: { appState.pause() },
                onStop: { appState.stop() }
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

    init(iapManager: IAPManager, provider: CoreServiceProviding) {
        let flags = CoreFeatureFlags(iapManager: iapManager)
        let factory = CoreFactory(flags: flags, provider: provider)
        self.playbackService = factory.makePlaybackService()
        self.tagReaderService = factory.makeTagReaderService()
    }
}
```

- `AppState` does not know **how** services are built, only that they conform
  to app-layer protocols.
- `AppState` never imports HarmoniaCore.

### 6.3 CoreFactory -> HarmoniaCore-Swift

```swift
final class HarmoniaCoreProvider: CoreServiceProviding {
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter()
        let output = AVAudioEngineOutputAdapter()

        let coreService = DefaultPlaybackService(
            decoder: decoder,
            audioOutput: output,
            clock: clock
        )
        return HarmoniaPlaybackServiceAdapter(coreService: coreService)
    }

    func makeTagReaderService() -> TagReaderService {
        let tagReaderPort = AVMetadataTagReaderAdapter()
        return HarmoniaTagReaderAdapter(port: tagReaderPort)
    }
}
```

- All platform-specific details are contained here.
- Adapter wrappers (`HarmoniaPlaybackServiceAdapter`, `HarmoniaTagReaderAdapter`)
  bridge HarmoniaCore services to app-layer protocols.
- The rest of the app only sees `PlaybackService` and `TagReaderService` interfaces.

---

## 7. Testing Strategy and Boundaries

The module boundaries strongly influence how tests should be written.

1. **UI Layer**
   - Tested with SwiftUI snapshot tests or view inspection.
   - Use mocked `AppState` / ViewModels.

2. **Application Layer**
   - Tested with unit tests using fake services (`FakePlaybackService`,
     `FakeTagReaderService`, `FakeTagWriterService`) and `MockIAPManager`.
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
- [ ] No imports of `HarmoniaCore`
- [ ] Uses app-layer service protocols (`PlaybackService`, `TagReaderService`,
      `TagWriterService`) only
- [ ] No direct use of HarmoniaCore Ports or model types (`TagBundle`, `CoreError`)
- [ ] No AVFoundation, StoreKit, or OSLog imports
- [ ] Errors are typed (no string payloads across module boundary)
- [ ] Drag-and-drop URL validation goes through `FileDropService`
- [ ] `AudioFileItem.transferRepresentation` uses `ProxyRepresentation`, not `FileRepresentation` for import

**Integration Layer:**
- [ ] No SwiftUI imports
- [ ] No UI state manipulation
- [ ] Properly wires Ports to Adapters via adapter wrappers
- [ ] Contains all platform-specific code
- [ ] `import HarmoniaCore` only appears in this layer

**HarmoniaCore-Swift Usage:**
- [ ] Services are obtained through `CoreFactory` / `CoreServiceProviding`
- [ ] No direct adapter instantiation outside Integration Layer
- [ ] Free vs Pro decisions made in AppState via `featureFlags`, not in Core

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

- **Views** depend on AppState / ViewModels only.
- **AppState** depends on CoreFactory / IAPManager / app-layer service protocols.
- **CoreFactory** depends on HarmoniaCore-Swift services, ports, and platform adapters.
- **Platform adapters** depend on Apple frameworks and HarmoniaCore-Swift port
  protocols.
- **`import HarmoniaCore`** is restricted to Integration Layer files.
- **Free vs Pro decisions** live in `AppState` and `featureFlags`, not in the
  core engine.
- **No HarmoniaCore types** (e.g. `TagBundle`, `CoreError`) cross into the
  Application Layer; adapter wrappers handle all mapping.

Any pull request that crosses these boundaries (e.g. a view that imports
HarmoniaCore-Swift, or an adapter that accesses SwiftUI, or AppState using
HarmoniaCore types) should be rejected or refactored to restore the module
separation.

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