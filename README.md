# HarmoniaPlayer

[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015.6+-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
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
│  SwiftUI (macOS)                │
└──────────────┬──────────────────┘
               │ SPM dependency
               │ (dev: local ../HarmoniaCore/apple-swift)
               │ (deploy: GitHub tag from HarmoniaCore-Swift)
┌──────────────▼──────────────────┐
│  HarmoniaCore-Swift             │  ← Swift Package
│  Audio engine + platform        │
│  adapters (AVFoundation)        │
│  (subtree split from            │
│   HarmoniaCore/apple-swift)     │
└──────────────┬──────────────────┘
               │ implements spec from
┌──────────────▼──────────────────┐
│  HarmoniaCore                   │  ← Specification + Source Repository
│  Architecture, Ports, Models    │
│  apple-swift/ + linux-cpp/      │
│  (linux-cpp/ deferred)          │
└─────────────────────────────────┘
```

**HarmoniaPlayer** provides the user interface and application logic (playlists, IAP, persistence).  
**HarmoniaCore-Swift** is a standalone Swift Package containing the audio engine and platform adapters. It is created by tagging a release in HarmoniaCore and using `git subtree split` to extract the `apple-swift/` directory into its own repository. HarmoniaPlayer references this package for deployment, pinning to a specific tagged version.  
**HarmoniaCore** is the source-of-truth repository where both Swift and C++ implementations live side by side. Because SPM cannot consume a subdirectory of a repository directly, the subtree split into HarmoniaCore-Swift is necessary to produce a valid Swift Package. During development, HarmoniaPlayer uses a local path reference (`../HarmoniaCore/apple-swift`) for rapid iteration.

## Features

### v0.1 Free (current target)

- Playlist-based audio playback (MP3, AAC, ALAC, WAV, AIFF)
- Multiple playlists with drag reorder, M3U8 import/export
- File and directory drag-and-drop with recursive scanning
- Mini Player, ReplayGain, shuffle, repeat modes
- File Info panel, keyboard shortcuts, macOS menu bar integration
- Persistence (playlists, settings survive relaunch)
- Localisation: English, 繁體中文, 日本語

### v0.2 Pro (planned)

- FLAC / DSD playback
- Tag Editor (ID3 / MP4 metadata editing)
- LRC synchronised lyrics
- Gapless playback
- StoreKit 2 In-App Purchase

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

# Select scheme: HarmoniaPlayer
# Product > Run (⌘R)
```

**Requirements:**
- macOS 15.6+
- Xcode 26 beta
- Swift 6

HarmoniaCore-Swift dependency: development uses local path (`../HarmoniaCore/apple-swift`); deployment uses a tagged GitHub release from [HarmoniaCore-Swift](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift).

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
- **[API Reference](docs/api_reference.md)** - Complete public interface reference
- **[Module Boundaries](docs/module_boundary.md)** - Dependency rules and constraints

### Development
- **[Development Guide](docs/development_guide.md)** - Setup and contribution guide
- **[Implementation Guide (Swift)](docs/implementation_guide_swift.md)** - Swift implementation patterns
- **[Workflow](docs/workflow.md)** - SDD → TDD → commit workflow
- **[Documentation Strategy](docs/documentation_strategy.md)** - Documentation policy

### User Documentation
- **[User Guide](docs/user_guide.md)** - Planned features and usage

## Development

### Repository Structure

```
App/HarmoniaPlayer/HarmoniaPlayer/
├── Shared/Models/        # AppState (split into 5 files), Track, Playlist, PlaybackError, ...
├── Shared/Services/      # Integration Layer (3 files), FileDropService, M3U8Service, IAP, ...
├── Shared/Views/         # ContentView, PlayerView, PlaylistView, FileInfoView, ...
├── macOS/Free/           # HarmoniaPlayerApp, HarmoniaPlayerCommands, MiniPlayer, Settings
├── en/zh-Hant/ja.lproj/  # Localisation (3 languages)
└── Assets.xcassets
```

For the complete file listing, see [Development Guide](docs/development_guide.md#project-structure).

### Contributing

See [Development Guide](docs/development_guide.md) for:
- Setting up development environment
- Code style guidelines
- Testing procedures
- Pull request process

### Milestones

- **v0.1** — Free tier feature complete → App Store
- **v0.2** — Pro tier via In-App Purchase

For detailed planning, see [Development Plan](docs/slice/HarmoniaPlayer_development_plan.md).

## Related Projects

- **[HarmoniaCore](https://github.com/OneOfWolvesBilly/HarmoniaCore)** - Specification and source repository (Swift + C++ side by side)
  - `apple-swift/` — Swift implementation of the audio engine
  - `linux-cpp/` — C++ implementation (deferred)
  - Contains Ports & Adapters architecture, platform-agnostic specifications
  - **Key Specs:**
    - [Architecture (Ports & Adapters)](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/01_architecture.md)
    - [Ports Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md)
    - [Services Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/04_services.md)
    - [Models & Error Handling](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/05_models.md)
- **[HarmoniaCore-Swift](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift)** - Standalone Swift Package (subtree split from HarmoniaCore `apple-swift/`)
  - Tagged releases define the version HarmoniaPlayer pins for deployment
  - Audio engine, platform adapters (AVFoundation), and port protocols

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