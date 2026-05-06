# HarmoniaPlayer Implementation Guide (Swift)

> **Platform:** macOS 15.6+
> **Language:** Swift 6
> **Framework:** SwiftUI, HarmoniaCore-Swift (SPM)
>
> This guide provides concrete implementation patterns for building HarmoniaPlayer
> on macOS using Swift 6 and HarmoniaCore-Swift.

---

## 1. Overview

This guide demonstrates:
- How the Integration Layer bridges HarmoniaCore-Swift to the app
- How `AppState` is wired with dependency injection
- How to integrate StoreKit 2 for Pro unlock
- How errors flow from `CoreError` to `PlaybackError` to the UI
- SwiftUI view patterns and async/await usage
- Testing patterns with test doubles

**Prerequisites:**
- Read [API Reference](api_reference.md) for the complete interface surface
- Review [Module Boundaries](module_boundary.md) for dependency rules
- Understand [HarmoniaCore Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)

**Key mental model:**

```
[HC] PlaybackService  — synchronous (throws CoreError)
              ↓ wrapped by
[HP] HarmoniaPlaybackServiceAdapter  — bridges sync → async, maps CoreError → PlaybackError
              ↓ conforms to
[HP] PlaybackService (app-layer protocol)  — async throws PlaybackError
              ↓ used by
[HP] AppState  — async methods consumed by SwiftUI Views via Task { await ... }
```

HarmoniaCore's own APIs are synchronous. The app-layer `PlaybackService`
protocol defined in HarmoniaPlayer is **async throws**. The Integration Layer
bridges the two.

---

## 2. Integration Layer

The Integration Layer is the **only** place in HarmoniaPlayer where
`import HarmoniaCore` or `import MediaPlayer` is allowed. It consists
of exactly three HarmoniaCore-importing files, one closure-binding
adapter that does not import HarmoniaCore, and one MediaPlayer-importing
adapter for the system Now Playing surface:

1. `HarmoniaCoreProvider.swift` — constructs real HarmoniaCore services
2. `HarmoniaPlaybackServiceAdapter.swift` — wraps `DefaultPlaybackService`
3. `HarmoniaTagReaderAdapter.swift` — wraps `TagReaderPort`
4. `HarmoniaEQAdapter.swift` — bridges Core EQ control surface to `EQService`
   via closures (no `import HarmoniaCore` — see §2.5)
5. `MPNowPlayingAdapter.swift` — bridges `NowPlayingService` to system
   `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` (only `import
   MediaPlayer` site — see §2.6)

### 2.1 HarmoniaCoreProvider

The single production implementation of `CoreServiceProviding`. Constructs
all platform adapters and wires them into HarmoniaCore services. It also
caches the constructed `HarmoniaCore.PlaybackService` in `sharedCore` so
`makePlaybackService(isProUser:)` and `makeEQService()` operate on the same
audio chain — the EQ node injected at construction time must be the node
that the EQ control surface mutates.

```swift
import Foundation
import HarmoniaCore

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
        // See module_boundary.md §4.4(b) for the rationale.
        DefaultLyricsService()
    }

    func makeEQService() -> EQService {
        // Closure binding — keeps HarmoniaCore types out of HarmoniaEQAdapter.
        let core = sharedCore ?? buildCore()
        self.sharedCore = core
        return HarmoniaEQAdapter(
            setEnabled:   { core.setEQEnabled($0)   },
            setPreamp:    { core.setEQPreamp($0)    },
            setBandGains: { core.setEQBandGains($0) }
        )
    }

    private func buildCore() -> HarmoniaCore.PlaybackService {
        let logger  = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "Playback")
        let clock   = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let eq      = AVAudioUnitEQAdapter()
        // The same `eq` instance is handed to BOTH the audio output adapter
        // (which splices its node into the live signal chain during configure)
        // AND DefaultPlaybackService (which forwards the EQ control surface).
        // Sharing one instance is what makes setEQEnabled / setEQPreamp /
        // setEQBandGains audible — see module_boundary.md §4.3(c).
        let audio   = AVAudioEngineOutputAdapter(logger: logger, eq: eq)
        return DefaultPlaybackService(
            decoder: decoder,
            audio:   audio,
            clock:   clock,
            logger:  logger,
            eq:      eq
        )
    }
}
```

The `isProUser` parameter is forwarded for future Pro-tier decoder selection.
Currently the same adapter is used for both tiers.

### 2.2 HarmoniaPlaybackServiceAdapter

Bridges synchronous HarmoniaCore to the async app-layer protocol. Handles
`CoreError` → `PlaybackError` mapping at the module boundary so the app
never sees `CoreError` directly.

