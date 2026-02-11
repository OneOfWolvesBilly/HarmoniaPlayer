# 🎧 HarmoniaPlayer Development Guide

This document explains the development setup, architecture, and IAP integration for HarmoniaPlayer.

> **Note:** This guide reflects the planned architecture. Implementation has not yet begun.

---

## 🔗 Understanding the Repository Structure

HarmoniaPlayer is part of the **HarmoniaSuite** ecosystem:

### Main Repositories

1. **[HarmoniaCore](https://github.com/OneOfWolvesBilly/HarmoniaCore)** (Main Specification)
   - Contains Swift and C++20 implementations
   - Platform-agnostic specifications
   - Used for NLnet grant review
   - Structure:
     - `apple-swift/` - Swift implementation
     - `linux-cpp/` - C++20 implementation (planned)
     - `docs/specs/` - Platform-neutral specifications

2. **[HarmoniaCore-Swift](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift)** (SPM Package)
   - Subtree extracted from `HarmoniaCore/apple-swift/`
   - SPM-compatible package
   - Used as dependency by HarmoniaPlayer

3. **[HarmoniaPlayer](https://github.com/OneOfWolvesBilly/HarmoniaPlayer)** (This Repo)
   - Reference UI application
   - Validates HarmoniaCore functionality
   - Demonstrates best practices

### Repository Relationships

```
HarmoniaCore (Main)
├── apple-swift/              → Becomes → HarmoniaCore-Swift (SPM)
├── linux-cpp/                → Future
└── docs/specs/               → Specifications

HarmoniaPlayer (This Repo)
└── depends on → HarmoniaCore-Swift (via SPM)
```

**Key Architectural Documents:**
- [HarmoniaCore Architecture](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [HarmoniaCore Services](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
- [HarmoniaPlayer Architecture](architecture.md)

---

## 🚀 Setting Up Development Environment

### Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+
- Git

### Clone and Setup

```bash
# Clone HarmoniaPlayer
git clone https://github.com/OneOfWolvesBilly/HarmoniaPlayer.git
cd HarmoniaPlayer

# Open in Xcode (note the correct path)
open App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj

# HarmoniaCore-Swift will be automatically fetched via SPM
```

### Manual SPM Setup (if needed)

**In Xcode:**
1. File → Add Package Dependencies
2. Enter: `https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift.git`
3. Version: `0.1.0` or later
4. Add to target: `HarmoniaPlayer-macOS-Free`

**Verify Dependency:**
```swift
import HarmoniaCore  // Should import without errors

let logger = OSLogAdapter()
let clock = MonotonicClockAdapter()
// If this compiles, dependency is working
```

---

## 📂 Project Structure

```
HARMONIAPLAYER/                   # Repository root
├── App/
│   └── HarmoniaPlayer/           # Xcode project
│       ├── Shared/               # Cross-platform UI code (90%)
│       │   ├── Models/           # UI-level data models
│       │   │   ├── Track.swift
│       │   │   ├── Playlist.swift
│       │   │   ├── PlaybackState.swift
│       │   │   ├── PlaybackError.swift
│       │   │   ├── ViewPreferences.swift
│       │   │   └── AppState.swift
│       │   ├── Views/            # SwiftUI views
│       │   │   ├── PlayerView.swift
│       │   │   ├── PlaylistView.swift
│       │   │   └── TrackRow.swift
│       │   └── Services/
│       │       ├── CoreFactory.swift   # HarmoniaCore service construction
│       │       └── IAPManager.swift    # IAP management (macOS Pro)
│       ├── macOS/
│       │   └── Free/             # macOS Free app
│       │       ├── HarmoniaPlayer_macOSApp.swift
│       │       └── ContentView.swift
│       ├── iOS/                  # iOS apps (v0.3+)
│       ├── Tests/
│       │   ├── SharedTests/
│       │   └── macOSTests/
│       └── HarmoniaPlayer.xcodeproj/
├── docs/                         # Documentation
│   ├── architecture.md
│   ├── api_reference.md
│   ├── implementation_guide_swift.md
│   ├── module_boundary.md
│   ├── development_guide.md
│   ├── user_guide.md
│   └── ...
├── CHANGELOG.md
├── LICENSE
└── README.md
```

**Key Principles:**
- 90% of code in `Shared/` (cross-platform)
- 10% in `macOS/` or `iOS/` (platform-specific)
- HarmoniaCore provides all audio functionality
- Documentation lives in repo root for easy access

**See:** [Module Boundaries](module_boundary.md) for dependency rules.

---

## 📄 HarmoniaCore Integration

### Adding HarmoniaCore Dependency

**In Package.swift:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarmoniaPlayer",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(
            url: "https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift.git",
            from: "0.1.0"
        )
    ],
    targets: [
        .target(
            name: "HarmoniaPlayer",
            dependencies: [
                .product(name: "HarmoniaCore", package: "HarmoniaCore-Swift")
            ]
        )
    ]
)
```

### Architecture Pattern: Dependency Injection

HarmoniaPlayer follows a clean Ports & Adapters architecture:

```
Views → AppState → CoreFactory → HarmoniaCore Services
                 ↘ IAPManager
```

**Key Points:**
- **Views** depend on AppState only
- **AppState** receives services via dependency injection
- **CoreFactory** constructs all HarmoniaCore services
- **IAPManager** handles IAP state independently

### Example: CoreFactory

```swift
import HarmoniaCore

struct CoreFactory {
    /// Constructs PlaybackService with appropriate configuration
    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        let logger = OSLogAdapter()
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let audio = AVAudioEngineOutputAdapter(logger: logger)
        
        return DefaultPlaybackService(
            decoder: decoder,
            audio: audio,
            clock: clock,
            logger: logger
        )
    }
    
    /// Constructs TagReaderService for metadata reading
    func makeTagReaderService() -> TagReaderService {
        let logger = OSLogAdapter()
        let tagReaderPort = AVMetadataTagReaderAdapter(logger: logger)
        return DefaultTagReaderService(tagReaderPort: tagReaderPort)
    }
}
```

### Example: AppState Integration

**IMPORTANT:** AppState does NOT construct services directly. Services are injected via CoreFactory.

```swift
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
    private let tagReaderService: TagReaderService
    private let iapManager: IAPManager
    
    // MARK: - Initialization (Dependency Injection)
    init(factory: CoreFactory, iap: IAPManager) {
        self.iapManager = iap
        self.isProUser = iap.isProUser
        
        // CoreFactory constructs services based on Pro status
        self.playbackService = factory.makePlaybackService(
            isProUser: iap.isProUser
        )
        self.tagReaderService = factory.makeTagReaderService()
    }
    
    // MARK: - Playback Control (synchronous, throws on error)
    func play() throws {
        try playbackService.play()
        playbackState = .playing
        lastError = nil
    }
    
    func pause() {
        playbackService.pause()
        playbackState = .paused
    }
    
    func stop() {
        playbackService.stop()
        playbackState = .stopped
        currentTrack = nil
    }
    
    func seek(to time: TimeInterval) throws {
        try playbackService.seek(to: time)
        currentTime = time
    }
    
    // MARK: - File Loading with Metadata
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
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        if let coreError = error as? CoreError {
            switch coreError {
            case .notFound(let msg):
                lastError = .fileNotFound(URL(string: msg) ?? URL(fileURLWithPath: "/"))
            case .unsupported(let msg):
                lastError = .unsupportedFormat(msg)
            default:
                lastError = .coreError(coreError.description)
            }
        } else {
            lastError = .coreError(error.localizedDescription)
        }
    }
}
```

**Key Architectural Points:**
1. **Synchronous Core:** All HarmoniaCore methods are synchronous (no `async`)
2. **Dependency Injection:** Services come from CoreFactory, not constructed in AppState
3. **Error Handling:** Errors are thrown and mapped to UI-friendly types
4. **Service Abstraction:** TagReaderService wraps HarmoniaCore's TagReaderPort for application use

**See:**
- [API Reference](api_reference.md) for interface definitions
- [Implementation Guide (Swift)](implementation_guide_swift.md) for complete implementation examples
- [Module Boundaries](module_boundary.md) for dependency rules
- [HarmoniaCore Services](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md) for service contracts

### Updating HarmoniaCore Dependency

When HarmoniaCore-Swift releases a new version:

```bash
# In Xcode
File → Packages → Update to Latest Package Versions

