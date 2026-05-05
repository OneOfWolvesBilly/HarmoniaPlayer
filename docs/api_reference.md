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

    // Lyrics (Group F — Slice 9-J)
    // USLT embedded variants populated by HarmoniaTagReaderAdapter from
    // TagBundle.lyrics. nil when no USLT frames present. Sidecar `.lrc`
    // lyrics are NOT stored here; they are resolved at display time by
    // LyricsService.
    var lyrics: [LyricsLanguageVariant]?

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

### 1.11 EQBand

Static configuration of one band of the 10-band graphic EQ. Slice 9-K.

```swift
struct EQBand: Codable, Equatable, Sendable {
    let frequency: Float    // Centre frequency in Hz
    let defaultGain: Float  // Default gain in dB applied on reset to flat
}
```

User-editable per-band state lives in `EQBandState`; this struct only carries the immutable band layout.

### 1.12 EQBandState

Mutable per-band state stored in presets and in `EQCoordinator.bandGains`. Slice 9-K.

```swift
struct EQBandState: Codable, nonisolated Equatable, Sendable {
    var gain: Float    // Band gain in dB; range ±12 dB (clamped by EQCoordinator)
    var q: Float       // Q factor; 9-K uses fixed 0.7071 across bands
}
```

The `q` field is included for forward compatibility with future variable-Q designs; in 9-K it is informational only.

### 1.13 EQPreset

A named EQ configuration: 10 band states + preamp. Slice 9-K.

```swift
struct EQPreset: Codable, nonisolated Equatable, Sendable, Identifiable {
    let name: String          // Display name; built-in names are reserved
    let bands: [EQBandState]  // Exactly 10 entries, ordered low → high
    let preamp: Float         // Preamp gain in dB; range ±12 dB
    let isBuiltin: Bool       // true for built-in, false for user-saved

    var id: String { name }
}
```

Built-in presets have `isBuiltin = true` and live in `EQPresets.builtin`. Custom presets are persisted via `EQPersistenceStore` with `isBuiltin = false`.

### 1.14 EQPresets

Statically-defined built-in presets. Slice 9-K.

```swift
enum EQPresets {
    static let builtin: [EQPreset]  // 8 presets in display order
}
```

Built-in set: `Flat`, `Rock`, `Pop`, `Jazz`, `Classical`, `Vocal`, `Bass Boost`, `Treble Boost`. Every preset uses preamp 0 dB and Q 0.7071. Band order (low → high): 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz.

### 1.15 LyricsLanguageVariant

Application Layer representation of one language variant of embedded USLT lyrics. Mirrors `HarmoniaCore.LyricsLanguageVariant` but lives in the Application Layer so `Track` and `AppState` can use it without importing HarmoniaCore. Slice 9-J.

```swift
struct LyricsLanguageVariant: Codable, Equatable, Sendable {
    let languageCode: String?  // ISO 639-2 (e.g. "eng", "chi", "jpn"); nil when undeclared
    let text: String           // Raw lyrics text; not yet stripped of LRC timestamps

    init(languageCode: String?, text: String)
}
```

Mapping from `HarmoniaCore.LyricsLanguageVariant` happens inside `HarmoniaTagReaderAdapter` (Integration Layer). LRC timestamp stripping is performed at display time by `LyricsService.stripLRCTimestamps(_:)`.

### 1.16 LyricsSource

The source from which lyrics content is resolved. Slice 9-J.

```swift
enum LyricsSource: String, Codable, Sendable {
    case embedded  // USLT frame(s) in the audio file
    case lrc       // Sidecar `.lrc` file alongside the audio file
}
```

### 1.17 LyricsPreference

Per-track user preference for lyrics source, encoding, and language. Persisted via `LyricsPreferenceStore` (UserDefaults-backed). Slice 9-J.

```swift
struct LyricsPreference: Codable, Equatable {
    var source: LyricsSource     // .embedded or .lrc
    var encoding: String         // IANA charset name; "auto" = auto-detect
    var languageCode: String?    // ISO 639-2; nil = auto (locale match)
    var customPath: String?      // Reserved for v0.15 custom file selection; always nil in 9-J

    init(source: LyricsSource,
         encoding: String = "auto",
         languageCode: String? = nil,
         customPath: String? = nil)
}
```