```swift
import Foundation
import HarmoniaCore

final class HarmoniaPlaybackServiceAdapter: PlaybackService {

    private let core: HarmoniaCore.PlaybackService

    init(core: HarmoniaCore.PlaybackService) { self.core = core }

    var state: PlaybackState {
        switch core.state {
        case .stopped:      return .stopped
        case .playing:      return .playing
        case .paused:       return .paused
        case .buffering:    return .loading
        case .error(let e): return .error(Self.mapCoreError(e))
        }
    }

    func load(url: URL) async throws {
        do { try core.load(url: url) }
        catch let error as CoreError { throw Self.mapCoreError(error) }
    }

    func play() async throws {
        do { try core.play() }
        catch let error as CoreError { throw Self.mapCoreError(error) }
    }

    func pause() async             { core.pause() }
    func stop() async              { core.stop() }
    func currentTime() async -> TimeInterval { core.currentTime() }
    func duration() async -> TimeInterval    { core.duration() }
    func setVolume(_ volume: Float) async    { core.setVolume(volume) }

    // Boundary: CoreError → PlaybackError.
    // No String payload crosses the module boundary.
    static func mapCoreError(_ error: CoreError) -> PlaybackError {
        switch error {
        case .notFound:        return .failedToOpenFile
        case .ioError:         return .failedToOpenFile
        case .unsupported:     return .unsupportedFormat
        case .decodeError:     return .failedToDecode
        case .invalidState:    return .invalidState
        case .invalidArgument: return .invalidArgument
        }
    }
}
```

Note the fully-qualified `HarmoniaCore.PlaybackService` — `PlaybackService`
alone inside HarmoniaPlayer refers to the app-layer protocol.

### 2.3 HarmoniaTagReaderAdapter

Pure value mapping from HarmoniaCore's `TagBundle` to HarmoniaPlayer's `Track`.
No AVFoundation calls — all metadata reading is done inside HarmoniaCore:

```swift
import Foundation
import HarmoniaCore

final class HarmoniaTagReaderAdapter: TagReaderService {

    private let port: TagReaderPort

    init(port: TagReaderPort) { self.port = port }

    var currentSchemaVersion: Int { TagBundle.currentSchemaVersion }

    func readMetadata(for url: URL) async throws -> Track {
        let bundle = try port.read(url: url)
        let fileFormat = url.pathExtension.uppercased()

        return Track(
            url:              url,
            title:            bundle.title       ?? url.deletingPathExtension().lastPathComponent,
            artist:           bundle.artist      ?? "",
            album:            bundle.album       ?? "",
            duration:         bundle.duration    ?? 0,
            artworkData:      bundle.artworkData,
            albumArtist:      bundle.albumArtist ?? "",
            composer:         bundle.composer    ?? "",
            genre:            bundle.genre       ?? "",
            year:             bundle.year,
            trackNumber:      bundle.trackNumber,
            trackTotal:       bundle.trackTotal,
            discNumber:       bundle.discNumber,
            discTotal:        bundle.discTotal,
            bpm:              bundle.bpm,
            replayGainTrack:  bundle.replayGainTrack,
            replayGainAlbum:  bundle.replayGainAlbum,
            comment:          bundle.comment     ?? "",
            bitrate:          bundle.bitrate,
            sampleRate:       bundle.sampleRate,
            channels:         bundle.channels,
            fileSize:         bundle.fileSize,
            fileFormat:       fileFormat,
            codec:            bundle.codec    ?? "",
            encoding:         bundle.encoding ?? "",
            metadataVersion:  TagBundle.currentSchemaVersion,
            lyrics:           bundle.lyrics.map { hcVariants in
                hcVariants.map { LyricsLanguageVariant(languageCode: $0.languageCode, text: $0.text) }
            }
        )
    }
}
```

### 2.4 CoreFactory (Application Layer)

`CoreFactory` is in the **Application Layer** — it does **not** import
HarmoniaCore. It delegates construction to a `CoreServiceProviding`
implementation, enabling test injection:

```swift
struct CoreFactory {
    let featureFlags: CoreFeatureFlags
    private let provider: CoreServiceProviding

    init(featureFlags: CoreFeatureFlags, provider: CoreServiceProviding) {
        self.featureFlags = featureFlags
        self.provider = provider
    }

    func makePlaybackService() -> PlaybackService {
        let isProUser = featureFlags.supportsFLAC
        return provider.makePlaybackService(isProUser: isProUser)
    }

    func makeTagReaderService() -> TagReaderService {
        provider.makeTagReaderService()
    }

    func makeLyricsService() -> LyricsService {
        provider.makeLyricsService()
    }

    func makeEQService() -> EQService {
        provider.makeEQService()
    }
}
```

Production wiring uses `HarmoniaCoreProvider`; tests use `FakeCoreProvider`.

### 2.5 HarmoniaEQAdapter (Integration Layer, no HarmoniaCore import)

