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
   - `PlaybackService` and other high-level services.
   - Ports: `DecoderPort`, `AudioOutputPort`, `TagReaderPort`, `ClockPort`, `LoggerPort`.
5. **Platform Adapters (HarmoniaCore-Swift)**
   - `AVAssetReaderDecoderAdapter`
   - `AVAudioEngineOutputAdapter`
   - `MonotonicClockAdapter`
   - `OSLogAdapter`
   - Future Apple-specific adapters.

HarmoniaCore-Swift and its adapters live in a **separate package**. From the
HarmoniaPlayer perspective, they are external dependencies.

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
(PlaybackService, etc.)]
    adapters[Platform Adapters
(AV* / OSLog / Clock)]

    views --> app
    app --> integration
    integration --> services
    services --> adapters
```

### 3.2 Rules

1. **UI Layer** may depend on:
   - Application Layer (AppState, ViewModels, UI models).
   - Standard Apple frameworks (SwiftUI, Combine, Foundation) for rendering and binding.

   UI Layer **must not**:
   - Import HarmoniaCore-Swift directly.
   - Import or reference platform adapters.
   - Call `PlaybackService` or ports directly.

2. **Application Layer** may depend on:
   - HarmoniaPlayer UI models and ViewModels.
   - Integration Layer abstractions (`CoreFactory` interface, `IAPManager` interface).
   - Core Service interfaces (e.g. `PlaybackService`, `TagReaderService`) injected
     via constructor or environment.

   Application Layer **must not**:
   - Instantiate platform adapters directly.
   - Call AVFoundation APIs directly.
   - Import OSLog, StoreKit, or other Apple-specific frameworks, except through
     small, well-defined interfaces.

3. **Integration Layer** may depend on:
   - Core service interfaces and their concrete implementations.
   - HarmoniaCore-Swift ports and platform adapters.
   - Platform-specific frameworks required to wire services (e.g. StoreKit).

   Integration Layer **must not**:
   - Contain UI rendering logic (no SwiftUI views).
   - Manipulate SwiftUI layout or view state directly.

4. **Core Services (HarmoniaCore-Swift)** may depend on:
   - Ports (protocols) that abstract decoding, audio output, logging, and clocks.
   - Pure Swift utility types.

   Core Services **must not**:
   - Depend on SwiftUI, AppKit, UIKit, or any UI framework.
   - Depend on IAP or licensing logic.

5. **Platform Adapters (HarmoniaCore-Swift)** may depend on:
   - AVFoundation, AudioToolbox, OSLog, and other Apple-specific frameworks.
   - HarmoniaCore-Swift port protocols.

   Platform Adapters **must not**:
   - Import SwiftUI.
   - Know anything about `AppState` or ViewModels.
   - Embed business decisions about Free vs Pro.

---

## 4. Forbidden Dependencies (Examples)

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

---

## 5. Boundary Examples

### 5.1 UI -> AppState

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

### 5.2 AppState -> CoreFactory

```swift
final class AppState: ObservableObject {
    private let playbackService: PlaybackService

    init(factory: CoreFactory, iap: IAPManager) {
        if iap.isProUser {
            self.playbackService = factory.makeProPlaybackService()
        } else {
            self.playbackService = factory.makeFreePlaybackService()
        }
    }

    func play() {
        playbackService.play()
    }
}
```

- `AppState` does not know **how** `PlaybackService` is built, only that it
  conforms to the `PlaybackService` interface.

### 5.3 CoreFactory -> HarmoniaCore-Swift

```swift
struct CoreFactory {
    func makeFreePlaybackService() -> PlaybackService {
        let logger = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "Playback")
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let output = AVAudioEngineOutputAdapter(logger: logger)

        return DefaultPlaybackService(
            decoder: decoder,
            audioOutput: output,
            clock: clock,
            logger: logger
        )
    }
}
```

- All platform-specific details are contained here.
- The rest of the app only sees `PlaybackService`.

---

## 6. Testing Strategy and Boundaries

The module boundaries strongly influence how tests should be written.

1. **UI Layer**
   - Tested with SwiftUI snapshot tests or view inspection.
   - Use mocked `AppState` / ViewModels.

2. **Application Layer**
   - Tested with unit tests using mocked `PlaybackService`, `TagReaderService`,
     and `IAPManager`.
   - Ensure business rules (e.g. format gating, playlist operations) are covered.

3. **Integration Layer**
   - Tested with integration tests that build real `CoreFactory` graphs but may
     still mock OS-level concerns when possible.

4. **Core Services and Adapters**
   - Primarily tested in the HarmoniaCore-Swift repository.
   - HarmoniaPlayer should rely on those tests and treat the package as a
     tested dependency.

---

## 7. Summary

- Views depend on AppState / ViewModels only.
- AppState depends on CoreFactory / IAPManager / service interfaces.
- CoreFactory depends on HarmoniaCore-Swift services and platform adapters.
- Platform adapters depend on Apple frameworks and HarmoniaCore-Swift port
  protocols.
- Free vs Pro decisions live in the app, not in the core engine.

Any pull request that crosses these boundaries (e.g. a view that imports
HarmoniaCore-Swift, or an adapter that accesses SwiftUI) should be rejected or
refactored to restore the module separation.

