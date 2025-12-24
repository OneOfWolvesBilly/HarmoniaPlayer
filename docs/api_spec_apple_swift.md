# HarmoniaPlayer Application API Specification (Apple / Swift)

> This document defines the **application-facing API** for the Apple / Swift
> implementation of HarmoniaPlayer.
>
> It focuses on the interfaces and types that UI code and feature modules are
> expected to use, rather than the internal details of HarmoniaCore-Swift.

---

## 1. Scope

This API spec covers:

- The **AppState** interface exposed to SwiftUI views.
- The service interfaces consumed by AppState and ViewModels:
  - `PlaybackService`
  - `TagReaderService`
  - `IAPManager`
- The main UI-level models used across the app.

It does **not** describe:

- The internal implementation of HarmoniaCore-Swift services and ports.
- The internal data structures of C++ HarmoniaCore.
- Lower-level adapter APIs (AVFoundation, OSLog, etc.).

---

## 2. Core UI Models

These models live in the HarmoniaPlayer codebase (not in HarmoniaCore-Swift)
and are tailored for UI needs.

### 2.1 `PlaybackState`

```swift
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(PlaybackError)
}
```

### 2.2 `PlaybackError`

```swift
enum PlaybackError: Error, Equatable {
    case unsupportedFormat
    case failedToOpenFile
    case failedToDecode
    case outputError
    case coreError(String)
}
```

### 2.3 `Track`

```swift
struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL

    // Basic metadata (UI-level only; may be derived from HarmoniaCore tags)
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?

    // Optional artwork / extra info (future)
    var artworkURL: URL?
}
```

### 2.4 `Playlist`

```swift
struct Playlist: Identifiable, Equatable {
    let id: UUID
    var name: String
    var tracks: [Track]

    var isEmpty: Bool { tracks.isEmpty }
}
```

### 2.5 `ViewPreferences`

```swift
struct ViewPreferences: Equatable {
    var isWaveformVisible: Bool
    var isPlaylistVisible: Bool
    var layoutPreset: LayoutPreset
}

enum LayoutPreset: String, CaseIterable {
    case compact
    case standard
    case waveformFocused
}
```

---

## 3. AppState Interface

`AppState` is the central application state object exposed to SwiftUI via
`@EnvironmentObject`. UI code should depend on this API rather than directly
calling services.

### 3.1 Public API

```swift
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    @Published private(set) var playlist: Playlist = Playlist(
        id: UUID(),
        name: "Session",
        tracks: []
    )

    @Published var viewPreferences: ViewPreferences = ViewPreferences(
        isWaveformVisible: true,
        isPlaylistVisible: true,
        layoutPreset: .standard
    )

    @Published private(set) var lastError: PlaybackError?

    // Indicates whether Pro features are available in this runtime.
    @Published private(set) var isProUser: Bool = false

    // MARK: - Initialization

    init(factory: CoreFactory, iap: IAPManager) {
        // Wiring described in architecture / module-boundary docs
    }

    // MARK: - Playlist Management

    func load(urls: [URL])
    func clearPlaylist()
    func removeTrack(_ trackID: Track.ID)
    func moveTrack(fromOffsets: IndexSet, toOffset: Int)

    // MARK: - Playback Control

    func play()
    func play(trackID: Track.ID)
    func pause()
    func stop()
    func seek(to seconds: TimeInterval)

    // MARK: - UI Helpers

    func toggleWaveformVisibility()
    func togglePlaylistVisibility()
    func setLayoutPreset(_ preset: LayoutPreset)
}
```

### 3.2 Responsibilities

- Translate user actions into calls on `PlaybackService` and other services.
- Maintain published state observed by SwiftUI views.
- Enforce product rules (Free vs Pro) when loading tracks.
- Remain free of platform-specific APIs (AVFoundation, StoreKit, etc.).

---

## 4. Service Interfaces

The application layer depends on the following service interfaces. Concrete
implementations are provided either by HarmoniaCore-Swift or by app-specific
infrastructure (e.g. IAPManager).

### 4.1 `PlaybackService`

```swift
protocol PlaybackService {
    // Load and prepare a track for playback.
    func load(url: URL) async throws

    // Start playback. If playback is already running, this is a no-op.
    func play() async throws

    // Pause playback. Safe to call when already paused.
    func pause() async

    // Stop playback and release any underlying resources.
    func stop() async

    // Seek to an absolute time within the current track.
    func seek(to seconds: TimeInterval) async throws

    // Query current playback time and duration.
    func currentTime() async -> TimeInterval
    func duration() async -> TimeInterval

    // Query current state for debugging / UI.
    var state: PlaybackState { get }
}
```

### 4.2 `TagReaderService`

```swift
protocol TagReaderService {
    func readMetadata(for url: URL) async throws -> Track
}
```

- Returns a `Track` model populated with title/artist/album/duration when
  possible.
- Implementation may call into HarmoniaCore-Swift tag ports or OS metadata APIs.

### 4.3 `IAPManager`

```swift
protocol IAPManager: AnyObject {
    var isProUser: Bool { get }

    // Async startup to refresh purchase state.
    func refreshEntitlements() async

    // Start purchase flow for Pro.
    func purchasePro() async throws
}
```