Persistence key: `hp.lyrics.prefs.<absolute-file-path>` (see §8). The `customPath` field is latent in 9-J — present in the schema for forward compatibility but never written.

### 1.18 LyricsResolution

Result of a lyrics availability check and optional content resolution. Produced by `LyricsService.resolveAvailability(for:)`. Slice 9-J.

```swift
struct LyricsResolution {
    let hasAny: Bool                       // Drives lyrics-button visibility
    let currentSource: LyricsSource?       // nil when hasAny == false
    let availableSources: Set<LyricsSource>
    let availableLanguages: [String?]      // ISO 639-2 codes; nil entries for undeclared frames
    let currentLanguage: String?
    let content: String?                   // Lazy: nil until LyricsPanel opens

    static let none: LyricsResolution      // hasAny: false, all empty
}
```

**β strategy (9-J):** `resolveAvailability` fills everything except `content`, which is `nil` until the user opens `LyricsPanel`. At that point `resolveContent` is called and AppState stores the loaded content in an updated `LyricsResolution`. `hasAny` drives button visibility — checked synchronously on track load.

`currentLanguage` is `nil` when:
- source is `.lrc` (no language variants in 9-J), or
- source is `.embedded` with a single variant whose `languageCode` is `nil`.

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

### 2.4 LyricsServiceError

Slice 9-J. Thrown by `LyricsService.resolveContent(...)` when content cannot be obtained.

```swift
enum LyricsServiceError: Error {
    case noEmbeddedLyrics  // source == .embedded but no USLT frames present
    case sidecarNotFound   // source == .lrc but no `.lrc` file beside the audio
    case decodingFailed    // sidecar bytes could not be decoded with any encoding candidate
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
    undoManager: UndoManager? = nil,
    lyricsPreferenceStore: LyricsPreferenceStore? = nil,
    eqCoordinator: EQCoordinator? = nil
)
```

Wiring flow: `IAPManager` → `CoreFeatureFlags` → `CoreFactory` → Services. The injected `eqCoordinator` parameter (Slice 9-K) is for tests that need a pre-seeded coordinator; production builds the default from the same `provider`'s `EQService` and an `EQPersistenceStore` backed by the same `userDefaults` instance. The injected `lyricsPreferenceStore` parameter (Slice 9-J) is similarly for tests; production builds a `DefaultLyricsPreferenceStore` backed by the same `userDefaults`.

### 3.2 Services (injected)

| Property | Type | Description |
|----------|------|-------------|
| `playbackService` | `PlaybackService` | Audio playback |
| `tagReaderService` | `TagReaderService` | Metadata reading |
| `fileDropService` | `FileDropService` | URL validation + directory expansion |
| `lyricsService` | `LyricsService` | Resolves USLT + sidecar `.lrc` content; encoding detection; LRC timestamp stripping (Slice 9-J) |
| `lyricsPreferenceStore` | `LyricsPreferenceStore` | Per-track persistence of source / encoding / language preference (Slice 9-J) |
| `eqCoordinator` | `EQCoordinator` | Owns observable EQ state; views access EQ via `appState.eqCoordinator.…` (Slice 9-K) |
| `nowPlayingCoordinator` | `NowPlayingCoordinator` | Routes AppState publishers and action closures to the system Now Playing surface via `NowPlayingService` (Slice 9-L) |

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

#### Lyrics State (Slice 9-J)

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `showLyrics` | `Bool` | read/write | Whether the lyrics panel is visible. Toggled by `toggleLyrics()`. Default `false`. |
| `lyricsResolution` | `LyricsResolution?` | read/write | Lyrics availability + selected source/language for the current track. Recomputed when `currentTrack` changes; `lyricsResolution?.hasAny == true` drives lyrics-button visibility. |

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
| `toggleLyrics()` | Toggles `showLyrics`. Slice 9-J. |
| `recheckLyrics()` | Re-runs lyrics availability detection for `currentTrack`; refreshes `lyricsResolution`. Slice 9-J. |
| `setLyricsSource(_ source: LyricsSource)` | Switches active source (.embedded ↔ .lrc) for current track; persists choice via `LyricsPreferenceStore`. Slice 9-J. |
| `setLyricsLanguage(_ languageCode: String?)` | Switches active language for current track; no-op when source is not `.embedded`. Persists. Slice 9-J. |
| `setLyricsEncoding(_ encoding: String)` | Stores per-track encoding choice; persists. Slice 9-J. |

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