`HarmoniaEQAdapter` lives in the Integration Layer alongside the three
importing adapters above, but it **does not** `import HarmoniaCore`. Instead
of holding a `HarmoniaCore.PlaybackService` reference directly, it holds
three closures bound by `HarmoniaCoreProvider.makeEQService()`. The closures
forward `EQService` calls to the Core PlaybackService EQ control surface.

This pattern buys two things:

1. The `import HarmoniaCore` count in HarmoniaPlayer stays at three files
   (see `module_boundary.md` Section 3.2 rule 2).
2. `EQServiceTests` can verify forward semantics without importing
   HarmoniaCore — `IntegrationTests.swift` line 28 forbids HarmoniaCore in
   tests; this adapter side-steps that constraint by design.

```swift
import Foundation

final class HarmoniaEQAdapter: EQService {

    private let setEnabledHook:   (Bool)    -> Void
    private let setPreampHook:    (Float)   -> Void
    private let setBandGainsHook: ([Float]) -> Void

    init(
        setEnabled:   @escaping (Bool)    -> Void,
        setPreamp:    @escaping (Float)   -> Void,
        setBandGains: @escaping ([Float]) -> Void
    ) {
        self.setEnabledHook   = setEnabled
        self.setPreampHook    = setPreamp
        self.setBandGainsHook = setBandGains
    }

    func setEnabled(_ enabled: Bool)    { setEnabledHook(enabled) }
    func setPreamp(_ db: Float)         { setPreampHook(db) }
    func setBandGains(_ gains: [Float]) { setBandGainsHook(gains) }

    // Xcode 26 beta workaround — see development_guide.md §8.6.
    nonisolated deinit { }
}
```

**Swift 6 / Xcode 26 notes:**

- Stored closure types are plain `(Bool) -> Void` / `(Float) -> Void` /
  `([Float]) -> Void`, **not** `@Sendable`. They inherit MainActor isolation
  from `HarmoniaCoreProvider.makeEQService()` and capture the non-Sendable
  `HarmoniaCore.PlaybackService` without crossing an isolation boundary, so
  no Sendable warning is emitted.
- The class declares an **explicit** `nonisolated deinit { }` to sidestep
  the Xcode 26 beta `swift_task_deinitOnExecutorImpl` TaskLocal teardown
  crash. Earlier comments in this section claimed *"no explicit deinit
  avoids the bug"* — that was wrong: it is the **compiler-synthesised**
  deinit on an inferred-`@MainActor` class that fires the bug, and only the
  explicit `nonisolated deinit { }` forces deallocation down the synchronous
  ARC path. The same pattern is applied to `EQCoordinator`, `AppState`, and
  the test-side `FakeEQService` — see `development_guide.md` §8.6 for the
  full rationale and inventory.

### 2.6 MPNowPlayingAdapter (Integration Layer, imports MediaPlayer)

Slice 9-L. `MPNowPlayingAdapter` is the only file in HarmoniaPlayer that
imports the `MediaPlayer` framework. It bridges the application-layer
`NowPlayingService` protocol to two system singletons:

- `MPNowPlayingInfoCenter.default()` — receives push updates (metadata,
  playback state, elapsed time) so the system Now Playing widget reflects
  HarmoniaPlayer state.
- `MPRemoteCommandCenter.shared()` — receives user actions on the system
  surface (Control Center widget, lock screen, AirPods, media keys, Siri)
  and routes them to the seven `NowPlayingService` pull-side callbacks
  that `NowPlayingCoordinator` has assigned.

Constructed once at app launch via `HarmoniaCoreProvider.makeNowPlayingService()`;
lives the process lifetime so Bluetooth / media-key / Siri commands work
at any moment regardless of current playback state.

```swift
import Foundation
import AppKit
import MediaPlayer

final class MPNowPlayingAdapter: NowPlayingService {

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onStop: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    init() {
        registerSupportedCommands()
        disableUnsupportedCommands()
        observeAppTermination()
    }

    func updateCurrentTrack(_ track: Track?) { /* push metadata, artwork */ }
    func updatePlaybackState(_ state: PlaybackState, rate: Double) { /* push state + rate */ }
    func updateElapsedTime(_ seconds: Double) { /* re-anchor scrubber */ }
    func clear() {
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .unknown
    }

    // ... see api_reference.md §6.5 for the full list of pushed keys,
    //     registered commands, disabled commands, artwork fallback rules,
    //     and app-termination cleanup.
}
```

**Why no `import HarmoniaCore`:** this adapter bridges to a system macOS
surface, not the audio core. `MediaPlayer.framework` does not exist on
Linux; the cross-platform abstraction is `NowPlayingService` (Application
Layer protocol). See `module_boundary.md` §4.5 for the full rationale.

---

## 3. AppState Implementation

`AppState` is the central observable state. It is `@MainActor` and split
across five files for maintainability:

