# HarmoniaPlayer Implementation Guide (Swift)

> **Platform:** Apple platforms (macOS 13+, iOS 16+)  
> **Language:** Swift 5.9+  
> **Framework:** SwiftUI, HarmoniaCore-Swift
>
> This guide provides concrete implementation patterns for building HarmoniaPlayer
> on Apple platforms using Swift and HarmoniaCore-Swift.
>
> **Note:** This is Swift-specific. C++20 implementation will have different patterns.

---

## 1. Overview

This guide demonstrates:
- How to implement AppState with dependency injection
- How to construct HarmoniaCore services via CoreFactory
- How to integrate IAP management
- How to handle errors and state updates
- SwiftUI integration patterns

**Prerequisites:**
- Read [API Reference](api_reference.md) first
- Understand [HarmoniaCore Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- Review [Module Boundaries](module_boundary.md)

---

## 2. CoreFactory Implementation

CoreFactory constructs HarmoniaCore services by wiring ports to platform adapters.

```swift
import HarmoniaCore

struct CoreFactory {
    /// Constructs PlaybackService with Free or Pro configuration
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        // Create platform adapters
        let logger = OSLogAdapter()
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let audio = AVAudioEngineOutputAdapter(logger: logger)
        
        // Wire adapters into service
        return DefaultPlaybackService(
            decoder: decoder,
            audio: audio,
            clock: clock,
            logger: logger
        )
    }
    
    /// Constructs TagReaderPort for metadata extraction
    func makeTagReader() -> TagReaderPort {
        let logger = OSLogAdapter()
        return AVMetadataTagReaderAdapter(logger: logger)
    }
}
```

**Key Points:**
1. **Adapter Construction:** All Apple-specific code (AVFoundation, OSLog) lives here
2. **Service Wiring:** CoreFactory knows how to wire ports to adapters
3. **Configuration:** `isProUser` flag can be used for Pro feature selection
4. **Single Responsibility:** Only constructs services, doesn't use them

---

## 3. AppState Implementation

AppState is the central observable state for the application.

```swift
import SwiftUI
import Combine
import HarmoniaCore

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
    @Published private(set) var isProUser: Bool = false
    
    // MARK: - Services (injected via CoreFactory)
    
    private let playbackService: PlaybackService
    private let tagReader: TagReaderPort
    private let iapManager: IAPManager
    
    // MARK: - State Management
    
    private var updateTimer: Timer?
    
    // MARK: - Initialization (Dependency Injection)
    
    init(factory: CoreFactory, iap: IAPManager) {
        self.iapManager = iap
        self.isProUser = iap.isProUser
        
        // CoreFactory constructs services based on Pro status
        self.playbackService = factory.makePlaybackService(
            isProUser: iap.isProUser
        )
        self.tagReader = factory.makeTagReader()
        
        // Start observing IAP changes
        observeIAPChanges()
        
        // Start playback position timer
        startUpdateTimer()
    }
    
    // MARK: - Playlist Management
    
    func load(urls: [URL]) {
        for url in urls {
            do {
                // Check format requirements
                let ext = url.pathExtension.lowercased()
                let requiresPro = ["flac", "dsd", "dsf", "dff"].contains(ext)
                
                if requiresPro && !isProUser {
                    lastError = .unsupportedFormat(
                        "\(ext.uppercased()) playback requires Pro"
                    )
                    continue
                }
                
                // Enrich track with metadata
                let track = try enrichTrack(url: url)
                playlist.tracks.append(track)
                
            } catch {
                handleError(error)
            }
        }
    }
    
    func clearPlaylist() {
        stop()
        playlist.tracks.removeAll()
        currentTrack = nil
    }
    
    func removeTrack(_ trackID: Track.ID) {
        if currentTrack?.id == trackID {
            stop()
        }
        playlist.tracks.removeAll { $0.id == trackID }
    }
    
    func moveTrack(fromOffsets: IndexSet, toOffset: Int) {
        playlist.tracks.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }
    
    // MARK: - Playback Control (synchronous, throws on error)
    
    func play() throws {
        guard let track = currentTrack else {
            throw PlaybackError.coreError("No track selected")
        }
        
        try playbackService.play()
        playbackState = .playing
        lastError = nil
    }
    
    func play(trackID: Track.ID) throws {
        guard let track = playlist.tracks.first(where: { $0.id == trackID }) else {
            throw PlaybackError.fileNotFound(URL(fileURLWithPath: "/"))
        }
        
        // Stop current playback
        if playbackState == .playing || playbackState == .paused {
            stop()
        }
        
        // Load and play new track
        currentTrack = track
        playbackState = .loading
        
        do {
            try playbackService.load(url: track.url)
            duration = playbackService.duration()
            
            try playbackService.play()
            playbackState = .playing
            lastError = nil
            
        } catch {
            playbackState = .idle
            currentTrack = nil
            throw error
        }
    }
    
    func pause() {
        playbackService.pause()
        playbackState = .paused
    }
    
    func stop() {
        playbackService.stop()
        playbackState = .stopped
        currentTime = 0
    }
    
    func seek(to time: TimeInterval) throws {
        try playbackService.seek(to: time)
        currentTime = time
    }
    
    // MARK: - UI Helpers
    
    func toggleWaveformVisibility() {
        viewPreferences.isWaveformVisible.toggle()
    }
    
    func togglePlaylistVisibility() {
        viewPreferences.isPlaylistVisible.toggle()
    }
    
    func setLayoutPreset(_ preset: LayoutPreset) {
        viewPreferences.layoutPreset = preset
    }
    
    // MARK: - Metadata Reading (using TagReaderPort)
    
    private func enrichTrack(url: URL) throws -> Track {
        let tags = try tagReader.readTags(from: url)
        
        return Track(
            id: UUID(),
            url: url,
            title: tags["title"] as? String ?? url.lastPathComponent,
            artist: tags["artist"] as? String ?? "",
            album: tags["album"] as? String ?? "",
            duration: tags["duration"] as? TimeInterval,
            artworkURL: tags["artworkURL"] as? URL
        )
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        if let playbackError = error as? PlaybackError {
            lastError = playbackError
        } else {
            // Map HarmoniaCore errors to UI-friendly errors
            lastError = mapCoreError(error)
        }
    }
    
    private func mapCoreError(_ error: Error) -> PlaybackError {
        // This assumes HarmoniaCore defines a CoreError type
        // Adjust based on actual HarmoniaCore error types
        let description = error.localizedDescription
        
        if description.contains("not found") {
            return .fileNotFound(URL(fileURLWithPath: "/"))
        } else if description.contains("unsupported") {
            return .unsupportedFormat(description)
        } else if description.contains("decode") {
            return .decodingFailed(description)
        } else if description.contains("output") {
            return .outputFailed(description)
        } else {
            return .coreError(description)
        }
    }
    
    // MARK: - IAP Observation
    
    private func observeIAPChanges() {
        // Observe IAP state changes
        // Implementation depends on IAPManager design
        // This is a placeholder for the pattern
    }
    
    // MARK: - Playback Position Updates
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            self?.updatePlaybackPosition()
        }
    }
    
    private func updatePlaybackPosition() {
        guard playbackState == .playing else { return }
        currentTime = playbackService.currentTime()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}
```

**Key Implementation Patterns:**

1. **Dependency Injection:**
   - Services injected via constructor
   - No direct instantiation of adapters
   - Clear separation of concerns

2. **Synchronous Core, Async UI:**
   - HarmoniaCore methods are synchronous
   - AppState wraps them for UI consumption
   - Errors thrown, not returned in state

3. **State Updates:**
   - All state changes use `@Published`
   - SwiftUI observes changes automatically
   - Timer for playback position updates

4. **Error Handling:**
   - Map core errors to UI-friendly types
   - Store last error for UI display
   - Clear errors on successful operations

---

## 4. IAPManager Implementation

```swift
import StoreKit
import Combine

@MainActor
final class StoreKitIAPManager: IAPManager, ObservableObject {
    @Published private(set) var isProUser: Bool = false
    
    private let productID = "harmoniaplayer.pro"
    private var updateTask: Task<Void, Never>?
    
    init() {
        // Start listening for transactions
        updateTask = Task {
            await listenForTransactions()
        }
        
        // Check current entitlements
        Task {
            await refreshEntitlements()
        }
    }
    
    func refreshEntitlements() async {
        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == productID {
                    isProUser = true
                    return
                }
            }
        }
        isProUser = false
    }
    
    func purchasePro() async throws {
        guard let product = try await Product.products(for: [productID]).first else {
            throw IAPError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                await refreshEntitlements()
            }
        case .userCancelled:
            throw IAPError.userCancelled
        case .pending:
            throw IAPError.purchasePending
        @unknown default:
            throw IAPError.unknown
        }
    }
    
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }
    
    deinit {
        updateTask?.cancel()
    }
}

enum IAPError: Error {
    case productNotFound
    case userCancelled
    case purchasePending
    case unknown
}
```

---

## 5. SwiftUI Integration

### 5.1 App Entry Point

```swift
import SwiftUI

@main
struct HarmoniaPlayerApp: App {
    @StateObject private var appState: AppState
    
    init() {
        // Construct dependencies
        let factory = CoreFactory()
        let iapManager = StoreKitIAPManager()
        
        // Inject into AppState
        _appState = StateObject(
            wrappedValue: AppState(factory: factory, iap: iapManager)
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
```

### 5.2 View Implementation

```swift
struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Album art and track info
            trackInfoView
            
            // Waveform (if enabled)
            if appState.viewPreferences.isWaveformVisible {
                WaveformView()
            }
            
            // Progress bar
            progressBar
            
            // Transport controls
            transportControls
            
            // Playlist (if visible)
            if appState.viewPreferences.isPlaylistVisible {
                PlaylistView()
            }
        }
        .alert(
            "Playback Error",
            isPresented: $showError,
            presenting: appState.lastError
        ) { _ in
            Button("OK") {
                // Error acknowledged
            }
        } message: { error in
            Text(errorMessage(for: error))
        }
        .onChange(of: appState.lastError) { error in
            showError = error != nil
        }
    }
    
    private var trackInfoView: some View {
        VStack {
            if let track = appState.currentTrack {
                Text(track.title)
                    .font(.headline)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("No Track Playing")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    private var progressBar: some View {
        HStack {
            Text(formatTime(appState.currentTime))
                .font(.caption)
                .monospacedDigit()
            
            Slider(
                value: Binding(
                    get: { appState.currentTime },
                    set: { newValue in
                        try? appState.seek(to: newValue)
                    }
                ),
                in: 0...max(appState.duration, 1)
            )
            
            Text(formatTime(appState.duration))
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal)
    }
    
    private var transportControls: some View {
        HStack(spacing: 20) {
            Button(action: { /* Previous */ }) {
                Image(systemName: "backward.fill")
            }
            
            Button(action: togglePlayPause) {
                Image(systemName: playButtonIcon)
                    .font(.title)
            }
            
            Button(action: { appState.stop() }) {
                Image(systemName: "stop.fill")
            }
            
            Button(action: { /* Next */ }) {
                Image(systemName: "forward.fill")
            }
        }
        .padding()
    }
    
    private var playButtonIcon: String {
        appState.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill"
    }
    
    private func togglePlayPause() {
        do {
            if appState.playbackState == .playing {
                appState.pause()
            } else {
                try appState.play()
            }
        } catch {
            // Error will be shown via alert
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func errorMessage(for error: PlaybackError) -> String {
        switch error {
        case .unsupportedFormat(let msg):
            return msg
        case .fileNotFound:
            return "File not found"
        case .decodingFailed(let msg):
            return "Failed to decode: \(msg)"
        case .outputFailed(let msg):
            return "Audio output error: \(msg)"
        case .coreError(let msg):
            return msg
        }
    }
}
```

### 5.3 Playlist View

```swift
struct PlaylistView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        List {
            ForEach(appState.playlist.tracks) { track in
                TrackRow(
                    track: track,
                    isPlaying: appState.currentTrack?.id == track.id
                )
                .onTapGesture {
                    try? appState.play(trackID: track.id)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let track = appState.playlist.tracks[index]
                    appState.removeTrack(track.id)
                }
            }
            .onMove { from, to in
                appState.moveTrack(fromOffsets: from, toOffset: to)
            }
        }
    }
}

struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(track.title)
                    .font(.headline)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isPlaying {
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.accentColor)
            }
            
            if let duration = track.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
```

---

## 6. Testing Patterns

### 6.1 Mock Services

```swift
final class MockPlaybackService: PlaybackService {
    var state: PlaybackState = .idle
    var mockDuration: TimeInterval = 180
    var mockCurrentTime: TimeInterval = 0
    
    func load(url: URL) throws {
        state = .loading
        // Simulate successful load
        state = .idle
    }
    
    func play() throws {
        state = .playing
    }
    
    func pause() {
        state = .paused
    }
    
    func stop() {
        state = .stopped
        mockCurrentTime = 0
    }
    
    func seek(to seconds: TimeInterval) throws {
        mockCurrentTime = seconds
    }
    
    func currentTime() -> TimeInterval {
        return mockCurrentTime
    }
    
    func duration() -> TimeInterval {
        return mockDuration
    }
}
```

### 6.2 Unit Tests

```swift
import XCTest
@testable import HarmoniaPlayer

final class AppStateTests: XCTestCase {
    func testPlayPauseFlow() throws {
        // Arrange
        let mockService = MockPlaybackService()
        let mockFactory = MockCoreFactory(playbackService: mockService)
        let mockIAP = MockIAPManager(isProUser: true)
        let appState = AppState(factory: mockFactory, iap: mockIAP)
        
        // Add a test track
        appState.playlist.tracks.append(Track(
            id: UUID(),
            url: URL(fileURLWithPath: "/test.mp3"),
            title: "Test",
            artist: "Test Artist",
            album: "Test Album",
            duration: 180
        ))
        
        // Act & Assert
        try appState.play(trackID: appState.playlist.tracks[0].id)
        XCTAssertEqual(appState.playbackState, .playing)
        
        appState.pause()
        XCTAssertEqual(appState.playbackState, .paused)
        
        appState.stop()
        XCTAssertEqual(appState.playbackState, .stopped)
    }
    
    func testProFormatGating() {
        // Test that FLAC requires Pro
        let mockFactory = MockCoreFactory()
        let mockIAP = MockIAPManager(isProUser: false)
        let appState = AppState(factory: mockFactory, iap: mockIAP)
        
        let flacURL = URL(fileURLWithPath: "/test.flac")
        appState.load(urls: [flacURL])
        
        XCTAssertNotNil(appState.lastError)
        XCTAssertEqual(appState.playlist.tracks.count, 0)
    }
}
```

---

## 7. Architecture Patterns Summary

### 7.1 Dependency Flow

```
SwiftUI Views
    ↓ @EnvironmentObject
AppState
    ↓ injected via init
CoreFactory + IAPManager
    ↓ constructs
PlaybackService + TagReaderPort
    ↓ delegates to
HarmoniaCore Ports & Adapters
    ↓ use
Apple Frameworks (AVFoundation, CoreAudio)
```

### 7.2 Key Principles

1. **Dependency Injection:**
   - All services injected via constructors
   - No singletons (except at app entry point)
   - Clear dependency graph

2. **Synchronous Core:**
   - HarmoniaCore uses synchronous APIs
   - AppState wraps in async when needed
   - Errors thrown, not returned in state

3. **Observable State:**
   - All UI state in AppState
   - Published via @Published
   - SwiftUI observes changes

4. **Module Boundaries:**
   - Views depend on AppState only
   - AppState uses service interfaces
   - CoreFactory constructs implementations

---

## 8. Platform-Specific Notes

### Swift-Specific Patterns

- **@MainActor:** Ensures UI updates on main thread
- **Combine:** Used for reactive state updates
- **SwiftUI:** Declarative UI with @EnvironmentObject
- **async/await:** Used for IAP operations only

### Differences from C++ Implementation

The C++20 implementation will differ in:
- **State Management:** No @Published, use observer pattern
- **UI Framework:** Qt/GTK instead of SwiftUI
- **Memory Management:** Manual vs automatic reference counting
- **Threading:** Explicit thread management
- **Error Handling:** Result types vs exceptions

---

## 9. Cross-References

**HarmoniaCore Documentation:**
- [Services Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/04_services_impl.md)
- [Apple Adapters](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/02_01_apple_adapters_impl.md)

**HarmoniaPlayer Documentation:**
- [API Reference](api_reference.md) - Interface definitions
- [Architecture](architecture.md) - System design
- [Module Boundaries](module_boundary.md) - Dependency rules
- [Development Guide](development_guide.md) - Setup and guidelines

---

## 10. Common Pitfalls

### ❌ Don't Do This

```swift
// ❌ View directly using PlaybackService
struct PlayerView: View {
    let playbackService: PlaybackService
    
    var body: some View {
        Button("Play") {
            try? playbackService.play()
        }
    }
}

// ❌ AppState constructing adapters
init() {
    let logger = OSLogAdapter()
    self.playbackService = DefaultPlaybackService(...)
}

// ❌ Using async for HarmoniaCore calls
func play() async throws {
    try await playbackService.play()  // Wrong! It's synchronous
}
```

### ✅ Do This Instead

```swift
// ✅ View using AppState
struct PlayerView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Button("Play") {
            try? appState.play()
        }
    }
}

// ✅ AppState receiving services
init(factory: CoreFactory, iap: IAPManager) {
    self.playbackService = factory.makePlaybackService(...)
}

// ✅ Synchronous calls
func play() throws {
    try playbackService.play()
    playbackState = .playing
}
```

---

This implementation guide is Swift-specific. Future C++20 implementation will follow similar architectural principles but with platform-appropriate patterns.