### 4.4 EQService

```swift
protocol EQService: AnyObject {
    func setEnabled(_ enabled: Bool)
    func setPreamp(_ db: Float)
    func setBandGains(_ gains: [Float])
}
```

Implementations: `HarmoniaEQAdapter` (production, closure-binding — does not
import HarmoniaCore), `FakeEQService` (test).

Slice 9-K. Sync, non-throwing, mirrors the underlying HarmoniaCore
PlaybackService EQ control surface (`setEQEnabled` / `setEQPreamp` /
`setEQBandGains`). Clamping (±12 dB band, ±12 dB preamp) is performed
downstream by `AVAudioUnitEQAdapter`.

### 4.5 LyricsService

```swift
protocol LyricsService: AnyObject {
    /// Fast synchronous check: which sources are available and what is the default.
    /// Does NOT read file content (only checks existence).
    func resolveAvailability(for track: Track) -> LyricsResolution

    /// Slow path: read actual content for the given source/language/encoding.
    /// - languageCode: ISO 639-2; nil uses first variant.
    /// - encodingName: IANA charset; nil or "auto" triggers auto-detection.
    func resolveContent(
        for track: Track,
        source: LyricsSource,
        languageCode: String?,
        encodingName: String?
    ) throws -> String

    /// Strips LRC-style timestamps and metadata headers from raw text.
    func stripLRCTimestamps(_ raw: String) -> String

    /// Auto-detects encoding using a fallback chain.
    func detectEncoding(of data: Data) -> String.Encoding
}
```

Implementations: `DefaultLyricsService` (production).

Slice 9-J. Pure Application Layer service — does not import HarmoniaCore. The production initializer takes `preferredLanguageCode: String` for testability; default is `Locale.current.language.languageCode?.identifier ?? ""`. `DefaultLyricsService` exposes two static helper constants for non-public Swift encodings: `gb18030` (Simplified Chinese) and `big5` (Traditional Chinese), constructed via `CFStringConvertEncodingToNSStringEncoding`. Throws `LyricsServiceError` (see §2.4) when content cannot be obtained.

### 4.6 LyricsPreferenceStore

```swift
protocol LyricsPreferenceStore: AnyObject {
    /// Returns the UserDefaults key for the given track.
    func key(for track: Track) -> String

    /// Loads the persisted preference, or nil if absent or unreadable.
    func load(for track: Track) -> LyricsPreference?

    /// Saves the preference. Failures (e.g. encoder errors) are silently ignored —
    /// preferences are best-effort and must not break playback.
    func save(_ pref: LyricsPreference, for track: Track)
}
```

Implementations: `DefaultLyricsPreferenceStore` (production).

Slice 9-J. UserDefaults-backed, keyed by absolute file path with optional `#track=<n>` suffix for CUE virtual tracks (latent in 9-J, activated v0.15). Preferences are shared across playlists — the same file in playlist A and playlist B uses the same preference. See §8 for the full key format.

### 4.7 NowPlayingService

```swift
protocol NowPlayingService: AnyObject {
    // Push (AppState → service)
    func updateCurrentTrack(_ track: Track?)
    func updatePlaybackState(_ state: PlaybackState, rate: Double)
    func updateElapsedTime(_ seconds: Double)
    func clear()

    // Pull (service → AppState, set by NowPlayingCoordinator)
    var onPlay: (() -> Void)? { get set }
    var onPause: (() -> Void)? { get set }
    var onTogglePlayPause: (() -> Void)? { get set }
    var onNext: (() -> Void)? { get set }
    var onPrevious: (() -> Void)? { get set }
    var onStop: (() -> Void)? { get set }
    var onSeek: ((Double) -> Void)? { get set }
}
```

