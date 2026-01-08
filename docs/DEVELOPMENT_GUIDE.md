# 🎧 HarmoniaPlayer Development Guide

This document explains the development setup, architecture, and IAP integration for HarmoniaPlayer.

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
│       │   │   └── AppState.swift
│       │   ├── Views/            # SwiftUI views
│       │   │   ├── PlayerView.swift
│       │   │   ├── PlaylistView.swift
│       │   │   └── TrackRow.swift
│       │   └── Services/
│       │       └── CoreFactory.swift   # HarmoniaCore integration
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

### Using HarmoniaCore Services

**Example: AppState Integration**

```swift
import HarmoniaCore

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTrack: Track?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    // MARK: - Services (from HarmoniaCore)
    private let playbackService: PlaybackService
    private let logger: LoggerPort
    
    // MARK: - Initialization
    init() {
        // Create HarmoniaCore services
        let logger = OSLogAdapter(subsystem: "HarmoniaPlayer", category: "App")
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let audio = AVAudioEngineOutputAdapter(logger: logger)
        
        self.logger = logger
        self.playbackService = DefaultPlaybackService(
            decoder: decoder,
            audio: audio,
            clock: clock,
            logger: logger
        )
    }
    
    // MARK: - Playback Control
    func play() {
        do {
            try playbackService.play()
            playbackState = playbackService.state
        } catch {
            logger.error("Failed to play: \(error)")
        }
    }
    
    func pause() {
        playbackService.pause()
        playbackState = playbackService.state
    }
}
```

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

## 🔒 Core Principles for IAP Integration

### Principle 1: Centralized IAP State Management

All purchase state is managed by **StoreKit/IAPManager.swift**:

```swift
final class IAPManager: ObservableObject {
    static let shared = IAPManager()
    @Published var isProUser: Bool = false

    func purchasePro() async throws {
        // StoreKit 2 purchase logic
    }
    
    func restorePurchases() async throws {
        // Restore logic
    }
}
```

### Principle 2: Runtime IAP Locking

Every Pro entry point checks IAP status before execution:

```swift
import HarmoniaCore

func loadTrack(url: URL) {
    // Check if format requires Pro
    if url.pathExtension == "flac" {
        guard IAPManager.shared.isProUser else {
            NotificationCenter.default.post(
                name: .showPaywall,
                object: "FLAC Playback"
            )
            return
        }
        // Use Pro decoder
        #if HARMONIA_PRO
        let decoder = ProDecoderAdapter(logger: logger)
        #endif
    } else {
        // Free playback logic
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
    }
}
```

### Principle 3: UI-Level Paywall Integration

UI elements for Pro functionality should be disabled for non-Pro users:

```swift
struct AudioSettingsView: View {
    @ObservedObject var iapManager = IAPManager.shared
    @State private var bitPerfectEnabled = false

    var body: some View {
        VStack {
            Toggle("Bit-perfect Output", isOn: $bitPerfectEnabled)
                .disabled(!iapManager.isProUser)
                .opacity(iapManager.isProUser ? 1.0 : 0.4)

            if !iapManager.isProUser {
                Button("Unlock Pro Features") {
                    // Show PaywallView
                }
            }
        }
    }
}
```

---

## 🎯 Development Workflow

### Adding a New Feature

1. **Implement business logic in `Shared/`**
   ```swift
   // Shared/Models/AppState.swift
   func addToPlaylist(_ track: Track) {
       playlist.append(track)
   }
   ```

2. **Create UI in `Shared/Views/`**
   ```swift
   // Shared/Views/PlaylistView.swift
   struct PlaylistView: View {
       @EnvironmentObject var appState: AppState
       
       var body: some View {
           // UI implementation
       }
   }
   ```

3. **Add platform-specific code if needed**
   ```swift
   // macOS/Free/ContentView.swift
   #if os(macOS)
   .toolbar {
       // macOS-specific toolbar
   }
   #endif
   ```

4. **Write tests**
   ```swift
   // Tests/SharedTests/AppStateTests.swift
   func testAddToPlaylist() {
       let appState = AppState()
       let track = Track(url: testURL, title: "Test")
       
       appState.addToPlaylist(track)
       
       XCTAssertEqual(appState.playlist.count, 1)
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
- [Architecture](docs/architecture.md) - App structure
- [User Guide](docs/user_guide.md) - How to use the app
- [Development Guide](docs/development_guide.md) - This file
- [Documentation Strategy](docs/documentation_strategy.md) - Documentation policy

### HarmoniaCore Specs (Main Repository)

**Platform-Agnostic Specifications:**
- [Architecture Overview](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
- [Adapters Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/02_adapters.md)
- [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
- [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
- [Models Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)

**Implementation Guides:**
- [Apple Adapters Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/02_01_apple_adapters_impl.md)
- [Ports Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/03_ports_impl.md)
- [Services Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/04_services_impl.md)
- [Models Implementation](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/05_models_impl.md)

### HarmoniaCore-Swift (Package)
- [Swift Package README](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift/blob/main/README.md)

---

## ⚠️ App Store Review Considerations

| Phase | Recommendation |
|-------|----------------|
| **Initial submission** | Include only core functionality (Free). Keep Pro code present but not visually exposed until IAP is approved. |
| **After IAP approval** | Enable visible Paywall and Pro feature entry points. |
| **External payments** | ❌ Never include PayPal or Buy Me a Coffee links inside the app. Such links belong only in GitHub/README. |

---

## 🧱 Code Style Guidelines

### SwiftUI Views

- Use `@EnvironmentObject` for shared state
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
            stateIndicator
        }
    }
    
    private var albumArtView: some View {
        // Implementation
    }
}
```

### State Management

- Use `@Published` for UI-observable state
- Keep business logic in AppState or ViewModels
- Use `@MainActor` for UI updates

### Error Handling

- Always handle `CoreError` cases
- Provide user-friendly error messages
- Log errors for debugging

```swift
do {
    try playbackService.load(url: url)
} catch let error as CoreError {
    switch error {
    case .notFound(let msg):
        showAlert("File not found", message: msg)
    case .unsupported(let msg):
        showAlert("Format not supported", message: msg)
    default:
        showAlert("Error", message: error.description)
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
- `PlaylistView.handleImport()` - File loading
- `PlayerView.body` - UI updates

---

## ✅ Summary

- **Single public repo**: Transparent development
- **HarmoniaCore-Swift dependency**: Provides all audio functionality
- **IAP gating**: Protects Pro features without hiding code
- **Cross-platform**: 90% shared code between macOS/iOS
- **Fully compliant**: Satisfies Apple's IAP-only monetization guidelines

---

## 📧 Contact

For questions about HarmoniaPlayer development or the Harmonia Suite:

- **Email**: [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub**: [@OneOfWolvesBilly](https://github.com/OneOfWolvesBilly)

Please use the email for technical discussions, bug reports, or contribution inquiries.