- On macOS, this is backed by StoreKit 2.
- On iOS Free, a trivial implementation can always return `false` and throw for
  `purchasePro()`.

---

## 5. Integration API: CoreFactory

`CoreFactory` is responsible for constructing service graphs based on runtime
configuration (Free vs Pro, platform-specific options).

### 5.1 Interface

```swift
struct CoreFactory {
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReaderService() -> TagReaderService
}
```

### 5.2 Expected Behavior

- `makePlaybackService(isProUser:)` selects appropriate decoder / output
  configuration:

  - For Free:
    - Only standard formats (MP3, AAC, ALAC, WAV, AIFF).
  - Uses `AVAssetReaderDecoderAdapter`.

  - For Pro (macOS):
    - Extends support to FLAC/DSD via a Pro-capable decoder configuration.

- `makeTagReaderService()` may create a service using either HarmoniaCore-Swift
  tag ports or OS-level metadata APIs.

---

## 6. UI Usage Patterns

### 6.1 Consuming AppState in SwiftUI

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

### 6.2 Loading Files

```swift
func handleFileSelection(urls: [URL]) {
    appState.load(urls: urls)
}
```

The `load(urls:)` implementation is responsible for:

- Updating the playlist.
- Calling `TagReaderService` to enrich `Track` metadata.
- Enforcing Free vs Pro format rules.

---

## 7. Error Handling and Reporting

- All service methods that can fail return `async throws`.
- AppState catches errors and maps them into `PlaybackError` values.
- `lastError` is updated, and SwiftUI views may present alerts or banners
  based on that state.

Example pattern:

```swift
func play() {
    Task { @MainActor in
        do {
            try await playbackService.play()
            playbackState = .playing
        } catch {
            let mapped = map(error)
            playbackState = .error(mapped)
            lastError = mapped
        }
    }
}
```

---

## 8. Extensibility Guidelines

When adding new features:

1. Prefer to extend **AppState** or create a new ViewModel that wraps AppState,
   rather than calling services directly from views.
2. New services should be expressed as protocols and injected via `CoreFactory`
   or other integration points.
3. Avoid exposing HarmoniaCore-Swift types directly to the UI; wrap them in
   app-level models or abstractions.
4. Keep the API surface small and intentional; do not leak implementation
   details into public interfaces.

This API spec should be treated as a contract. Changes to these interfaces
should be deliberate and coordinated with updates to the architecture and
module-boundary documents.


## C4 Context (Apple / Swift implementation)

This architecture document describes HarmoniaPlayer when implemented as a
Swift / SwiftUI application on Apple platforms (macOS and iOS), using
HarmoniaCore-Swift as the audio engine. Linux / C++ UI implementations will
have their own architecture documents in their respective repositories.

### C4 Level 1 — System Context

```mermaid
flowchart LR
    user[User / Listener]

    subgraph player[HarmoniaPlayer (Apple / Swift)]
      ui[SwiftUI UI
(macOS / iOS)]
      appState[AppState & ViewModels]
    end

    subgraph coreSwift[HarmoniaCore-Swift]
      services[PlaybackService & other Core Services]
    end

    subgraph coreCpp[HarmoniaCore (Core Specs & C++ Impl)]
      coreSpec[Ports / Services / Models / Adapters]
    end

    fs[(Local File System
(Audio, artwork, lyrics))]
    audioStack[(Apple Audio Stack
(CoreAudio / AVAudioEngine))]
    os[(macOS / iOS Runtime)]

    user --> ui
    ui --> appState
    appState --> services
    services --> audioStack
    services --> fs

    coreSwift --> coreSpec
    coreSpec -.guides & contracts.- coreSwift

    ui --> os
    audioStack --> os
    fs --> os
```

### C4 Level 2 — Containers / Layers

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

    subgraph coreSwift[HarmoniaCore-Swift]
      services[PlaybackService,
TagReaderService, ...]
      ports[Ports
(DecoderPort, AudioOutputPort,
TagReaderPort, ClockPort, LoggerPort)]
      adapters[Apple Adapters
(AVAssetReaderDecoderAdapter,
AVAudioEngineOutputAdapter,
MonotonicClockAdapter,
OSLogAdapter)]
    end

    fs[(File System)]
    audioStack[(Apple Audio Stack)]

    views --> viewModels
    viewModels --> appState

    appState --> coreFactory
    appState --> iap

    coreFactory --> services

    services --> ports
    ports --> adapters

    adapters --> fs
    adapters --> audioStack
```

## Related Documents

For the Apple / Swift implementation of HarmoniaPlayer:

- `docs/harmoniaplayer-product-spec-apple-swift.md` — Product-level spec (macOS Free / macOS Pro / iOS Free, feature matrix, non-goals).
- `docs/harmoniaplayer-c4-apple-swift.md` — Full C4 model (C1/C2/C3/C4) for the Swift implementation.
- `docs/harmoniaplayer-module-boundary.md` — Formal module boundary and allowed dependencies.
- `docs/harmoniaplayer-api-spec-apple-swift.md` — Application-facing API (AppState, services, core models) for SwiftUI code.