Implementations: `MPNowPlayingAdapter` (production, see §6.5), `FakeNowPlayingService` (test).

Slice 9-L. Application Layer abstraction over the system Now Playing surface (Control Center widget, lock screen, AirPods, media keys, Siri). Push methods deliver metadata, state, and elapsed-time updates from `NowPlayingCoordinator` to whatever system implementation is bound. Pull-side closures are assigned by the coordinator at construction so user actions on the system widget reach AppState's action methods.

### 4.8 CoreServiceProviding

```swift
protocol CoreServiceProviding: AnyObject {
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReaderService() -> TagReaderService
    func makeLyricsService() -> LyricsService
    func makeEQService() -> EQService
    func makeNowPlayingService() -> NowPlayingService
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
    func makeLyricsService() -> LyricsService
    func makeEQService() -> EQService
    func makeNowPlayingService() -> NowPlayingService
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

### 5.6 EQPersistenceStore

**Location:** `Shared/Services/EQPersistenceStore.swift`

**Purpose:** UserDefaults-backed persistence for EQ state (enabled / preamp / band gains / current preset name / custom presets) with explicit schema versioning. Slice 9-K. `nonisolated final class`; safe to construct from any actor. Does not import HarmoniaCore.

```swift
/// Snapshot of all EQ state persisted to UserDefaults.
struct EQPersistedState: Codable, nonisolated Equatable, Sendable {
    var isEnabled: Bool
    var preamp: Float
    var bandGains: [Float]
    var currentPresetName: String?
    var customPresets: [EQPreset]

    nonisolated static let defaults: EQPersistedState
}

/// Current schema version this build of HarmoniaPlayer writes.
nonisolated let eqCurrentSchemaVersion: Int  // = 1 in 9-K

nonisolated final class EQPersistenceStore {
    init(defaults: UserDefaults = .standard)

    func save(_ state: EQPersistedState)
    func load() -> EQPersistedState
    func currentSchemaVersion() -> Int?  // nil on fresh install
}
```

`save(_:)` writes all keys atomically with the current schema version. `load()` returns `EQPersistedState.defaults` on fresh install (and stamps the schema version), otherwise decodes and migrates via `EQSchemaMigrator` to the current version. See §8 for the full key list.

### 5.7 EQSchemaMigrator

**Location:** `Shared/Services/EQSchemaMigrator.swift`

**Purpose:** Forward migration of EQ persisted state between schema versions. Slice 9-K. `nonisolated enum`; pure transformation, no I/O.

```swift
nonisolated enum EQSchemaMigrator {
    static func migrate(
        from fromVersion: Int,
        to toVersion: Int,
        state: EQPersistedState
    ) -> EQPersistedState
}
```

9-K ships only schema version 1, so the migrator currently only handles `fromVersion == toVersion` as identity; any non-matching `fromVersion` falls through to `EQPersistedState.defaults` rather than risking corruption. Future slices (e.g. v0.15 per-track EQ, v0.15/v0.2 user-adjustable Q) bump the version and add migration steps here.

### 5.8 EQCoordinator

**Location:** `Shared/Models/EQCoordinator.swift`

**Purpose:** `@MainActor` `ObservableObject` that owns all EQ-related observable state for the UI layer. Coordinates between `EQService` (the Application Layer view of HarmoniaCore's EQ control surface) and `EQPersistenceStore`. Slice 9-K. Lives in `Shared/Models/` (not `Services/`) because, like `AppState`, it is a state-bearing observable object rather than a stateless service. AppState holds a single `let eqCoordinator: EQCoordinator` and views read EQ state via `appState.eqCoordinator.…`; AppState itself has no EQ-specific `@Published` properties or methods.

```swift
@MainActor
final class EQCoordinator: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var bandGains: [Float]          // 10 entries, low → high
    @Published private(set) var preamp: Float               // dB, ±12
    @Published private(set) var currentPresetName: String?  // nil = custom state
    @Published private(set) var customPresets: [EQPreset]

    init(service: EQService, store: EQPersistenceStore)

    func setEnabled(_ enabled: Bool)
    func setBand(index: Int, gain: Float)        // clears currentPresetName
    func setPreamp(_ db: Float)                  // clears currentPresetName
    func selectPreset(_ name: String)            // built-in or custom
    func saveAsCustomPreset(name: String) throws // EQCoordinatorError.nameCollidesWithBuiltin
    func deleteCustomPreset(_ name: String)
}

