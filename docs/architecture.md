# HarmoniaPlayer Architecture

## 1. System Overview

**Harmonia Player** is a reference audio player product.

This repository, **HarmoniaPlayer**, contains the application codebase built on top of **HarmoniaCore**, a cross-platform audio framework that provides identical behavior on Apple (Swift) and Linux (C++20) platforms.

HarmoniaPlayer has two primary roles:

1. Provide a **practical, user-facing audio player** on each supported platform.
2. Act as a **reference implementation and parity harness** for validating HarmoniaCore behavior across platforms.

The application is intentionally kept modular so that additional platforms or UI technologies can be added without changing HarmoniaCore itself.

---

## 2. Repositories and Components

HarmoniaPlayer is designed to work together with the following repositories:

* **HarmoniaPlayer (this repository)**

  * Contains the application code and documentation for:

    * Apple / Swift implementation (macOS, iOS).
    * Linux / C++ implementation (desktop Linux).
  * Contains platform-specific architecture documents and product specifications.

* **HarmoniaCore-Swift**

  * Swift Package providing audio services for Apple platforms.
  * Implements the HarmoniaCore specification using AVFoundation and the Apple audio stack.

* **HarmoniaCore**

  * Main specification and core implementation repository.
  * Provides the cross-platform architecture and contracts for:

    * Ports (DecoderPort, AudioOutputPort, TagReaderPort, ClockPort, LoggerPort, FileAccessPort, TagWriterPort)
    * Services (PlaybackService)
    * Models (Track metadata, Error types)
    * Adapters (AVFoundation, OSLog, etc.)
  * Contains both the Swift and C++20 implementations and their shared specs.

**Important:** HarmoniaPlayer never bypasses HarmoniaCore. All audio playback, decoding, clocking, and error behavior is delegated to HarmoniaCore implementations.