# Or via command line
swift package update
```

---

## 🧪 Testing with Local HarmoniaCore

If you're developing both HarmoniaCore and HarmoniaPlayer simultaneously:

### Option 1: Local Package Override (Recommended)

**In Xcode:**
1. File → Packages → Resolve Package Versions
2. Right-click `HarmoniaCore-Swift` in project navigator
3. Select "Use Local Package..."
4. Choose local folder: `../HarmoniaCore-Swift`

### Option 2: Package.swift Override

```swift
// For local development only
dependencies: [
    .package(path: "../HarmoniaCore-Swift")
]
```

⚠️ **Don't commit this!** Revert before pushing:
```swift
// Revert to remote before committing
dependencies: [
    .package(url: "https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift.git", from: "0.1.0")
]
```

---

## 🔒 IAP Integration (macOS Pro)

### Overview

HarmoniaPlayer follows a clean separation for IAP:

```
UI Layer (Views)
    ↓ observes isProUser
Application Layer (AppState)
    ↓ uses
Integration Layer (IAPManager)
    ↓ manages
StoreKit 2
```

### IAPManager Interface

```swift
protocol IAPManager: AnyObject {
    var isProUser: Bool { get }
    
    func refreshEntitlements() async
    func purchasePro() async throws
}
```

### Implementation Example

```swift
import StoreKit