| File | Responsibility |
|------|----------------|
| `AppState.swift` | Properties, init, persistence, display helpers |
| `AppState+Playlist.swift` | Playlist operations, undo/redo, sort |
| `AppState+Playback.swift` | Transport controls, volume, ReplayGain, polling |
| `AppState+Navigation.swift` | Next/previous, track-finished handling |
| `AppState+M3U8.swift` | M3U8 import/export |

### 3.1 Initialization (Dependency Injection)

```swift
@MainActor
final class AppState: ObservableObject {

    // Services — internal access, never `private`
    // (Views access AppState, not services directly — the boundary is
    //  architectural, not enforced by access control.)
    let playbackService: PlaybackService
    let tagReaderService: TagReaderService
    let fileDropService: FileDropService

    // Lyrics services (Slice 9-J). LyricsService resolves USLT + sidecar
    // `.lrc` content; LyricsPreferenceStore persists per-track source /
    // encoding / language choice keyed by absolute file path.
    let lyricsService: LyricsService
    let lyricsPreferenceStore: LyricsPreferenceStore

    // Owns observable EQ state; views read EQ via `appState.eqCoordinator.…`
    // (Slice 9-K). AppState itself has no EQ-specific @Published properties.
    let eqCoordinator: EQCoordinator

    // NowPlaying coordinator (Slice 9-L). Routes AppState publishers and
    // action closures to the system Now Playing surface via NowPlayingService.
    // Declared `private(set) var ...!` rather than `let` so the seven action
    // closures can capture `[weak self]` after every other stored property
    // is initialised.
    private(set) var nowPlayingCoordinator: NowPlayingCoordinator!

    // Dependencies kept private
    private let iapManager: IAPManager
    private let userDefaults: UserDefaults

    // Derived from IAPManager
    private(set) var featureFlags: CoreFeatureFlags

    // Published state (excerpt)
    @Published private(set) var isProUnlocked: Bool
    @Published var playlists: [Playlist]
    @Published var activePlaylistIndex: Int = 0
    @Published var currentTrack: Track?
    @Published var playbackState: PlaybackState = .idle
    @Published var lastError: PlaybackError?

    // Lyrics state (Slice 9-J). Lives directly on AppState rather than in a
    // parallel coordinator — see module_boundary.md §4.4(a) for rationale.
    @Published var showLyrics: Bool = false
    @Published var lyricsResolution: LyricsResolution?

    init(
        iapManager: IAPManager,
        provider: CoreServiceProviding,
        userDefaults: UserDefaults = .standard,
        undoManager: UndoManager? = nil,
        lyricsPreferenceStore: LyricsPreferenceStore? = nil,
        eqCoordinator: EQCoordinator? = nil
    ) {
        self.iapManager   = iapManager
        self.featureFlags = CoreFeatureFlags(iapManager: iapManager)

        let coreFactory = CoreFactory(
            featureFlags: featureFlags,
            provider:     provider
        )
        self.playbackService  = coreFactory.makePlaybackService()
        self.tagReaderService = coreFactory.makeTagReaderService()
        self.fileDropService  = FileDropService()

        // Lyrics — production builds the default store backed by the same
        // userDefaults; tests inject a stub via the parameter.
        self.lyricsService = coreFactory.makeLyricsService()
        self.lyricsPreferenceStore = lyricsPreferenceStore
            ?? DefaultLyricsPreferenceStore(userDefaults: userDefaults)

        // EQ coordinator — injected variant for tests, default for production.
        // The default uses the same provider's EQService and a store backed by
        // the same `userDefaults` instance, so coordinator state and persisted
        // state stay in sync from t=0.
        self.eqCoordinator = eqCoordinator
            ?? EQCoordinator(
                service: coreFactory.makeEQService(),
                store:   EQPersistenceStore(defaults: userDefaults)
            )

        self.isProUnlocked  = iapManager.isProUnlocked
        self.playlists      = [Playlist(name: "Playlist 1")]
        self.userDefaults   = userDefaults
        // ... (remaining init: undoManager, languageBundle, restoreState(),
        //      Combine sinks for replayGainMode/selectedLanguage/lyricsResolution)

        // NowPlayingCoordinator (Slice 9-L). Constructed last so all stored
        // properties are initialised before the seven action closures capture
        // `[weak self]`. The coordinator never holds an AppState reference.
        self.nowPlayingCoordinator = NowPlayingCoordinator(
            service: coreFactory.makeNowPlayingService(),
            currentTrackPublisher: $currentTrack.eraseToAnyPublisher(),
            playbackStatePublisher: $playbackState.eraseToAnyPublisher(),
            currentTimeProvider: { [weak self] in self?.currentTime ?? 0 },
            play: { [weak self] in await self?.play() },
            pause: { [weak self] in await self?.pause() },
            stop: { [weak self] in await self?.stop() },
            seek: { [weak self] s in await self?.seek(to: s) },
            next: { [weak self] in await self?.playNextTrack() },
            previous: { [weak self] in await self?.playPreviousTrack() },
            togglePlayPause: { [weak self] in
                guard let self else { return }
                if self.playbackState == .playing { await self.pause() }
                else { await self.play() }
            }
        )
    }

    // Xcode 26 beta workaround — see development_guide.md §8.6.
    nonisolated deinit {}
}
```

