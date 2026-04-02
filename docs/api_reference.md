# HarmoniaPlayer API Reference

> This document defines the **application-facing API** for HarmoniaPlayer.
>
> It specifies the interfaces, types, and contracts that application code uses,
> without implementation details.

---

## 1. Scope

This API reference covers:

- **AppState** - Central application state interface
- **PlaybackService** - Audio playback interface (from HarmoniaCore)
- **IAPManager** - In-app purchase management
- **CoreFactory** - Service construction interface
- **UI Models** - Data types used across the application

**Cross-References:**
- [HarmoniaCore Services](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md) - Core audio service contracts
- [HarmoniaCore Ports](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md) - Port interfaces
- [Implementation Guide (Swift)](implementation_guide_swift.md) - Platform-specific implementation patterns

---

## 2. UI Models

### 2.1 PlaybackState

```swift
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
}
```

**Note:** Errors are handled through exceptions, not through state.

### 2.2 PlaybackError

```swift
enum PlaybackError: Error, Equatable {
    case unsupportedFormat(String)
    case fileNotFound(URL)
    case decodingFailed(String)
    case outputFailed(String)
    case coreError(String)
}
```

### 2.3 Track

```swift
struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    var artworkURL: URL?
}
```

### 2.4 Playlist

```swift
struct Playlist: Identifiable, Equatable {
    let id: UUID
    var name: String
    var tracks: [Track]
    
    var isEmpty: Bool { tracks.isEmpty }
}
```

### 2.5 ViewPreferences

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

Central application state observable by SwiftUI views.

```swift
@MainActor
final class AppState: ObservableObject {
    // MARK: - Observable State
    @Published private(set) var playbackState: PlaybackState
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentTime: TimeInterval
    @Published private(set) var duration: TimeInterval
    @Published private(set) var playlists: [Playlist]
    @Published var activePlaylistIndex: Int
    var playlist: Playlist { playlists[activePlaylistIndex] }
    @Published var viewPreferences: ViewPreferences
    @Published private(set) var lastError: PlaybackError?
    @Published private(set) var isProUnlocked: Bool
    @Published private(set) var repeatMode: RepeatMode
    @Published private(set) var isShuffled: ShuffleMode
    @Published var volume: Float
    @Published var allowDuplicateTracks: Bool

    // MARK: - UndoManager
    /// Injected at init for testability. Production uses UndoManager().
    /// levelsOfUndo = 10: retains 10 most recent track operations.
    /// Scope: load / removeTrack / moveTrack only.
    /// Cleared automatically on playlist context change.
    let undoManager: UndoManager

    // MARK: - Init
    init(
        iapManager: IAPManager,
        provider: CoreServiceProviding,
        userDefaults: UserDefaults = .standard,
        undoManager: UndoManager? = nil   // nil → creates UndoManager() inside @MainActor body
    )

    // MARK: - Playlist Management
    func load(urls: [URL]) async
    func clearPlaylist()
    func removeTrack(_ trackID: Track.ID)
    func moveTrack(fromOffsets: IndexSet, toOffset: Int)
    func newPlaylist(name: String)
    func renamePlaylist(at index: Int, name: String)
    func deletePlaylist(at index: Int)
    func playNext(_ trackID: Track.ID)

    // MARK: - Mini Player
    /// Stops playback, switches activePlaylistIndex, clears undo stack,
    /// then plays the first track in the new playlist.
    func switchMiniPlayerPlaylist(to index: Int) async

    // MARK: - Playback Control
    func play() async
    func play(trackID: Track.ID) async
    func pause() async
    func stop() async
    func seek(to seconds: TimeInterval) async
    func setVolume(_ volume: Float) async
    func playNextTrack() async
    func playPreviousTrack() async
    func cycleRepeatMode()
    func toggleShuffle()

    // MARK: - Persistence
    func saveState()
    func restoreState()

    // MARK: - File Info
    func showFileInfo(trackID: Track.ID)
}
```

