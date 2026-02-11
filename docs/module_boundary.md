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
   - UI-facing models (`Track`, `Playlist`, `ViewPreferences`, etc.).
3. **Integration Layer**
   - `CoreFactory` for constructing HarmoniaCore-Swift services.
   - `IAPManager` (macOS-only Pro unlock handling).
   - Any glue that wires services into the app.
4. **Core Services (HarmoniaCore-Swift)**
   - `PlaybackService` - High-level audio service
5. **Ports (HarmoniaCore-Swift)**
   - Abstract interfaces: `DecoderPort`, `AudioOutputPort`, `TagReaderPort`, `ClockPort`, `LoggerPort`, `FileAccessPort`, `TagWriterPort`
6. **Platform Adapters (HarmoniaCore-Swift)**
   - `AVAssetReaderDecoderAdapter`
   - `AVAudioEngineOutputAdapter`
   - `AVMetadataTagReaderAdapter`
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
(CoreFactory, IAPManager)]
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
   - **PlaybackService interface only** (not concrete implementations).
   - **TagReaderService interface** for metadata reading.

   Application Layer **must not**:
   - Instantiate platform adapters directly.
   - Call AVFoundation APIs directly.
   - Import OSLog, StoreKit, or other Apple-specific frameworks, except through
     small, well-defined interfaces.
   - Directly use HarmoniaCore Ports (DecoderPort, AudioOutputPort, TagReaderPort, etc.).

3. **Integration Layer** may depend on:
   - Core service interfaces and their concrete implementations.
   - **All HarmoniaCore-Swift ports and platform adapters**.
   - Platform-specific frameworks required to wire services (e.g. StoreKit).

   Integration Layer **must not**:
   - Contain UI rendering logic (no SwiftUI views).
   - Manipulate SwiftUI layout or view state directly.
   - Expose Ports or Adapters to Application Layer (except TagReaderPort).

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

### 4.1 TagReaderService Usage

**AppState uses TagReaderService (not TagReaderPort directly) for metadata reading.**

**Rationale:** Metadata reading is needed during file import to populate Track models.
TagReaderService is an application-level abstraction that wraps HarmoniaCore's TagReaderPort.

**Usage Pattern:**
```swift
// In AppState or a helper
@MainActor
final class AppState: ObservableObject {
    private let tagReaderService: TagReaderService
    
    init(factory: CoreFactory, iap: IAPManager) {
        self.tagReaderService = factory.makeTagReaderService()
        // ...
    }
    
    func loadFiles(urls: [URL]) {
        for url in urls {
            do {
                let track = try tagReaderService.readMetadata(for: url)
                playlist.tracks.append(track)
            } catch {
                handleError(error)
            }
        }
    }
}
```

**Not allowed:**
```swift
// ❌ AppState must NOT use Ports directly
let tagReader: TagReaderPort = factory.makeTagReader()  // FORBIDDEN
```

### 4.2 Error Mapping

**Pattern:** AppState translates HarmoniaCore errors to UI-friendly errors.

```swift
// In AppState
private func mapError(_ error: Error) -> PlaybackError {
    if let coreError = error as? CoreError {
        switch coreError {
        case .notFound(let msg):
            return .fileNotFound(URL(string: msg) ?? URL(fileURLWithPath: "/"))
        case .unsupported(let msg):
            return .unsupportedFormat(msg)
        default:
            return .coreError(coreError.description)
        }
    }
    return .coreError(error.localizedDescription)
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
   - ✅ `CoreFactory` builds the service graph and injects `PlaybackService`.

3. **Views importing StoreKit or IAPManager**
   - ❌ SwiftUI views must not call StoreKit APIs directly.
   - ✅ They may observe exposed state such as `isProUser` forwarded by `AppState`.

4. **Core services knowing about Free vs Pro**
   - ❌ `PlaybackService` must not perform product checks.
   - ✅ `AppState` decides which `PlaybackService` configuration to use based on
     `IAPManager.isProUser`.

5. **Adapters accessing SwiftUI state**
   - ❌ `OSLogAdapter` must not depend on any view or `AppState`.
   - ✅ It only logs messages passed by services.

6. **AppState directly using audio Ports**
   - ❌ `AppState` must not use `DecoderPort`, `AudioOutputPort`, `ClockPort`, or `LoggerPort`.
   - ✅ Exception: `TagReaderPort` is allowed for metadata reading only.

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
                onPlay: { 
                    do {
                        try appState.play()
                    } catch {
                        // Handle error in UI
                    }
                },
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
    private let playbackService: PlaybackService
    private let tagReaderService: TagReaderService

    init(factory: CoreFactory, iap: IAPManager) {
        // CoreFactory decides which services to create based on Pro status
        self.playbackService = factory.makePlaybackService(
            isProUser: iap.isProUser
        )
        self.tagReaderService = factory.makeTagReaderService()
    }

    func play() throws {
        try playbackService.play()
        playbackState = .playing
    }
    
    func loadFiles(urls: [URL]) {
        for url in urls {
            do {
                let track = try tagReaderService.readMetadata(for: url)
                playlist.tracks.append(track)
            } catch {
                handleError(error)
            }
        }
    }
}
```

- `AppState` does not know **how** services are built, only that they conform to their interfaces.
- `AppState` uses `TagReaderService`, not `TagReaderPort` directly.

### 6.3 CoreFactory -> HarmoniaCore-Swift

```swift
struct CoreFactory {
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        let logger = OSLogAdapter()
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let output = AVAudioEngineOutputAdapter(logger: logger)

        return DefaultPlaybackService(
            decoder: decoder,
            audio: output,
            clock: clock,
            logger: logger
        )
    }
    
    func makeTagReaderService() -> TagReaderService {
        let logger = OSLogAdapter()
        let tagReaderPort = AVMetadataTagReaderAdapter(logger: logger)
        return DefaultTagReaderService(tagReaderPort: tagReaderPort)
    }
}
```

- All platform-specific details are contained here.
- The rest of the app only sees `PlaybackService` and `TagReaderService` interfaces.

---

## 7. Testing Strategy and Boundaries

The module boundaries strongly influence how tests should be written.

1. **UI Layer**
   - Tested with SwiftUI snapshot tests or view inspection.
   - Use mocked `AppState` / ViewModels.

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
- [ ] Uses `TagReaderService` for metadata reading
- [ ] No direct use of HarmoniaCore Ports
- [ ] No AVFoundation, StoreKit, or OSLog imports
- [ ] Errors are mapped to UI-friendly types

**Integration Layer:**
- [ ] No SwiftUI imports
- [ ] No UI state manipulation
- [ ] Properly wires Ports to Adapters
- [ ] Contains all platform-specific code

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

- **Views** depend on AppState / ViewModels only.
- **AppState** depends on CoreFactory / IAPManager / PlaybackService interface / TagReaderService interface.
- **CoreFactory** depends on HarmoniaCore-Swift services, ports, and platform adapters.
- **Platform adapters** depend on Apple frameworks and HarmoniaCore-Swift port
  protocols.
- **Free vs Pro decisions** live in the app (AppState + IAPManager), not in the core engine.
- **TagReaderService** is an application-level abstraction that wraps HarmoniaCore's TagReaderPort.

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