@MainActor
final class StoreKitIAPManager: IAPManager, ObservableObject {
    @Published private(set) var isProUser: Bool = false
    
    private let productID = "harmoniaplayer.pro"
    
    init() {
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
            if case .verified(_) = verification {
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
}
```

### Format Gating Pattern

Pro features are gated at the AppState level, not in HarmoniaCore:

```swift
func load(urls: [URL]) {
    for url in urls {
        // Check format requirements
        let ext = url.pathExtension.lowercased()
        let requiresPro = ["flac", "dsd", "dsf", "dff"].contains(ext)
        
        if requiresPro && !isProUser {
            // Show paywall or skip
            lastError = .unsupportedFormat("FLAC/DSD playback requires Pro")
            continue
        }
        
        // Proceed with loading
        do {
            let track = try enrichTrack(url: url)
            playlist.tracks.append(track)
        } catch {
            handleError(error)
        }
    }
}
```

### UI Integration

```swift
struct PlayerView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack {
            if !appState.isProUser {
                proFeatureBanner
            }
            playlistView
            transportControls
        }
    }
    
    private var proFeatureBanner: some View {
        HStack {
            Text("Upgrade to Pro for FLAC/DSD support")
            Button("Upgrade") {
                Task {
                    try? await appState.iapManager.purchasePro()
                }
            }
        }
    }
}
```

**Important IAP Rules:**
- ❌ Never construct services based on IAP inside HarmoniaCore
- ✅ CoreFactory receives `isProUser` flag and chooses configuration
- ✅ AppState enforces format restrictions before loading
- ✅ UI shows upgrade prompts for Pro features

---

## 🎯 Development Workflow

### Adding a New Feature

1. **Define model in `Shared/Models/`**
   ```swift
   // Shared/Models/PlaybackSpeed.swift
   enum PlaybackSpeed: Double, CaseIterable {
       case slow = 0.5
       case normal = 1.0
       case fast = 1.5
   }
   ```

2. **Add to AppState**
   ```swift
   @Published var playbackSpeed: PlaybackSpeed = .normal
   
   func setPlaybackSpeed(_ speed: PlaybackSpeed) {
       self.playbackSpeed = speed
       // Update playback service if needed
   }
   ```

3. **Create UI in `Shared/Views/`**
   ```swift
   // Shared/Views/SpeedControlView.swift
   struct SpeedControlView: View {
       @EnvironmentObject var appState: AppState
       
       var body: some View {
           Picker("Speed", selection: $appState.playbackSpeed) {
               ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                   Text("\(speed.rawValue)x").tag(speed)
               }
           }
       }
   }
   ```

4. **Write tests**
   ```swift
   // Tests/SharedTests/AppStateTests.swift
   func testPlaybackSpeedChange() {
       let factory = CoreFactory()
       let iap = MockIAPManager()
       let appState = AppState(factory: factory, iap: iap)
       
       appState.setPlaybackSpeed(.fast)
       
       XCTAssertEqual(appState.playbackSpeed, .fast)
   }
   ```

### Running Tests

```bash
# Run all tests
swift test