**Wiring flow:** `IAPManager` → `CoreFeatureFlags` → `CoreFactory` → Services.

### 3.2 Async Playback Methods

All transport methods are `async` because the app-layer `PlaybackService`
protocol is async. Errors from the Integration Layer arrive already mapped
to `PlaybackError`:

```swift
extension AppState {

    // Resumes from current position. If no track loaded, resolves one from
    // selection or the first track in the active playlist.
    func play() async {
        if currentTrack == nil {
            let tracks = playlists[activePlaylistIndex].tracks
            if !selectedTrackIDs.isEmpty,
               let selected = tracks.first(where: { selectedTrackIDs.contains($0.id) }) {
                await play(trackID: selected.id)
            } else if let first = tracks.first {
                await play(trackID: first.id)
            }
            return
        }

        do {
            try await playbackService.play()
            playbackState = .playing
            startPolling()
        } catch {
            let mapped = mapToPlaybackError(error)
            lastError = mapped
            playbackState = .error(mapped)
        }
    }

    func pause() async {
        await playbackService.pause()
        playbackState = .paused
    }

    func stop() async {
        stopPolling()
        await playbackService.stop()
        playbackState = .stopped
        currentTime = 0
    }
}
```

### 3.3 Fallback Error Mapping

`CoreError` → `PlaybackError` mapping happens in
`HarmoniaPlaybackServiceAdapter` (Integration Layer). AppState only needs a
thin fallback for unexpected non-`PlaybackError` errors:

```swift
// In AppState (Application Layer)
func mapToPlaybackError(_ error: Error) -> PlaybackError {
    if let playbackError = error as? PlaybackError { return playbackError }
    // Should not happen if Integration Layer mapping is complete.
    // Logged as invalidState for diagnostic purposes.
    return .invalidState
}
```

---

## 4. IAPManager Implementation

Three implementations exist, all conforming to the `IAPManager` protocol:

| Implementation | Use Case |
|----------------|----------|
| `StoreKitIAPManager` | Production (StoreKit 2 + UserDefaults cache) |
| `FreeTierIAPManager` | Free-tier build stub (always `isProUnlocked == false`) |
| `MockIAPManager` | Tests (deterministic + configurable purchase result) |

### 4.1 StoreKitIAPManager (Production)

Uses StoreKit 2 with a UserDefaults cache so AppState's synchronous init
can read `isProUnlocked` without awaiting:

```swift
import Foundation
import StoreKit

final class StoreKitIAPManager: IAPManager {

    static let productID = "harmoniaplayer.pro"
    private static let defaultsKey = "hp.isProUnlocked"

    private(set) var isProUnlocked: Bool {
        didSet {
            defaults.set(isProUnlocked, forKey: Self.defaultsKey)
        }
    }

    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        self.isProUnlocked = userDefaults.bool(forKey: Self.defaultsKey)
        // Listen for Transaction.updates for Ask-to-Buy / Family Sharing.
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    func refreshEntitlements() async {
        guard let result = await Transaction.currentEntitlement(for: Self.productID)
        else {
            isProUnlocked = false
            return
        }
        if case .verified = result {
            isProUnlocked = true
        }
    }

    func purchasePro() async throws {
        let products = try await Product.products(for: [Self.productID])
        guard let product = products.first else {
            throw IAPError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                isProUnlocked = true
            case .unverified:
                throw IAPError.verificationFailed
            }
        case .userCancelled:
            throw IAPError.userCancelled
        case .pending:
            throw IAPError.purchaseFailed("pending")
        @unknown default:
            throw IAPError.purchaseFailed("unknown")
        }
    }
}
```

`IAPError` cases (see `[HP] IAPManager.swift`):
- `.productNotFound` — product not found in App Store Connect
- `.verificationFailed` — StoreKit could not verify result
- `.userCancelled` — user dismissed the purchase sheet
- `.purchaseFailed(String)` — underlying failure with reason
- `.notAvailable` — IAP not available (e.g. Free-tier stub)

### 4.2 FreeTierIAPManager (Stub)

For Free-tier builds where IAP is not wired up:

```swift
final class FreeTierIAPManager: IAPManager {
    var isProUnlocked: Bool { false }
    func refreshEntitlements() async { }
    func purchasePro() async throws {
        throw IAPError.notAvailable
    }
}
```

### 4.3 AppState IAP Surface

```swift
extension AppState {
    func purchasePro() async throws {
        try await iapManager.purchasePro()
        isProUnlocked = iapManager.isProUnlocked
        featureFlags = CoreFeatureFlags(iapManager: iapManager)
    }

    func refreshEntitlements() async {
        await iapManager.refreshEntitlements()
        isProUnlocked = iapManager.isProUnlocked
        featureFlags = CoreFeatureFlags(iapManager: iapManager)
    }
}
```