**UndoManager scope:**
- ✅ `load(urls:)`, `removeTrack(_:)`, `moveTrack(fromOffsets:toOffset:)`
- ❌ All playback controls, volume, shuffle, repeat, playlist create/delete
- Stack is cleared (`removeAllActions()`) when: `clearPlaylist()`, `newPlaylist()`,
  `deletePlaylist()`, `switchMiniPlayerPlaylist()`, playlist tab switch

**Key Behaviors:**
- All async methods dispatch onto `@MainActor`
- Errors mapped to `PlaybackError` and published via `lastError`
- State updates trigger SwiftUI re-render automatically

**See:** [Implementation Guide (Swift)](implementation_guide_swift.md) for concrete implementation.

---

## 4. Service Interfaces

### 4.1 PlaybackService

```swift
protocol PlaybackService {
    // Load and prepare a track for playback
    func load(url: URL) throws
    
    // Start playback
    func play() throws
    
    // Pause playback
    func pause()
    
    // Stop playback and release resources
    func stop()
    
    // Seek to absolute time
    func seek(to seconds: TimeInterval) throws
    
    // Query playback position and duration
    func currentTime() -> TimeInterval
    func duration() -> TimeInterval
    
    // Current playback state
    var state: PlaybackState { get }
}
```

**Source:** [HarmoniaCore Services Spec](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)

**Key Behaviors:**
- All operations are synchronous
- `play()` starts from current position
- `pause()` preserves playback position
- `stop()` resets position to beginning

### 4.2 IAPManager

```swift
protocol IAPManager: AnyObject {
    var isProUser: Bool { get }
    
    func refreshEntitlements() async
    func purchasePro() async throws
}
```

**Responsibilities:**
- Manage Pro feature unlock state
- Handle purchase transactions
- Persist entitlement state

### 4.3 CoreFactory

```swift
protocol CoreFactory {
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReader() -> TagReaderPort
}
```

**Responsibilities:**
- Construct HarmoniaCore services
- Wire ports to platform adapters
- Apply product configuration (Free vs Pro)

---

## 5. Port Interfaces

### 5.1 TagReaderPort

```swift
protocol TagReaderPort {
    func readTags(from url: URL) throws -> [String: Any]
}
```

**Source:** [HarmoniaCore Ports Spec](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)

**Usage:** Metadata extraction during file import.

**Note:** TagReaderPort is the only port interface directly used by application layer. All other ports are used internally by HarmoniaCore services.

---

## 7. Usage Patterns

### 6.1 View Integration

```swift
struct PlayerView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack {
            PlaylistView()
            TransportControlsView(
                isPlaying: appState.playbackState == .playing,
                onPlay: { try? appState.play() },
                onPause: { appState.pause() }
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

### 6.3 Error Handling

```swift
do {
    try appState.play()
} catch let error as PlaybackError {
    showAlert(for: error)
}
```

---

## 8. Module Boundaries

**Allowed Dependencies:**

```
Views
  ↓ depend on
AppState (protocol)
  ↓ depend on
CoreFactory, IAPManager, PlaybackService (protocols)
  ↓ implemented by
HarmoniaCore-Swift
```

**Forbidden:**
- ❌ Views importing HarmoniaCore directly
- ❌ AppState constructing platform adapters
- ❌ Views accessing PlaybackService directly

**See:** [Module Boundaries](module_boundary.md) for complete rules.

---

## 9. Cross-References

**HarmoniaCore Specifications:**
- [Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md) - Ports & Adapters pattern
- [Ports](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md) - Port interface contracts
- [Services](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md) - Service behavior specifications
- [Models](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md) - Error types and data models

**HarmoniaPlayer Documentation:**
- [Architecture](architecture.md) - System architecture
- [Implementation Guide (Swift)](implementation_guide_swift.md) - Swift-specific implementation
- [Module Boundaries](module_boundary.md) - Dependency rules
- [Development Guide](development_guide.md) - Development setup

---

## 10. Version Compatibility

| HarmoniaCore | HarmoniaPlayer | API Version | Status |
|--------------|----------------|-------------|--------|
| v0.1 | v0.1 | 1.0 | Planning |

This API is designed to remain stable across HarmoniaPlayer versions. Breaking changes will be coordinated with HarmoniaCore updates.