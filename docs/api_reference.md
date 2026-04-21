# HarmoniaPlayer API Reference

> Complete interface reference for HarmoniaPlayer.
> Generated from source code as of 2026-04-15.
>
> For architecture overview, see [Architecture](architecture.md).
> For dependency rules, see [Module Boundaries](module_boundary.md).

---

## 1. Data Models

### 1.1 Track

Audio track model representing a single audio file in the playlist.

```swift
struct Track: Identifiable, Equatable, Sendable, Codable {

    // Core
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkData: Data?

    // Extended tags (Group A)
    var albumArtist: String
    var composer: String
    var genre: String
    var year: Int?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var bpm: Int?

    // Replay Gain (Group B)
    var replayGainTrack: Double?
    var replayGainAlbum: Double?

    // Comment (Group C)
    var comment: String

    // Technical info (Group D)
    var bitrate: Int?           // kbps
    var sampleRate: Double?     // Hz
    var channels: Int?
    var fileSize: Int?          // bytes
    var fileFormat: String      // e.g. "MP3", "AAC"

    // Playback statistics (Group E — reserved, no UI yet)
    var playCount: Int
    var lastPlayedAt: Date?
    var rating: Double?

    // Metadata version (matches TagBundle.currentSchemaVersion)
    var metadataVersion: Int

    // Runtime-only (not persisted via Codable)
    var isAccessible: Bool      // false if file missing or in Trash
    var originalPath: String    // path at encode time, for Trash detection

    // Sort helpers (nil maps to -1 for SwiftUI Table Comparable requirement)
    var sortYear: Int
    var sortTrackNumber: Int
    var sortDiscNumber: Int
    var sortBpm: Int
    var sortBitrate: Int
    var sortSampleRate: Double
    var sortChannels: Int
    var sortFileSize: Int

    // Initializers
    init(url: URL, title: String, artist: String = "", album: String = "",
         duration: TimeInterval = 0, artworkData: Data? = nil, ...)
    init(url: URL)  // derives title from filename
}
```

Persistence: encoded with URL bookmark (`minimalBookmark`) for file access across launches. Decoding resolves bookmark, then urlPath, then legacy URL key.

### 1.2 Playlist

```swift
enum PlaylistSortKey: String, Equatable, Sendable, Codable {
    case none
    case title, artist, album, duration
    case albumArtist, composer, genre, year
    case trackNumber, discNumber, bpm
    case bitrate, sampleRate, channels, fileSize, fileFormat
}

struct Playlist: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var name: String
    var tracks: [Track]
    var sortKey: PlaylistSortKey = .none
    var sortAscending: Bool = true
    var insertionOrder: [Track.ID] = []

    var isEmpty: Bool { tracks.isEmpty }
    var count: Int    { tracks.count }
}
```

### 1.3 PlaybackState

```swift
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(PlaybackError)
}
```

### 1.4 PlaybackError

Typed error codes with no String payloads. View layer maps each case to a localised message.

```swift
enum PlaybackError: Error, Equatable, Sendable {
    case unsupportedFormat
    case failedToOpenFile
    case failedToDecode
    case outputError
    case invalidState
    case invalidArgument
}
```

### 1.5 RepeatMode

```swift
enum RepeatMode: String, Equatable, Sendable, Codable {
    case off
    case all
    case one
}
```

### 1.6 ShuffleMode

```swift
typealias ShuffleMode = Bool

extension ShuffleMode {
    static let off: ShuffleMode = false
    static let on: ShuffleMode = true
}
```

### 1.7 ReplayGainMode

```swift
enum ReplayGainMode: String, CaseIterable, Codable {
    case off
    case track
    case album
}
```

### 1.8 ViewPreferences

```swift
enum LayoutPreset: String, CaseIterable, Equatable, Sendable {
    case compact
    case standard
    case waveformFocused
}

struct ViewPreferences: Equatable, Sendable {
    var isWaveformVisible: Bool
    var isPlaylistVisible: Bool
    var layoutPreset: LayoutPreset

    static let defaultPreferences: ViewPreferences
}
```

### 1.9 AudioFileItem

Transferable type for drag-and-drop. Uses `ProxyRepresentation` (not `FileRepresentation`) to receive original file URLs.

```swift
struct AudioFileItem: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation
}
```

### 1.10 CoreFeatureFlags

Derived from `IAPManager.isProUnlocked`. Determines which formats and features are available.