**See HarmoniaCore Specs:**
- [Architecture Overview](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
- [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)

---

## 3. Platform Targets

HarmoniaPlayer currently targets two platform families.

### 3.1 Apple / Swift

* Platforms:

  * macOS 13+ (Free / Pro variants)
  * iOS 16+ (Free)
* Technologies:

  * Swift, SwiftUI
  * HarmoniaCore-Swift (Swift Package Manager)
  * AVFoundation, CoreAudio
  * StoreKit 2 (macOS Pro IAP)
* Architecture:

  * Single shared SwiftUI codebase for macOS and iOS.
  * App-level state and ViewModels in Swift.
  * Integration layer constructs HarmoniaCore-Swift services and wires them into the app (CoreFactory, IAPManager).

The detailed architecture for the Apple / Swift implementation is described in:

* `docs/api_spec_apple_swift.md`
* `docs/module_boundary.md`

### 3.2 Linux / C++

* Platforms:

  * Desktop Linux distributions (exact support matrix TBD).
* Technologies:

  * C++20
  * HarmoniaCore C++ implementation
  * PipeWire / ALSA audio stack
  * Desktop UI toolkit (Qt / GTK / other, chosen per implementation).
* Architecture:

  * Desktop UI (windows, menus, playlist views).
  * ViewModel and application layer in C++.
  * Integration layer constructs HarmoniaCore C++ services for Linux.

The detailed architecture for the Linux / C++ implementation will be described in:

* `docs/harmoniaplayer-architecture-linux-cpp.md` (future)

---

## 4. High-Level Context (C4 Level 1)

At the highest level, HarmoniaPlayer consumes HarmoniaCore services and presents them through a platform-native UI.

```mermaid
flowchart LR
    user[User / Listener]

    subgraph player[HarmoniaPlayer]
      appApple[Apple / Swift App
(macOS / iOS)]
      appLinux[Linux / C++ App]
    end

    subgraph coreSwift[HarmoniaCore-Swift]
      svcSwift[PlaybackService
+ Ports + Adapters]
    end

    subgraph coreCpp[HarmoniaCore C++]
      svcCpp[PlaybackService
+ Ports + Adapters]
    end

    fs[(Local File System
(Audio, artwork, lyrics))]
    audioApple[(Apple Audio Stack)]
    audioLinux[(Linux Audio Stack
(PipeWire / ALSA))]

    user --> appApple
    user --> appLinux

    appApple --> svcSwift
    appLinux --> svcCpp

    svcSwift --> fs
    svcCpp --> fs

    svcSwift --> audioApple
    svcCpp --> audioLinux
```

The **contract** between HarmoniaPlayer and HarmoniaCore is defined entirely in HarmoniaCore specs (ports, services, error behavior). HarmoniaPlayer code is responsible for:

* UI and interaction design.
* Application state and workflows (playlists, views, product variants).
* Platform-specific integration (file pickers, IAP, window lifecycle).

---

## 5. Detailed Architecture (C4 Level 2) - Apple / Swift

```mermaid
flowchart TB
    subgraph player[HarmoniaPlayer Application]
      subgraph ui[UI Layer]
        views[SwiftUI Views
(NowPlayingView, PlaylistView, SettingsView)]
      end

      subgraph appLayer[Application Layer]
        appState[AppState
(@MainActor ObservableObject)]
        viewModels[ViewModels
(PlaybackViewModel, etc.)]
      end

      subgraph integration[Integration Layer]
        coreFactory[CoreFactory
(constructs Core services)]
        iap[IAPManager
(Pro unlock, macOS only)]
      end
    end

    subgraph coreSwift[HarmoniaCore-Swift Package]
      service[PlaybackService
(DefaultPlaybackService)]
      ports[Ports
(DecoderPort, AudioOutputPort,
TagReaderPort, ClockPort, LoggerPort,
FileAccessPort, TagWriterPort)]
      adapters[Apple Adapters
(AVAssetReaderDecoderAdapter,
AVAudioEngineOutputAdapter,
AVMetadataTagReaderAdapter,
MonotonicClockAdapter,
OSLogAdapter,
SandboxFileAccessAdapter)]
    end

    fs[(File System)]
    audioStack[(Apple Audio Stack
CoreAudio / AVAudioEngine)]

    views --> viewModels
    viewModels --> appState

    appState --> coreFactory
    appState --> iap

    coreFactory --> service
    coreFactory -.creates.-> ports

    service --> ports
    ports --> adapters

    adapters --> fs
    adapters --> audioStack
```

### Layer Responsibilities

**UI Layer (Views):**
- SwiftUI views that render the interface
- **May depend on:** AppState, ViewModels
- **Must not depend on:** HarmoniaCore-Swift directly, Ports, Adapters

**Application Layer (AppState, ViewModels):**
- Central observable state (`AppState`)
- Presentation logic (ViewModels)
- **May depend on:** PlaybackService interface, CoreFactory, IAPManager
- **Must not depend on:** Ports directly, Adapters, platform-specific APIs

**Integration Layer (CoreFactory, IAPManager):**
- Constructs HarmoniaCore-Swift services
- Wires Ports to Adapters
- Handles IAP state
- **May depend on:** HarmoniaCore-Swift (Services, Ports, Adapters), StoreKit
- **Must not depend on:** SwiftUI, UI state

**HarmoniaCore-Swift Package:**
- **Services:** High-level audio services (PlaybackService)
- **Ports:** Abstract interfaces (protocols) for audio operations
- **Adapters:** Platform-specific implementations of Ports

See [HarmoniaCore Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md) for detailed Port & Adapter pattern.

---

## 6. Key Architectural Patterns

### 6.1 Ports & Adapters (Hexagonal Architecture)

HarmoniaPlayer follows the same Ports & Adapters pattern as HarmoniaCore:

```
┌─────────────────────────────────┐
│   UI Layer (SwiftUI)            │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│   Application Layer             │
│   (AppState, ViewModels)        │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│   Integration Layer             │
│   (CoreFactory, IAPManager)     │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│   HarmoniaCore-Swift            │
│   Services → Ports → Adapters   │
└─────────────────────────────────┘
```

**Key Principles:**
1. **UI depends on AppState only** - No direct service access
2. **AppState uses Services** - Not Ports directly (except for metadata reading)
3. **CoreFactory constructs Services** - Wires Ports to Adapters
4. **Adapters contain platform code** - All AVFoundation, StoreKit, etc.

### 6.2 Dependency Injection

All services are injected via constructors:

```swift
@MainActor
final class AppState: ObservableObject {
    private let playbackService: PlaybackService
    private let iapManager: IAPManager
    
    init(factory: CoreFactory, iap: IAPManager) {
        self.iapManager = iap
        self.playbackService = factory.makePlaybackService(
            isProUser: iap.isProUser
        )
    }
}
```

This enables:
- Testing with mocks
- Runtime configuration (Free vs Pro)
- Clear dependency graph

### 6.3 Synchronous Core, Async UI

**HarmoniaCore-Swift uses synchronous APIs:**
```swift
// Synchronous - blocking operations
try playbackService.load(url: url)
try playbackService.play()
let time = playbackService.currentTime()
```

**AppState wraps in async/await for UI:**
```swift
func play() {
    Task { @MainActor in
        do {
            try playbackService.play()
            playbackState = .playing
        } catch {
            handleError(error)
        }
    }
}
```

This separation ensures:
- UI remains responsive
- Core audio operations are predictable
- Error handling is explicit

---

## 7. Design Principles

HarmoniaPlayer follows the same underlying principles as HarmoniaCore:

1. **Ports & Adapters alignment**

   * HarmoniaPlayer does not embed audio logic.
   * All audio responsibilities are forwarded to HarmoniaCore implementations.

2. **Never break core contracts**

   * HarmoniaPlayer must respect the behavior defined by HarmoniaCore specs.
   * Any audio-related change must be coordinated with HarmoniaCore.

3. **Platform-native UI, shared behavior**

   * Each platform uses its native UI framework.
   * Behavior (playback flow, error categories, seek semantics) must remain consistent across platforms.

4. **Clear separation of concerns**

   * UI layer (views, windows) is kept separate from application logic and integration layers.
   * Integration layers are the only place that know how to construct HarmoniaCore services.

5. **Testable and verifiable**

   * HarmoniaPlayer should be testable through unit, integration, and parity tests.
   * Where possible, the same audio test corpus should be shared between Apple and Linux implementations.

---

## 8. Document Map

To keep the documentation focused and maintainable, platform-specific details are split into separate files.

* **This document** (`docs/architecture.md`)

  * High-level overview of HarmoniaPlayer.
  * Repository relationships and system context.
  * C4 Level 1 and Level 2 diagrams.

* **Application API Specification (Apple / Swift)**

  * `docs/api_reference.md`
  * Defines interface contracts for SwiftUI code.
  * `docs/implementation_guide_swift.md`
  * Provides Swift-specific implementation patterns.

* **Module Boundaries (Apple / Swift)**

  * `docs/module_boundary.md`
  * Defines allowed dependencies and module boundaries for the Swift implementation.

* **Development Guide**

  * `docs/development_guide.md`
  * Setup instructions, IAP integration, code style guidelines.

* **User Guide**

  * `docs/user_guide.md`
  * End-user documentation for using the app.

* **Documentation Strategy**

  * `docs/documentation_strategy.md`
  * Documentation organization and maintenance policy.

---

## 9. Cross-References to HarmoniaCore

For detailed specifications of the underlying audio framework:

**HarmoniaCore Main Repository:**
- [Architecture Overview](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [Adapters Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/02_adapters.md)
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
- [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
- [Models Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)

**HarmoniaCore-Swift Package:**
- [Package README](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift/blob/main/README.md)
- [Implementation Guides](https://github.com/OneOfWolvesBilly/HarmoniaCore/tree/main/docs/impl)

Platform-specific documents follow the same documentation style as the HarmoniaCore specs to keep the overall suite consistent and predictable for contributors.