enum EQCoordinatorError: Error {
    case nameCollidesWithBuiltin
}
```

**Clamping:** band gains and preamp are clamped to ±12 dB on assignment, mirroring the downstream clamp in `AVAudioUnitEQAdapter` so coordinator state and service state agree on what was stored.

**Custom-state semantics:** `currentPresetName` is `nil` whenever the live state does not match any saved preset. Both `setBand(index:gain:)` and `setPreamp(_:)` clear it, because `EQPreset` defines a preset as bands + preamp together — any change to either makes the live state diverge from the saved preset.

**Init side effect:** the constructor pushes the loaded state to the injected `EQService` (`setEnabled`, `setPreamp`, `setBandGains`) so the audio chain matches the coordinator's published state from t=0.

**Mutators side effects:** every public mutator forwards the resulting state to the injected `EQService` (where applicable) and persists via the injected `EQPersistenceStore`. Boundary behaviours: `setBand` is a silent no-op on out-of-bounds indices; `selectPreset` is a silent no-op when no preset matches the given name and otherwise sets `currentPresetName` to that name; `saveAsCustomPreset` replaces any existing custom preset with the same name and sets `currentPresetName` to the saved name; `deleteCustomPreset` silently rejects built-in names and clears `currentPresetName` when it matches the deleted preset.

**Xcode 26 beta workaround:** declared with `nonisolated deinit { }`. With module-level `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` the synthesised deinit on an inferred-MainActor class routes deallocation through `swift_task_deinitOnExecutorImpl`, which crashes in Xcode 26 beta during TaskLocal teardown. Methods stay on MainActor; only deinit drops down to the synchronous ARC path. The same pattern is applied to `HarmoniaEQAdapter`, `AppState`, and the test-side `FakeEQService`.

### 5.9 NowPlayingCoordinator

**Location:** `Shared/Models/NowPlayingCoordinator.swift`

**Purpose:** `@MainActor` class that owns all NowPlaying wiring for the UI / Application boundary with the system Now Playing surface. Slice 9-L. Subscribes to `AppState.$currentTrack` and `AppState.$playbackState`, routes the seven `NowPlayingService` pull-side callbacks to AppState action closures, and exposes `notifySeekCompleted(at:)` for direct AppState notification on successful seek (seek success is not derivable from `$playbackState`). Lives in `Shared/Models/` for the same reason `EQCoordinator` does — it is a lifecycle participant rather than a stateless service. Receives all dependencies via constructor closure injection and never holds an `AppState` reference.

```swift
@MainActor
final class NowPlayingCoordinator {

    init(
        service: NowPlayingService,
        currentTrackPublisher: AnyPublisher<Track?, Never>,
        playbackStatePublisher: AnyPublisher<PlaybackState, Never>,
        currentTimeProvider: @escaping @MainActor () -> TimeInterval,
        play: @escaping @MainActor () async -> Void,
        pause: @escaping @MainActor () async -> Void,
        stop: @escaping @MainActor () async -> Void,
        seek: @escaping @MainActor (TimeInterval) async -> Void,
        next: @escaping @MainActor () async -> Void,
        previous: @escaping @MainActor () async -> Void,
        togglePlayPause: @escaping @MainActor () async -> Void
    )