Note that `featureFlags` is **rebuilt** after purchase/refresh so downstream
gating uses the fresh tier info.

---

## 5. SwiftUI Integration

### 5.1 App Entry Point

`HarmoniaPlayerApp` builds `AppState` with production dependencies. The
app entry uses `@StateObject` so AppState survives view redraws:

```swift
import SwiftUI

@main
struct HarmoniaPlayerApp: App {

    init() {
        // Resolve UI language from persisted setting before any view loads.
        let saved = UserDefaults.standard.string(forKey: "hp.selectedLanguage")
        if let lang = saved, lang != "system" {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        } else if saved == nil {
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            UserDefaults.standard.set("en", forKey: "hp.selectedLanguage")
        }
    }

    @StateObject private var appState = AppState(
        iapManager: StoreKitIAPManager(),
        provider:   HarmoniaCoreProvider()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .focusedSceneObject(appState)
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification
                )) { _ in
                    appState.saveState()
                }
        }
        .commands { HarmoniaPlayerCommands() }

        Window("Mini Player", id: "mini-player") {
            MiniPlayerView().environmentObject(appState)
        }
        .windowResizability(.contentSize)

        Window("Equalizer", id: "equalizer-window") {
            EQWindow().environmentObject(appState)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView().environmentObject(appState)
        }
    }
}
```

### 5.2 Calling Async AppState Methods from SwiftUI

Every transport method on AppState is `async`. SwiftUI button handlers
are synchronous, so wrap calls in `Task { await ... }`:

```swift
struct TransportControls: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack {
            Button {
                Task { await appState.playPreviousTrack() }
            } label: { Image(systemName: "backward.fill") }

            Button {
                Task {
                    if appState.playbackState == .playing {
                        await appState.pause()
                    } else {
                        await appState.play()
                    }
                }
            } label: {
                Image(systemName: appState.playbackState == .playing
                      ? "pause.fill" : "play.fill")
            }

            Button {
                Task { await appState.stop() }
            } label: { Image(systemName: "stop.fill") }

            Button {
                Task { await appState.playNextTrack() }
            } label: { Image(systemName: "forward.fill") }
        }
    }
}
```

### 5.3 Seeking from a Slider Binding

Sliders need synchronous getters. Keep a local `@State` for the displayed
value and dispatch the async seek in the change handler:

```swift
struct ProgressBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Slider(
            value: Binding(
                get: { appState.currentTime },
                set: { newValue in
                    Task { await appState.seek(to: newValue) }
                }
            ),
            in: 0...max(appState.duration, 1)
        )
    }
}
```

### 5.4 Error Presentation

`AppState.lastError` is a `PlaybackError` enum with no String payload. Map
each case to a localised user-facing message in the View:

```swift
struct ErrorAlert: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content.alert(
            "Playback Error",
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: { if !$0 { appState.clearLastError() } }
            ),
            presenting: appState.lastError
        ) { _ in
            Button("OK") { appState.clearLastError() }
        } message: { error in
            Text(message(for: error))
        }
    }

    private func message(for error: PlaybackError) -> String {
        switch error {
        case .unsupportedFormat: return NSLocalizedString("error.unsupported_format", comment: "")
        case .failedToOpenFile:  return NSLocalizedString("error.file_not_found",     comment: "")
        case .failedToDecode:    return NSLocalizedString("error.decode_failed",      comment: "")
        case .outputError:       return NSLocalizedString("error.output",             comment: "")
        case .invalidState,
             .invalidArgument:   return NSLocalizedString("error.internal",           comment: "")
        }
    }
}
```

### 5.5 Drag-and-Drop

Drag-and-drop validation goes through `FileDropService` via
`AppState.handleFileDrop(urls:)`. Views should never validate URLs or call
`load(urls:)` directly:

```swift
struct PlaylistView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(appState.playlist.tracks) { track in
            TrackRow(track: track)
        }
        .dropDestination(for: AudioFileItem.self) { items, _ in
            Task {
                await appState.handleFileDrop(urls: items.map { $0.url })
            }
            return true
        }
    }
}
```

`AudioFileItem` uses `ProxyRepresentation` (not `FileRepresentation`) to
receive the original file URL — `FileRepresentation` creates a temporary
copy that is deleted after the callback, breaking playback.

---

## 6. Testing Patterns

### 6.1 Test Doubles

Test infrastructure lives in `HarmoniaPlayerTests/FakeInfrastructure/`:

