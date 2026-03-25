# HarmoniaPlayer

[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015+-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)
[![Development](https://img.shields.io/badge/Status-In%20Development-yellow.svg)]()

Reference music player application built with [HarmoniaCore](https://github.com/OneOfWolvesBilly/HarmoniaCore).

## What is HarmoniaPlayer?

**Harmonia Player** is a reference audio player product.

This repository, **HarmoniaPlayer**, contains the application codebase built on top of **HarmoniaCore**, a cross-platform audio framework that provides identical behavior on Apple (Swift) and Linux (C++20) platforms.

It serves as:

1. **Reference Implementation** - Shows how to use HarmoniaCore APIs
2. **Validation Tool** - Ensures HarmoniaCore works correctly
3. **Standalone App** - Fully functional music player

### Relationship with HarmoniaCore

```
┌─────────────────────────────────┐
│  HarmoniaPlayer (this repo)     │  ← UI Application
│  SwiftUI + AppKit/UIKit         │
└──────────────┬──────────────────┘
               │ uses via SPM
┌──────────────▼──────────────────┐
│  HarmoniaCore-Swift (package)   │  ← Swift Package
│  Subtree from HarmoniaCore      │
└──────────────┬──────────────────┘
               │ extracted from
┌──────────────▼──────────────────┐
│  HarmoniaCore (main spec)       │  ← Main Repository
│  apple-swift/ + linux-cpp/      │
└─────────────────────────────────┘
```

**HarmoniaPlayer** provides the user interface.  
**HarmoniaCore-Swift** provides the audio engine (SPM package).  
**HarmoniaCore** contains specifications and implementations.

## Features

### Current Development Status (2026-03-25)

**✅ Completed:**
- Slices 1–6: core architecture, audio playback, SwiftUI UI, menu bar, keyboard shortcuts

**🚧 In Active Development:**
- Slice 7: persistence, multiple playlists, M3U8 import/export, volume control,
  column customization, File Info Panel, UI localisation (24 languages)

**Planned:**
- Slice 8 (v0.1): UndoManager, Mini Player, ReplayGain
- Slice 9 (v0.2 Pro): StoreKit 2 IAP, Tag Editor, FLAC/DSD unlock

**Supported formats:**
- Free: MP3, AAC, ALAC, WAV, AIFF
- Pro (v0.2): all Free formats + FLAC, DSD

## Installation

### Download Pre-Built App

*(Not yet available - currently in active development)*

### Build from Source

```bash
# Clone repository
git clone https://github.com/OneOfWolvesBilly/HarmoniaPlayer.git
cd HarmoniaPlayer

# Open in Xcode
open App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj

# Select scheme: HarmoniaPlayer-macOS-Free
# Product > Run (⌘R)
```

**Requirements:**
- macOS 15.0+ (Sequoia)
- Xcode 26 beta
- Swift 6

HarmoniaCore-Swift dependency is automatically fetched via SPM.

## Quick Start

1. **Launch** HarmoniaPlayer
2. **Add files** by clicking `+` or drag-and-drop
3. **Double-click** a track to play
4. **Use keyboard shortcuts**: `Space` to play/pause, `⌘→` for next track, `⌘←` for previous track
5. **Repeat modes**: cycle through Off → Repeat All → Repeat One

See [User Guide](docs/user_guide.md) for full feature documentation.

## Documentation

### Architecture & Specifications
- **[Architecture](docs/architecture.md)** - System design and C4 diagrams
- **[API Specification](docs/api_spec_apple_swift.md)** - Application-facing API
- **[Module Boundaries](docs/module_boundary.md)** - Dependency rules and constraints

### Development
- **[Development Guide](docs/development_guide.md)** - Setup and contribution guide
- **[Documentation Strategy](docs/documentation_strategy.md)** - Documentation policy

### User Documentation
- **[User Guide](docs/user_guide.md)** - Planned features and usage

## Development

### Repository Structure

```
HARMONIAPLAYER/
├── App/
│   └── HarmoniaPlayer/
│       ├── HarmoniaPlayer/        # Source files
│       │   ├── Shared/            # Cross-platform code (90%)
│       │   │   ├── Models/        # Data models
│       │   │   ├── Views/         # SwiftUI views
│       │   │   └── Services/      # HarmoniaCore integration
│       │   │       └── HarmoniaCoreProvider.swift
│       │   ├── macOS/             # macOS-specific code
│       │   │   └── Free/          # macOS Free version
│       │   ├── iOS/               # iOS-specific code (future)
│       │   ├── Assets.xcassets
│       │   ├── ContentView.swift
│       │   └── HarmoniaPlayerApp.swift
│       ├── Tests/                 # Unit and UI tests
│       └── HarmoniaPlayer.xcodeproj/
├── docs/                          # Documentation
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### Contributing

See [Development Guide](docs/development_guide.md) for:
- Setting up development environment
- Code style guidelines
- Testing procedures
- Pull request process

### Milestones

- **v0.1** — Free tier feature complete (Slices 1–8)
- **v0.2** — Pro tier: Tag Editor + FLAC/DSD via App Store IAP (Slice 9)

For the full slice breakdown and scope evolution, see
[Development Plan](docs/slice/HarmoniaPlayer_development_plan.md).

## Related Projects

- **[HarmoniaCore](https://github.com/OneOfWolvesBilly/HarmoniaCore)** - Main specification repository
  - Contains Swift and C++20 implementations
  - Platform-agnostic specifications
  - Cross-platform behavior documentation
  - **Key Specs:**
    - [Architecture (Ports & Adapters)](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
    - [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
    - [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
    - [Models & Error Handling](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)


- **[HarmoniaCore-Swift](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift)** - Swift package
  - Extracted from `HarmoniaCore/apple-swift/`
  - Used as dependency in this project
  - Supports macOS 13+ and iOS 16+

## License

MIT License - see [LICENSE](LICENSE)

Copyright (c) 2025 Chih-hao (Billy) Chen

## Contact

- **Email**: [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub**: [@OneOfWolvesBilly](https://github.com/OneOfWolvesBilly)
- **Project**: [HarmoniaPlayer](https://github.com/OneOfWolvesBilly/HarmoniaPlayer)

For any questions about the Harmonia Suite (HarmoniaCore, HarmoniaPlayer), please use the email above.

- **Issues**: [Report bugs](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/issues)
- **Discussions**: [Feature requests](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/discussions)