    func notifySeekCompleted(at seconds: TimeInterval)
}
```

**Push semantics:** on `currentTrack` non-nil push `updateCurrentTrack` then `updateElapsedTime(0)`; on nil call `clear()`. On every `playbackState` event push `updatePlaybackState(_:rate:)` (rate 1.0 playing / 0.0 otherwise) then `updateElapsedTime(currentTimeProvider())`; on `.stopped` also `clear()`.

**Pull semantics:** the seven service callbacks (`onPlay`, `onPause`, `onTogglePlayPause`, `onNext`, `onPrevious`, `onStop`, `onSeek`) are assigned in the coordinator's `init`, each wrapped in `Task { @MainActor in await … }` so the synchronous service callback signature can drive async AppState action closures.

**AppState ownership:** AppState declares `private(set) var nowPlayingCoordinator: NowPlayingCoordinator!` (rather than `let`) so the seven action closures can capture `[weak self]` after every other stored property is initialised. `EQCoordinator` uses `let` because it has no self-capture requirement; that contrast does not apply here.

---

## 6. Integration Layer

These files form the Integration Layer. Three of them are the **only** production files allowed to `import HarmoniaCore` (§6.1, §6.2, §6.3). `HarmoniaEQAdapter` (§6.4) is also placed in the Integration Layer but **does not `import HarmoniaCore` by design** — see §6.4. `MPNowPlayingAdapter` (§6.5) is also Integration Layer but imports the `MediaPlayer` framework instead of `HarmoniaCore`, because it bridges to a system-level macOS surface (Control Center widget, lock screen, AirPods, media keys) rather than to the audio core.

### 6.1 HarmoniaCoreProvider

Constructs real HarmoniaCore services with AVFoundation adapters. Caches the
constructed `HarmoniaCore.PlaybackService` in `sharedCore` so
`makePlaybackService(isProUser:)` and `makeEQService()` operate on the same
audio chain.

```swift
final class HarmoniaCoreProvider: CoreServiceProviding {
    private var sharedCore: HarmoniaCore.PlaybackService?

    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReaderService() -> TagReaderService
    func makeLyricsService() -> LyricsService    // returns DefaultLyricsService
    func makeEQService() -> EQService            // closure-binds against sharedCore
    func makeNowPlayingService() -> NowPlayingService    // returns MPNowPlayingAdapter
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

### 6.4 HarmoniaEQAdapter

Bridges the HarmoniaCore PlaybackService EQ control surface
(`setEQEnabled` / `setEQPreamp` / `setEQBandGains`) to `EQService` via three
closure hooks bound at construction time by `HarmoniaCoreProvider`. **Does
not `import HarmoniaCore`** — closures keep the Core type surface confined
to the provider, which lets `EQServiceTests` verify forward semantics
without crossing the module boundary.

```swift
final class HarmoniaEQAdapter: EQService {
    init(
        setEnabled:   @escaping (Bool)    -> Void,
        setPreamp:    @escaping (Float)   -> Void,
        setBandGains: @escaping ([Float]) -> Void
    )
    // EQService methods forward to the closures.
}
```

Closures are stored as plain `(_) -> Void` (not `@Sendable`). They inherit
MainActor isolation from `HarmoniaCoreProvider.makeEQService()` and capture
the non-Sendable `HarmoniaCore.PlaybackService` without crossing an isolation
boundary, so no Sendable warning is raised. The class declares an explicit
`nonisolated deinit { }` to sidestep the Xcode 26 beta
`swift_task_deinitOnExecutorImpl` TaskLocal teardown crash that fires when
the synthesised deinit on an inferred-MainActor class releases captured
closures. The same pattern is applied to `EQCoordinator`, `AppState`, and the
test-side `FakeEQService` — see §5.8 for the full rationale.

### 6.5 MPNowPlayingAdapter

Bridges `NowPlayingService` to `MPNowPlayingInfoCenter.default()` and `MPRemoteCommandCenter.shared()`. Slice 9-L. Sole `import MediaPlayer` site in HarmoniaPlayer. Constructed once at app launch via `HarmoniaCoreProvider.makeNowPlayingService()`; lives the process lifetime so Bluetooth / media-key / Siri commands work at any moment regardless of current playback state.

```swift
final class MPNowPlayingAdapter: NowPlayingService {
    init()
    // NowPlayingService protocol methods drive nowPlayingInfo and playbackState.
    // The seven supported MPRemoteCommand handlers are registered in init and
    // never unregistered.
}
```

**Pushed nowPlayingInfo keys:** `MPMediaItemPropertyTitle`, `MPMediaItemPropertyArtist`, `MPMediaItemPropertyAlbumTitle`, `MPMediaItemPropertyPlaybackDuration`, `MPMediaItemPropertyArtwork`, `MPNowPlayingInfoPropertyMediaType` (`.audio.rawValue`), `MPNowPlayingInfoPropertyPlaybackRate`, `MPNowPlayingInfoPropertyElapsedPlaybackTime`. `MPNowPlayingInfoCenter.playbackState` mirrors `PlaybackState` via a private mapping (`.playing` / `.paused` / `.stopped` / `.unknown` for `.idle` / `.loading` / `.error`).

**Artwork fallback:** `track.artworkData` is decoded to `NSImage` and wrapped in `MPMediaItemArtwork` using `boundsSize` + `requestHandler`. On nil or decode failure, falls back to `NSImage(named: NSImage.applicationIconName)`. If even the application icon cannot be obtained, the artwork key is skipped silently and the system shows a generic icon.

**Registered MPRemoteCommands:** `playCommand`, `pauseCommand`, `togglePlayPauseCommand`, `nextTrackCommand`, `previousTrackCommand`, `stopCommand`, `changePlaybackPositionCommand`. Each handler returns `.success` or `.commandFailed`.

**Disabled MPRemoteCommands** (so the system widget renders only buttons HarmoniaPlayer responds to): `skipForwardCommand`, `skipBackwardCommand`, `seekForwardCommand`, `seekBackwardCommand`, `changePlaybackRateCommand`, `changeRepeatModeCommand`, `changeShuffleModeCommand`, `enableLanguageOptionCommand`, `disableLanguageOptionCommand`, `ratingCommand`, `likeCommand`, `dislikeCommand`, `bookmarkCommand`.

**App-termination cleanup:** observes `NSApplication.willTerminateNotification` and calls `clear()` so the widget does not retain stale info after app close.

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
| `hp.eq.schemaVersion` | `Int` | `EQPersistenceStore.save(_:)` |
| `hp.eq.enabled` | `Bool` | `EQPersistenceStore.save(_:)` |
| `hp.eq.preamp` | `Float` | `EQPersistenceStore.save(_:)` |
| `hp.eq.bands` | `Data` (JSON `[Float]`, 10 elements) | `EQPersistenceStore.save(_:)` |
| `hp.eq.currentPresetName` | `String?` | `EQPersistenceStore.save(_:)` |
| `hp.eq.customPresets` | `Data` (JSON `[EQPreset]`) | `EQPersistenceStore.save(_:)` |
| `hp.lyrics.prefs.<absolute-file-path>[#track=<n>]` | `Data` (JSON `LyricsPreference`) | `DefaultLyricsPreferenceStore.save(_:for:)` |

**EQ schema versioning (Slice 9-K).** The `hp.eq.*` keys are managed by `EQPersistenceStore` (see §5.6), independent of `AppState.saveState()`. Current schema version is `1`. On `load()`, an absent `hp.eq.schemaVersion` indicates a fresh install — the store stamps version 1 and returns `EQPersistedState.defaults`. A present version is decoded and lifted to the current version via `EQSchemaMigrator.migrate(...)` (see §5.7). Future slices (per-track EQ, user-adjustable Q) bump the version; older builds reading a newer version fall back to defaults rather than corrupting state.

**Lyrics preferences (Slice 9-J).** The `hp.lyrics.prefs.*` keys are managed by `DefaultLyricsPreferenceStore` (see §4.6), independent of `AppState.saveState()`. The key prefix is `hp.lyrics.prefs.` followed by the track's absolute file path, with an optional `#track=<n>` suffix for CUE virtual tracks. The CUE suffix branch is **latent in 9-J** — `Track` does not yet carry a `cueTrackNumber` field, so the key generator currently emits the non-CUE form only; v0.15 activates the suffix when CUE support lands. Preferences are keyed by file path (and CUE track number when applicable), so the same file appearing in playlist A and playlist B uses identical preference. Failures during save (encoder errors) are silently ignored — preferences are best-effort and must not break playback.

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

`import MediaPlayer` restricted to: `MPNowPlayingAdapter.swift` (Slice 9-L).

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