| Double | Replaces | Notable features |
|--------|----------|------------------|
| `FakeCoreProvider` | `CoreServiceProviding` | Injectable `FakePlaybackService`, `TagReaderService`, `FakeLyricsService`, `FakeEQService`, and `FakeNowPlayingService` stubs |
| `FakePlaybackService` | `PlaybackService` | Call counts, error stubs, `resetCounts()` for post-setup tests |
| `FakeTagReaderService` | `TagReaderService` | Per-URL metadata stubs, per-URL error stubs, configurable schema version |
| `FakeLyricsService` | `LyricsService` | No-op fake: `resolveAvailability` returns `.none`, `resolveContent` throws `noEmbeddedLyrics`. Defined inline in `FakeCoreProvider.swift`, not a separate file (Slice 9-J). Avoids `DefaultLyricsService`'s Xcode 26 beta runtime double-free when many short-lived instances coexist |
| `StubLyricsService` | `LyricsService` | Configurable: `stubbedResolution` dictates `resolveAvailability` output; `resolveAvailabilityCallCount` and `lastResolvedTrack` for assertion. Defined inline in `FakeCoreProvider.swift` (Slice 9-J) |
| `FakeEQService` | `EQService` | Call counts (`setEnabledCallCount`, `setPreampCallCount`, `setBandGainsCallCount`) plus last-value capture; defined inline in `FakeCoreProvider.swift`, not a separate file (Slice 9-K) |
| `FakeNowPlayingService` | `NowPlayingService` | Push call counters, last-value captures, `updatedElapsedHistory` array, and pull-side callback properties tests can invoke directly to simulate system commands. Standalone file in `FakeInfrastructure/` (Slice 9-L) |
| `MockIAPManager` | `IAPManager` | Configurable `purchaseResult` enum, call counts |

### 6.2 @MainActor Test Classes (Swift 6)

`AppState` is `@MainActor`. Test classes that use it must also be
`@MainActor` — XCTest runs `@MainActor`-isolated classes on the main
actor automatically, so individual methods don't need `await MainActor.run {}`:

```swift
import XCTest
@testable import HarmoniaPlayer

@MainActor
final class AppStatePlaybackControlTests: XCTestCase {

    private var sut: AppState!
    private var fakePlaybackService: FakePlaybackService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "hp-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        fakePlaybackService = FakePlaybackService()
        let provider = FakeCoreProvider(playbackService: fakePlaybackService)
        let iap = MockIAPManager(isProUnlocked: false)
        sut = AppState(
            iapManager:   iap,
            provider:     provider,
            userDefaults: testDefaults
        )
    }

    override func tearDown() {
        sut = nil
        fakePlaybackService = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPlayCallsServicePlay() async {
        await seedTracks()

        // Clear call counts set up by seedTracks().
        fakePlaybackService.resetCounts()

        await sut.play()

        XCTAssertEqual(fakePlaybackService.playCallCount, 1)
        XCTAssertEqual(sut.playbackState, .playing)
    }

    // Helper: loads tracks so play() can proceed past the
    // "no currentTrack / stopped state" guards.
    private func seedTracks() async {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        await sut.load(urls: [url])
        if let first = sut.playlist.tracks.first {
            await sut.play(trackID: first.id)
        }
    }
}
```

Key points:
- `@MainActor` on the test class — do not put it on individual methods
- Use a fresh `UserDefaults(suiteName:)` per test and clean up in `tearDown`
- Setup helpers like `seedTracks()` should reset call counts so assertions
  target the operation under test, not the setup

### 6.3 Configuring Fakes

```swift
// Stub a metadata response
let fakeTagReader = FakeTagReaderService()
let url = URL(fileURLWithPath: "/tmp/song.mp3")
fakeTagReader.stubbedMetadata[url] = Track(
    url: url, title: "Real Title", artist: "Artist X"
)

// Stub an error for a specific URL
fakeTagReader.stubbedErrors[url] = PlaybackError.failedToOpenFile

// Stub a playback error
let fakePlayback = FakePlaybackService()
fakePlayback.stubbedPlayError = PlaybackError.outputError

// Mock IAP purchase behavior
let mockIAP = MockIAPManager(isProUnlocked: false)
mockIAP.purchaseResult = .success
// or
mockIAP.purchaseResult = .failure(.userCancelled)

// Stub a lyrics resolution (Slice 9-J)
let stubLyrics = StubLyricsService()
stubLyrics.stubbedResolution = LyricsResolution(
    hasAny: true,
    currentSource: .embedded,
    availableSources: [.embedded],
    availableLanguages: ["eng"],
    currentLanguage: "eng",
    content: nil
)
let provider = FakeCoreProvider(lyricsService: stubLyrics)
// ... drive AppState ...
XCTAssertEqual(stubLyrics.resolveAvailabilityCallCount, 1)
XCTAssertEqual(stubLyrics.lastResolvedTrack?.id, expectedTrack.id)
```

---

## 7. Architecture Patterns Summary

### 7.1 Dependency Flow