# Or in Xcode
Product > Test (⌘U)
```

---

## 📚 Documentation References

### HarmoniaPlayer Docs (This Repo)
- [Architecture](architecture.md) - System architecture
- [API Reference](api_reference.md) - Interface definitions
- [Implementation Guide (Swift)](implementation_guide_swift.md) - Swift-specific patterns
- [Module Boundaries](module_boundary.md) - Dependency rules
- [User Guide](user_guide.md) - How to use the app
- [Documentation Strategy](documentation_strategy.md) - Documentation policy

### HarmoniaCore Specs (Main Repository)

**Platform-Agnostic Specifications:**
- [Architecture Overview](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md) - Ports & Adapters pattern
- [Adapters Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/02_adapters.md) - Platform adapters
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md) - Port interfaces
- [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md) - Service contracts
- [Models Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md) - Data models

**Implementation Guides:**
- [Apple Adapters Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/02_01_apple_adapters_impl.md)
- [Ports Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/03_ports_impl.md)
- [Services Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/04_services_impl.md)

### HarmoniaCore-Swift (Package)
- [Swift Package README](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift/blob/main/README.md)

---

## 🧱 Code Style Guidelines

### SwiftUI Views

- Use `@EnvironmentObject` for AppState
- Extract reusable components
- Keep view bodies small and readable

**Good:**
```swift
struct PlayerView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack {
            albumArtView
            progressBar
            transportControls
        }
    }
    
    private var albumArtView: some View {
        // Implementation
    }
}
```

**Bad:**
```swift
struct PlayerView: View {
    let playbackService: PlaybackService  // ❌ Don't inject services directly
}
```

### State Management

- Use `@Published` for UI-observable state
- Keep business logic in AppState
- Use `@MainActor` for UI updates

**Good:**
```swift
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var playbackState: PlaybackState
    
    func play() throws {
        try playbackService.play()
        playbackState = .playing
    }
}
```

### Error Handling

- Always handle errors from HarmoniaCore
- Map to UI-friendly error types
- Log for debugging

```swift
func play() {
    do {
        try playbackService.play()
        playbackState = .playing
        lastError = nil
    } catch {
        handleError(error)
    }
}

private func handleError(_ error: Error) {
    if let coreError = error as? CoreError {
        switch coreError {
        case .notFound(let msg):
            lastError = .fileNotFound(URL(string: msg) ?? URL(fileURLWithPath: "/"))
        case .unsupported(let msg):
            lastError = .unsupportedFormat(msg)
        default:
            lastError = .coreError(coreError.description)
        }
    } else {
        lastError = .coreError(error.localizedDescription)
    }
}
```

---

## 🐛 Debugging

### Logging

HarmoniaCore uses `OSLog`:

```swift
import OSLog

let logger = Logger(subsystem: "HarmoniaPlayer", category: "Debug")
logger.info("Playback started")
logger.error("Failed to load: \(error)")
```

View logs in Console.app or Xcode Console.

### Breakpoints

Set breakpoints in:
- `AppState.play()` - Playback control
- `AppState.load(urls:)` - File loading
- `PlayerView.body` - UI updates

### Common Issues

**Issue:** Service methods not found
- **Solution:** Verify HarmoniaCore-Swift package is up to date

**Issue:** "Cannot find type 'PlaybackService'"
- **Solution:** Check `import HarmoniaCore` is present

**Issue:** IAP not working in debug
- **Solution:** Use StoreKit Configuration file for testing

---

## ⚠️ App Store Review Considerations

| Phase | Recommendation |
|-------|----------------|
| **Initial submission** | Include only core functionality (Free). Keep Pro code present but not visually exposed until IAP is approved. |
| **After IAP approval** | Enable visible Paywall and Pro feature entry points. |
| **External payments** | ❌ Never include PayPal or Buy Me a Coffee links inside the app. Such links belong only in GitHub/README. |

---

## ✅ Summary

- **Dependency Injection**: Services injected via CoreFactory and IAPManager
- **Synchronous Core**: HarmoniaCore uses synchronous APIs
- **Module Boundaries**: Clear separation between UI, App, and Integration layers
- **IAP Gating**: Format restrictions enforced in AppState, not in HarmoniaCore
- **Cross-platform**: 90% shared code between macOS/iOS
- **Testing**: Unit tests with mocked services

**Key Architectural Principles:**
1. Views depend on AppState only
2. AppState receives services via dependency injection
3. CoreFactory constructs all HarmoniaCore services
4. IAPManager manages purchase state independently
5. Error handling through exceptions, not state

---

## 📧 Contact

For questions about HarmoniaPlayer development or the Harmonia Suite:

- **Email**: [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub**: [@OneOfWolvesBilly](https://github.com/OneOfWolvesBilly)

Please use the email for technical discussions, bug reports, or contribution inquiries.
