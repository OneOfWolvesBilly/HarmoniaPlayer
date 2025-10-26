# 🎧 HarmoniaPlayer — Architecture
```text
HarmoniaPlayer/
 ├─ Adapters/                              # Platform-specific implementations of Ports
 │   ├─ iOS/                               # iOS adapters (Free only)
 │   │   ├─ IOSAudioOutputImpl.swift       # AVAudioEngine output for iOS
 │   │   ├─ IOSFileAccessImpl.swift        # File access (read-only)
 │   │   └─ IOSTagReaderImpl.swift         # Metadata reader
 │   │   # (No TagWriter / FormatConverter on iOS)
 │   └─ macOS/                             # macOS adapters (Free + Pro)
 │       ├─ MacAudioOutputImpl.swift       # AVAudioEngine output for macOS
 │       ├─ MacFileAccessImpl.swift        # File read/write (sandbox-safe)
 │       ├─ MacFormatConverterImpl.swift   # Audio converter (FLAC/DSD etc., Pro)
 │       ├─ MacTagReaderImpl.swift         # Metadata reader
 │       └─ MacTagWriterImpl.swift         # Metadata editor (Pro)
 │
 ├─ App/                                   # Application layer (UI shell + DI)
 │   ├─ Shared/                            # Shared SwiftUI and ViewModels
 │   │   ├─ Bootstrap/                     # CompositionRoot (inject Adapters/UseCases)
 │   │   └─ UI/                            # RootView, PlayerView, QueueView, SettingsView
 │   ├─ iOS/                               # iOS app logic (Free only)
 │   │   ├─ AppDelegate.swift              # AVAudioSession, background audio
 │   │   ├─ iOSAppView.swift               # iOS app shell; calls CompositionRoot(.iOS)
 │   │   └─ iOSFilePicker.swift            # UIDocumentPicker bridge
 │   └─ macOS/                             # macOS app logic (Free + Pro)
 │       ├─ MacAppView.swift               # macOS app shell; calls CompositionRoot(.macOS)
 │       ├─ MacFileImporter.swift          # NSOpenPanel bridge
 │       └─ MacMenuCommands.swift          # Menu bar commands (File/Open, Preferences, …)
 │
 ├─ HarmoniaPlayer-iOS/                    # iOS Target (entry + assets + settings)
 │   ├─ Assets.xcassets                    # App icons / colors
 │   ├─ HarmoniaPlayer-iOS.entitlements    # Sandbox / capabilities
 │   ├─ HarmoniaPlayer_iOSApp.swift        # @main entry (opens App/iOS/iOSAppView)
 │   └─ Info.plist                         # Bundle metadata, background audio
 │
 ├─ HarmoniaPlayer-macOS/                  # macOS Target (entry + assets + settings)
 │   ├─ Assets.xcassets                    # App icons / accents
 │   ├─ HarmoniaPlayer-macOS.entitlements  # Sandbox / file access
 │   ├─ HarmoniaPlayer_macOSApp.swift      # @main entry (opens App/macOS/MacAppView)
 │   └─ Info.plist                         # Bundle metadata, IAP config
 │
 ├─ Packages/                              # Swift Package dependencies and modules
 │   └─ HarmoniaCore/                      # Core domain logic (pure Swift, no UI)
 │       ├─ LICENSE                        # MIT License (for Core module)
 │       ├─ Package.swift                  # SwiftPM configuration
 │       ├─ README.md                      # Internal module documentation
 │       ├─ Sources/
 │       │   └─ HarmoniaCore/
 │       │       ├─ Models/                # Domain entities (Track, Playlist, Artwork, …)
 │       │       ├─ Ports/                 # Abstract interfaces (AudioOutput, FileAccess, …)
 │       │       ├─ Services/              # Business services (Playback, Library, Settings)
 │       │       ├─ UseCases/              # Application actions (PlayTrack, Seek, Next, …)
 │       │       └─ Utils/                 # Helper algorithms (pure functions)
 │       │           └─ LRUCache.swift     # Cache for recently played items
 │       └─ Tests/
 │           └─ HarmoniaCoreTests/
 │               └─ PlaybackServiceTests.swift # Unit tests for playback logic
 │
 ├─ docs/                                  # Documentation (overview + detailed specs)
 │   ├─ adapters.overview.md               # Adapters layer spec
 │   ├─ app.ios.md                         # iOS app layer spec
 │   ├─ app.macos.md                       # macOS app layer spec
 │   ├─ app.shared.md                      # Shared UI + ViewModels spec
 │   ├─ architecture.md                    # English version (this file)
 │   ├─ core.structure.md                  # Core layer spec
 │   ├─ roadmap.md                         # Development roadmap outlining project phases and goals.
 │   ├─ spec.phase1.md                     # Technical specification for Phase 1 implementation.
 │   ├─ targets.ios.md                     # iOS target notes
 │   └─ targets.macos.md                   # macOS target notes
 │
 ├─ changelog.md                           # Historical changelog following Keep a Changelog format.
 ├─ LICENSE                                # MIT License for main project
 └─ README.md                              # Project overview and usage
```
