# HarmoniaPlayer

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013+%20%7C%20iOS%2016+-lightgrey.svg)](https://developer.apple.com)
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

### Current Development Status (2026-01-07)

**🚧 In Active Development:**
- macOS Free version (v0.1) - Foundation in progress
- iOS Free - Planned after macOS completion
- Target formats: MP3, AAC, ALAC, WAV, AIFF

**Development Timeline:**
- **This Week (Jan 7-10):** Complete macOS Free v0.1
- **Q1 2026 (Planned):** macOS Pro with FLAC/DSD support
- **Q2 2026:** iOS Free version
- **Q2-Q4 2026:** Linux HarmoniaCore (C++20) implementation

> **Note:** This is a reference implementation. Features marked as "planned" are non-binding targets for validation purposes.

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
- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

HarmoniaCore-Swift dependency is automatically fetched via SPM.

## Quick Start

*(App is not yet functional - in development)*

When complete:
1. **Launch** HarmoniaPlayer
2. **Add files** by clicking `+` or drag-and-drop
3. **Double-click** a track to play
4. **Use keyboard shortcuts**: `Space` to play/pause, `⌘→` for next track

See [User Guide](docs/user_guide.md) for planned features.

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
│       │   ├── macOS/             # macOS-specific code
│       │   │   └── Free/          # macOS Free version
│       │   ├── iOS/               # iOS-specific code (v0.3+)
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

### Milestones (Non-binding)

HarmoniaPlayer is developed as a **reference and validation application**
for exercising HarmoniaCore APIs in real-world scenarios.

The following milestones are **non-binding targets**, evaluated based on
validation readiness rather than delivery guarantees:

- **Q1 2026 (Target)**  
  Apple platform reference application for HarmoniaCore validation  
  (used internally for architecture and behavior review)

- **Future**  
  Additional platform validation targets may be explored after
  core behavior contracts stabilize.

Note: HarmoniaPlayer is **not** a deliverable commitment of the NLnet Core grant.
Its role is to support validation and integration of HarmoniaCore.

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
