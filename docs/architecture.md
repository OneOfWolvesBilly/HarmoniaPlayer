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

    * Ports
    * Services
    * Models
    * Adapters
  * Contains both the Swift and C++20 implementations and their shared specs.

HarmoniaPlayer never bypasses HarmoniaCore. All audio playback, decoding, clocking, and error behavior is delegated to HarmoniaCore implementations.

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

* `docs/harmoniaplayer-architecture-apple-swift.md`

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

The detailed architecture for the Linux / C++ implementation is described in:

* `docs/harmoniaplayer-architecture-linux-cpp.md`

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
      svcSwift[Core Services
(Swift)]
    end

    subgraph coreCpp[HarmoniaCore C++]
      svcCpp[Core Services
(C++20)]
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

## 5. Design Principles

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

## 6. Document Map

To keep the documentation focused and maintainable, platform-specific details are split into separate files.

**Naming note:** These documents live inside the HarmoniaPlayer repository, so references do not repeat the repository name in prose. The filenames themselves keep the `harmoniaplayer-` prefix to reduce confusion when you have multiple HarmoniaSuite repos checked out side-by-side.

* **This document** (`docs/architecture.md`)

  * High-level overview of HarmoniaPlayer.
  * Repository relationships and system context.

* **Apple / Swift Architecture**

  * `docs/harmoniaplayer-architecture-apple-swift.md`
  * Describes the SwiftUI-based implementation, AppState and ViewModels, integration with HarmoniaCore-Swift, and StoreKit integration.

* **Linux / C++ Architecture**

  * `docs/harmoniaplayer-architecture-linux-cpp.md`
  * Describes the Linux desktop implementation, ViewModels and controllers, integration with the HarmoniaCore C++ implementation, and audio stack adapters.

* **Product Specification (Apple / Swift)**

  * `docs/harmoniaplayer-product-spec-apple-swift.md`
  * Defines Free vs Pro features, platform matrix, and non-goals.

* **Module Boundaries (Apple / Swift)**

  * `docs/harmoniaplayer-module-boundary.md`
  * Defines allowed dependencies and module boundaries for the Swift implementation.

* **Application API Specification (Apple / Swift)**

  * `docs/harmoniaplayer-api-spec-apple-swift.md`
  * Defines AppState, services, and UI-facing models for the SwiftUI code.

Platform-specific documents follow the same documentation style as the HarmoniaCore specs to keep the overall suite consistent and predictable for contributors.