```
SwiftUI Views
    ↓ @EnvironmentObject
AppState (@MainActor)
    ↓ constructor-injected
CoreFactory (Application Layer)
    ↓ delegates to
CoreServiceProviding (HarmoniaCoreProvider in prod)
    ↓ constructs
HarmoniaPlaybackServiceAdapter, HarmoniaTagReaderAdapter (Integration Layer)
    ↓ wraps
DefaultPlaybackService, TagReaderPort (HarmoniaCore-Swift)
    ↓ use
AVAssetReaderDecoder, AVAudioEngine, AVMetadataTagReader (AVFoundation)
```

### 7.2 Key Principles

1. **Sync/async boundary at Integration Layer**
   - HarmoniaCore is synchronous; HarmoniaPlayer's protocols are async
   - `HarmoniaPlaybackServiceAdapter` does the bridging

2. **Typed errors at the boundary**
   - `CoreError` (with String payloads) is mapped to `PlaybackError` (no payloads)
   - Technical details stay in HarmoniaCore's logger, never cross into the app

3. **Dependency injection everywhere**
   - All services injected via constructor
   - No singletons in services (app entry point creates the graph)
   - `CoreServiceProviding` protocol enables test swap-in

4. **`import HarmoniaCore` restricted to 3 files; `import MediaPlayer` restricted to 1 file**
   - HarmoniaCore: `HarmoniaCoreProvider`, `HarmoniaPlaybackServiceAdapter`, `HarmoniaTagReaderAdapter`
   - MediaPlayer: `MPNowPlayingAdapter` (Slice 9-L, system Now Playing surface)
   - Any other file importing either is a boundary violation

5. **Views use AppState only**
   - No ViewModels — AppState is the single observable state
   - No direct service access from Views
   - Async AppState methods dispatched via `Task { await ... }`

---

## 8. Common Pitfalls

### ❌ Don't: Call async AppState methods without `Task`

```swift
Button("Play") {
    appState.play()  // ❌ error: async call in sync context
}
```

### ✅ Do: Wrap in `Task { await ... }`

```swift
Button("Play") {
    Task { await appState.play() }
}
```

---

### ❌ Don't: Import HarmoniaCore outside the 3 Integration Layer files

```swift
// In AppState+Playback.swift
import HarmoniaCore  // ❌ boundary violation
```

### ✅ Do: Use app-layer protocols

```swift
// AppState uses PlaybackService (app-layer protocol)
// No HarmoniaCore import needed.
try await playbackService.play()
```

---

### ❌ Don't: Propagate String payloads from CoreError

```swift
case .unsupported(let msg):
    throw PlaybackError.unsupportedFormat(msg)  // ❌ carries String payload
```

### ✅ Do: Map to typed codes with no payload

```swift
case .unsupported:
    return .unsupportedFormat  // ✓ typed code only
```

---

### ❌ Don't: Use `FileRepresentation` for drag-and-drop import

```swift
static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(contentType: .audio) { received in
        AudioFileItem(url: received.file)  // ❌ received.file is a temporary copy
    }
}
```

### ✅ Do: Use `ProxyRepresentation` via URL

```swift
static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation(
        exporting: { $0.url },
        importing: { AudioFileItem(url: $0) }  // ✓ original file URL
    )
}
```

---

### ❌ Don't: Forget to rebuild `featureFlags` after purchase

```swift
func purchasePro() async throws {
    try await iapManager.purchasePro()
    isProUnlocked = iapManager.isProUnlocked
    // ❌ featureFlags still reflects the old tier
}
```

### ✅ Do: Rebuild `featureFlags` from the refreshed manager

```swift
func purchasePro() async throws {
    try await iapManager.purchasePro()
    isProUnlocked = iapManager.isProUnlocked
    featureFlags = CoreFeatureFlags(iapManager: iapManager)  // ✓
}
```

---

### ❌ Don't: Put `@MainActor` on individual test methods

```swift
final class AppStateTests: XCTestCase {
    func testSomething() async {
        await MainActor.run {  // ❌ unnecessary boilerplate
            sut.doSomething()
        }
    }
}
```

### ✅ Do: Mark the whole class `@MainActor`

```swift
@MainActor
final class AppStateTests: XCTestCase {
    func testSomething() async {
        sut.doSomething()  // ✓ automatically on main actor
    }
}
```

---

## 9. Cross-References

**HarmoniaCore Documentation:**
- [Services Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/04_services_impl.md)
- [Apple Adapters](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/02_01_apple_adapters_impl.md)
- [Models (CoreError, TagBundle)](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)

**HarmoniaPlayer Documentation:**
- [API Reference](api_reference.md) — complete interface surface
- [Architecture](architecture.md) — system design and C4 diagrams
- [Module Boundaries](module_boundary.md) — dependency rules and enforcement
- [Development Guide](development_guide.md) — setup and cross-repo workflow
- [Workflow](workflow.md) — SDD → TDD → commit cycle