```swift
struct CoreFeatureFlags: Sendable {
    let supportsMP3: Bool               // always true
    let supportsAAC: Bool               // always true
    let supportsALAC: Bool              // always true
    let supportsWAV: Bool               // always true
    let supportsAIFF: Bool              // always true
    let supportsFLAC: Bool              // Pro only
    let supportsDSD: Bool               // Pro only
    let supportsGaplessPlayback: Bool   // Pro only
    let supportsMetadataEditing: Bool   // Pro only
    let supportsBitPerfectOutput: Bool  // Pro only

    init(isPro: Bool)
    init(iapManager: IAPManager)
}
```

---

## 2. Error Types

### 2.1 PlaybackError

See [1.4 PlaybackError](#14-playbackerror).

### 2.2 IAPError

```swift
enum IAPError: Error, Equatable {
    case productNotFound
    case verificationFailed
    case userCancelled
    case purchaseFailed(String)
    case notAvailable
}
```

### 2.3 ExtendedAttributeError

```swift
enum ExtendedAttributeError: Error, LocalizedError {
    case plistSerializationFailed(Error)
    case writeFailed(Int32)
    case removeFailed(Int32)
}
```

---

## 3. AppState

Central application state. `@MainActor`, `ObservableObject`.

Split across 5 files: `AppState.swift` (properties, init, persistence), `AppState+Playlist.swift`, `AppState+Playback.swift`, `AppState+Navigation.swift`, `AppState+M3U8.swift`.

### 3.1 Initialization

```swift
init(
    iapManager: IAPManager,
    provider: CoreServiceProviding,
    userDefaults: UserDefaults = .standard,
    undoManager: UndoManager? = nil
)
```

Wiring flow: `IAPManager` → `CoreFeatureFlags` → `CoreFactory` → Services.

### 3.2 Services (injected)

| Property | Type | Description |
|----------|------|-------------|
| `playbackService` | `PlaybackService` | Audio playback |
| `tagReaderService` | `TagReaderService` | Metadata reading |
| `fileDropService` | `FileDropService` | URL validation + directory expansion |

### 3.3 Published Properties

#### IAP / Feature State

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `isProUnlocked` | `Bool` | read | Pro features unlocked |
| `featureFlags` | `CoreFeatureFlags` | read | Tier-specific capabilities |

#### Playlist State

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `playlists` | `[Playlist]` | read | All playlists |
| `activePlaylistIndex` | `Int` | read/write | Currently visible playlist |
| `playlist` | `Playlist` | computed | `playlists[activePlaylistIndex]` |
| `currentTrack` | `Track?` | read | Currently selected/playing track |
| `selectedTrackIDs` | `Set<Track.ID>` | read/write | Multi-selection in PlaylistView |

#### Playback State

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `playbackState` | `PlaybackState` | read | Current playback state |
| `playingPlaylistID` | `Playlist.ID?` | read | Playlist owning the playing track |
| `currentTime` | `TimeInterval` | read | Current position in seconds |
| `duration` | `TimeInterval` | read | Track duration in seconds |

#### Error / Alert State

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `lastError` | `PlaybackError?` | read | Most recent error |
| `lastErrorDetail` | `String?` | read | One-line diagnostic summary in format `"<errorCode>: <path-or-noTrack>"`; set alongside `lastError` |
| `failedTrackName` | `String?` | read | Display name of failed track |
| `showFileNotFoundAlert` | `Bool` | read/write | File-not-found alert binding |
| `skippedInaccessibleNames` | `[String]` | read/write | Tracks skipped during auto-play |
| `skippedDuplicateURLs` | `[URL]` | read/write | Duplicates skipped during load |
| `skippedImportURLs` | `[URL]` | read/write | Files skipped during M3U8 import |
| `skippedUnsupportedURLs` | `[URL]` | read/write | Unsupported formats skipped during load |

#### Blocking Operation

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `isPerformingBlockingOperation` | `Bool` | read | True during batch load/import |

#### UI State

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `viewPreferences` | `ViewPreferences` | read/write | Layout preferences |
| `fileInfoTrack` | `Track?` | read/write | One-shot signal requesting File Info window to open; ContentView observes and resets to nil |
| `showPaywall` | `Bool` | read/write | Paywall sheet binding (v0.1: hidden) |
| `paywallDismissedThisSession` | `Bool` | read/write | Session-only skip flag |

#### Settings

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `allowDuplicateTracks` | `Bool` | read/write | Allow duplicate URLs in playlist |
| `volume` | `Float` | read/write | Output volume 0.0–1.0 |
| `selectedLanguage` | `String` | read/write | BCP-47 tag or "system" |
| `repeatMode` | `RepeatMode` | read | off/all/one |
| `isShuffled` | `ShuffleMode` | read | off/on |
| `replayGainMode` | `ReplayGainMode` | read/write | off/track/album |

#### Format Classification (static)

| Property | Type | Description |
|----------|------|-------------|
| `freeFormats` | `Set<String>` | `["mp3", "aac", "m4a", "wav", "aiff", "alac"]` |
| `proOnlyFormats` | `Set<String>` | `["flac", "dsf", "dff"]` |
| `allowedFormats` | `Set<String>` (computed) | v0.1: `freeFormats`. v0.2: includes Pro check |

#### Other

| Property | Type | Description |
|----------|------|-------------|
| `undoManager` | `UndoManager` | Injected; `levelsOfUndo = 10` |
| `languageBundle` | `Bundle` | Resolved at launch for `NSLocalizedString` |
| `pendingSeekTime` | `TimeInterval` | Seek position buffered while stopped/paused |
| `lastPlayedTrackID` | `Track.ID?` | Last successfully played track ID |
| `shuffleQueue` | `[Track.ID]` | Pre-shuffled order |
| `shuffleQueueIndex` | `Int` | Current position in shuffle queue |
| `pollingTask` | `Task<Void, Never>?` | Polling loop task for playback state |
| `saveBatchSize` | `Int` (static) | Incremental save interval during batch load (5) |

### 3.4 Methods — Playlist Operations (`AppState+Playlist.swift`)

| Method | Description |
|--------|-------------|
| `handleFileDrop(urls:) async` | Validates via FileDropService, then calls `load(urls:)` |
| `load(urls:) async` | Adds tracks; sub-batch save every 5; format gate via `allowedFormats` |
| `clearPlaylist()` | Removes all tracks, clears undo stack |
| `removeTrack(_:)` | Removes single track by ID, registers undo |
| `moveTrack(fromOffsets:toOffset:)` | Reorders tracks, registers undo |
| `playNext(_:)` | Moves track to position after currentTrack |
| `applySort(_:key:ascending:)` | Applies column sort to playlist |
| `restoreInsertionOrder()` | Restores original insertion order |
| `newPlaylist(name:)` | Creates new playlist tab |
| `renamePlaylist(at:name:)` | Renames playlist at index |
| `deletePlaylist(at:)` | Deletes playlist at index; auto-inserts if last |
| `switchPlaylist(to:)` | Switches active tab without affecting playback |
| `undo()` | Calls `undoManager.undo()` |
| `redo()` | Calls `undoManager.redo()` |
| `canUndo: Bool` | Whether undo stack has actions |
| `canRedo: Bool` | Whether redo stack has actions |

### 3.5 Methods — Playback (`AppState+Playback.swift`)

| Method | Description |
|--------|-------------|
| `play() async` | Resumes playback from current position |
| `pause() async` | Pauses playback, preserves position |
| `stop() async` | Stops playback, resets position to 0 |
| `seek(to:) async` | Seeks to absolute position in seconds |
| `setVolume(_:) async` | Sets output volume 0.0–1.0 |
| `play(trackID:) async` | Loads and plays a specific track by ID |
| `cycleRepeatMode()` | Cycles off → all → one → off |
| `toggleShuffle()` | Toggles shuffle on/off, rebuilds queue |
| `buildShuffleQueue(startingWith:)` | Rebuilds shuffle queue |
| `mapToPlaybackError(_:) -> PlaybackError` | Fallback error mapping |
| `applyReplayGainVolume(for:requiresActivePlayback:) async` | Applies ReplayGain adjustment to volume |

### 3.6 Methods — Navigation (`AppState+Navigation.swift`)

| Method | Description |
|--------|-------------|
| `playNextTrack() async` | Plays next track (respects shuffle/repeat) |
| `playPreviousTrack() async` | Plays previous track (respects shuffle/repeat) |
| `trackDidFinishPlaying() async` | Called by polling loop on natural completion |
| `switchMiniPlayerPlaylist(to:) async` | Switches playlist from Mini Player |

### 3.7 Methods — M3U8 (`AppState+M3U8.swift`)

| Method | Description |
|--------|-------------|
| `writeExport(to:pathStyle:) throws` | Exports active playlist to M3U8 file |
| `importPlaylist(from:) async` | Imports M3U8 into new playlist tab; format gate + sub-batch save |

### 3.8 Methods — Main File (`AppState.swift`)

| Method | Description |
|--------|-------------|
| `saveState()` | Persists playlists, settings to UserDefaults |
| `restoreState()` | Restores state from UserDefaults; triggers metadata refresh |
| `displayName(for:) -> String` | Returns "Title - Artist" or filename |
| `clearLastError()` | Clears lastError, lastErrorDetail, failedTrackName, showFileNotFoundAlert, skippedInaccessibleNames |
| `showFileInfo(trackID:)` | Sets fileInfoTrack to signal ContentView to open File Info WindowGroup; no-op if ID not in active playlist |
| `showPaywallIfNeeded() -> Bool` | Sets showPaywall if Free tier; returns true if blocked |
| `purchasePro() async throws` | Initiates purchase via IAPManager |
| `refreshEntitlements() async` | Refreshes Pro status from App Store |

---

## 4. Service Protocols

### 4.1 PlaybackService

```swift
protocol PlaybackService: AnyObject {
    func load(url: URL) async throws
    func play() async throws
    func pause() async
    func stop() async
    func seek(to seconds: TimeInterval) async throws
    func currentTime() async -> TimeInterval
    func duration() async -> TimeInterval
    func setVolume(_ volume: Float) async
    var state: PlaybackState { get }
}
```

Implementations: `HarmoniaPlaybackServiceAdapter` (production), `FakePlaybackService` (test).

### 4.2 TagReaderService

```swift
protocol TagReaderService: AnyObject {
    func readMetadata(for url: URL) async throws -> Track
    var currentSchemaVersion: Int { get }
}
```

Implementations: `HarmoniaTagReaderAdapter` (production), `FakeTagReaderService` (test).

### 4.3 IAPManager

```swift
protocol IAPManager: AnyObject {
    var isProUnlocked: Bool { get }
    func refreshEntitlements() async
    func purchasePro() async throws  // throws IAPError
}
```

Implementations: `StoreKitIAPManager` (production), `FreeTierIAPManager` (stub), `MockIAPManager` (test).

### 4.4 CoreServiceProviding

```swift
protocol CoreServiceProviding: AnyObject {
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReaderService() -> TagReaderService
}
```

Implementations: `HarmoniaCoreProvider` (production), `FakeCoreProvider` (test).

---

## 5. Application Services

### 5.1 CoreFactory

Constructs services from `CoreServiceProviding` with `CoreFeatureFlags`.

```swift
struct CoreFactory {
    init(featureFlags: CoreFeatureFlags, provider: CoreServiceProviding)
    func makePlaybackService() -> PlaybackService
    func makeTagReaderService() -> TagReaderService
}
```

### 5.2 FileDropService

Validates drag-and-drop URLs. Recursively expands directories into audio files.

```swift
struct FileDropService {
    func validate(_ urls: [URL]) -> [URL]
}
```

Criteria: `isFileURL` + `UTType.conforms(to: .audio)`. Directories enumerated recursively (hidden files skipped).

### 5.3 M3U8Service

Pure value type for M3U8 serialisation and parsing. No I/O.

```swift
enum M3U8PathStyle {
    case absolute
    case relative(to: URL)
}

struct M3U8Service {
    func export(playlist: Playlist, pathStyle: M3U8PathStyle) -> String
    func parse(m3u8: String, baseURL: URL?) -> [URL]
}
```

### 5.4 ExtendedAttributeService

Reads/writes `kMDItemWhereFroms` extended attribute via Darwin xattr APIs.

```swift
struct ExtendedAttributeService {
    static let whereFromsKey: String  // "com.apple.metadata:kMDItemWhereFroms"
    func readWhereFroms(url: URL) -> [String]
    func writeWhereFroms(_ sources: [String], url: URL) throws
    func clearWhereFroms(url: URL) throws
}
```

### 5.5 ErrorReportService

**Location:** `Shared/Services/ErrorReportService.swift`

**Purpose:** Application Layer pure struct. Builds a `mailto:` URL for the
"Report Issue" button in the playback-error alert. No I/O — only URL
construction. No `import HarmoniaCore`.

```swift
struct ErrorReportService {
    static let reportEmail = "harmonia.audio.project+harmonia_player@gmail.com"
    static let subjectLine = "[HarmoniaPlayer] Error Report"

    static func buildMailtoURL(
        detail: String,
        appVersion: String,
        osVersion: String
    ) -> URL?
}
```

The caller (`ContentView`) is responsible for reading runtime versions
(`Bundle.main` / `ProcessInfo`) and invoking `NSWorkspace.shared.open(_:)`.
This split keeps `ErrorReportService` itself free of side effects and
trivially unit-testable.

---

## 6. Integration Layer

These 3 files are the **only** production files allowed to `import HarmoniaCore`.

### 6.1 HarmoniaCoreProvider

Constructs real HarmoniaCore services with AVFoundation adapters.

```swift
final class HarmoniaCoreProvider: CoreServiceProviding {
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReaderService() -> TagReaderService
}
```

### 6.2 HarmoniaPlaybackServiceAdapter

Wraps HarmoniaCore `DefaultPlaybackService`. Maps `CoreError` to `PlaybackError`.

```swift
final class HarmoniaPlaybackServiceAdapter: PlaybackService {
    // All PlaybackService protocol methods
    static func mapCoreError(_ error: CoreError) -> PlaybackError
}
```

Error mapping:

| CoreError | PlaybackError |
|-----------|--------------|
| `.notFound` | `.failedToOpenFile` |
| `.unsupported` | `.unsupportedFormat` |
| `.decodeError` | `.failedToDecode` |
| `.ioError` | `.failedToOpenFile` |
| `.invalidState` | `.invalidState` |
| `.invalidArgument` | `.invalidArgument` |

### 6.3 HarmoniaTagReaderAdapter

Wraps HarmoniaCore `TagReaderPort`. Pure `TagBundle` to `Track` mapping. No AVFoundation.

```swift
final class HarmoniaTagReaderAdapter: TagReaderService {
    func readMetadata(for url: URL) async throws -> Track
    var currentSchemaVersion: Int  // forwarded from TagBundle.currentSchemaVersion
}
```

---

## 7. Notification Names

```swift
extension Notification.Name {
    static let openFilePicker         // "harmoniaPlayer.openFilePicker"
    static let renameActivePlaylist   // "harmoniaPlayer.renameActivePlaylist"
    static let bringMainWindowToFront // "harmoniaPlayer.bringMainWindowToFront"
}
```

---

## 8. Persistence

Persisted via `UserDefaults` with `hp.` prefix keys.

| Key | Type | Persisted by |
|-----|------|-------------|
| `hp.playlists` | `[Playlist]` (JSON) | `saveState()` |
| `hp.activePlaylistIndex` | `Int` | `saveState()` |
| `hp.allowDuplicateTracks` | `Bool` | `saveState()` |
| `hp.volume` | `Float` | `saveState()` |
| `hp.selectedLanguage` | `String` | `saveState()` + Combine sink |
| `hp.repeatMode` | `RepeatMode` (JSON) | `saveState()` |
| `hp.isShuffled` | `Bool` | `saveState()` |
| `hp.replayGainMode` | `String` | `saveState()` + Combine sink |
| `hp.isProUnlocked` | `Bool` | `StoreKitIAPManager` (didSet) |

Not persisted: `isPerformingBlockingOperation`, `showPaywall`, `paywallDismissedThisSession`, `shuffleQueue`, `currentTrack`, `playbackState`.

---

## 9. Module Boundaries Summary

```
Views -> AppState (only)
AppState -> PlaybackService, TagReaderService, CoreFactory, IAPManager (protocols)
CoreFactory -> CoreServiceProviding -> HarmoniaCore (via Integration Layer)
Integration Layer -> HarmoniaCore ports + adapters (import HarmoniaCore)
```

`import HarmoniaCore` restricted to: `HarmoniaCoreProvider.swift`, `HarmoniaPlaybackServiceAdapter.swift`, `HarmoniaTagReaderAdapter.swift`.

See [Module Boundaries](module_boundary.md) for complete rules.

---

## 10. Cross-References

- [Architecture](architecture.md)
- [Module Boundaries](module_boundary.md)
- [Implementation Guide (Swift)](implementation_guide_swift.md)
- [Development Guide](development_guide.md)
- [HarmoniaCore Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [HarmoniaCore Services](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
- [HarmoniaCore Models](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)