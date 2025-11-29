# Harmonia Player

A minimalist high-fidelity music player for **macOS** and **iOS**.  
Part of the [HarmoniaSuite](https://github.com/OneOfWolvesBilly/HarmoniaSuite) ecosystem.

Harmonia Player follows an **open-core** model: the core player is **free**, with optional **Pro features** available via **App Store In-App Purchase (macOS only)**.  
Built on [**HarmoniaCore**](https://github.com/OneOfWolvesBilly/HarmoniaCore) — a cross-platform audio framework.

---

## Features

### Core Features (Free)
- ✅ Clean playback UI built with SwiftUI
- ✅ Music library management and scanning (macOS)
- ✅ Queue and playlist management
- ✅ Gapless playback (where supported)
- ✅ **Metadata reading** (ID3/MP4/Vorbis tags)
- ✅ Album artwork display
- ✅ EQ equalizer
- ✅ ReplayGain support (macOS)
- ✅ Keyboard shortcuts and media key support (macOS)

### Pro Features (macOS IAP)
- 🎵 **FLAC playback** (24-bit, 192kHz+ support)
- 🎵 **DSD playback** (DSF/DFF with DSD-to-PCM conversion)
- ✏️ **Metadata editing** (batch tag editing, artwork management)
- 🔄 **Format conversion** (batch convert between formats)
- 🎨 **Advanced UI customization**:
  - Custom background images
  - Curved frame effects (bamboo-basket style borders)
  - Non-destructive image editing along frame contours
  - Professional image adjustment (opacity, blur, color grading)

> **Note**: Pro features and availability to be determined based on development progress and user feedback.

---

## Supported Formats

| Format | Codec | macOS (Free) | macOS Pro (IAP) | iOS |
|--------|-------|--------------|-----------------|-----|
| MP3 | MPEG-1 Layer III | ✅ | ✅ | ✅ |
| AAC | MPEG-4 AAC | ✅ | ✅ | ✅ |
| ALAC | Apple Lossless | ✅ | ✅ | ✅ |
| WAV | PCM 16-24-bit | ✅ | ✅ | ❌* |
| AIFF | PCM 16-24-bit | ✅ | ✅ | ❌* |
| FLAC | Free Lossless | ❌ | ✅ | ❌ |
| DSD | DSF/DFF | ❌ | ✅ | ❌ |

\* *iOS can only access files in the system Media Library; WAV/AIFF typically not supported via Music app*

---

## Feature Comparison

| Feature | macOS (Free) | macOS Pro (IAP) | iOS |
|---------|--------------|-----------------|-----|
| **Playback Formats** |
| MP3, AAC, ALAC, WAV, AIFF | ✅ | ✅ | ✅ (MP3/AAC/ALAC only) |
| FLAC (Hi-Res) | ❌ | ✅ | ❌ |
| DSD (DSF/DFF) | ❌ | ✅ | ❌ |
| **Library Management** |
| Direct File Access & Scanning | ✅ | ✅ | ❌ (Media Library only) |
| Playlist Creation | ✅ | ✅ | ✅ |
| Smart Playlists | ✅ | ✅ | ❌ |
| **Metadata** |
| Tag Reading | ✅ | ✅ | ✅ |
| Tag Editing | ❌ | ✅ | ❌ |
| Batch Tag Editing | ❌ | ✅ | ❌ |
| Artwork Management | ❌ | ✅ | ❌ |
| **Audio Features** |
| EQ Equalizer | ✅ | ✅ | ✅ |
| ReplayGain | ✅ | ✅ | ❌ |
| Format Conversion | ❌ | ✅ | ❌ |
| **UI Customization** |
| Standard Themes | ✅ | ✅ | ✅ |
| Custom Backgrounds | ❌ | ✅ | ❌ |
| Curved Frame Effects | ❌ | ✅ | ❌ |
| Advanced Image Editing | ❌ | ✅ | ❌ |

---

## UI Customization (Pro Only)

Harmonia Player Pro offers advanced UI customization inspired by **ttPlayer** with professional image editing capabilities:

### Features
- 🖼️ **Custom Background Images**: Import your own artwork as player background
- 🎨 **Curved Frame Effects**: Apply bamboo-basket-style curved borders to your images
- ✂️ **Non-Destructive Editing**: Adjust images along frame contours (similar to Photoshop's warp/distort)
- 🎭 **Multiple Themes**: Save and switch between different custom layouts

### How It Works
1. Import your image as background
2. Select a frame template (curved borders, rounded corners, etc.)
3. Adjust image to fit the frame using control points
4. Fine-tune opacity, blur, and color grading
5. Save as a custom theme

> **Note**: This feature is exclusive to **macOS Pro** and requires in-app purchase.

---

## Platform-Specific Notes

### macOS
- ✅ Full feature support
- ✅ Direct file access and library scanning
- ✅ Metadata reading (free)
- ✅ FLAC/DSD support, metadata editing, format conversion (Pro IAP)
- ✅ Advanced UI customization (Pro IAP)

### iOS
- ⚠️ **Library Access Only**: Can only play music from your device's **Media Library** (Apple Music / iTunes-synced items)
- ⚠️ **No Direct File Import**: iOS sandbox restrictions prevent accessing arbitrary audio files
- ⚠️ **Limited Formats**: Only MP3, AAC, and ALAC are supported (no FLAC/DSD)
- ⚠️ **Read-Only Metadata**: Can read tags but cannot edit them
- ⚠️ **No Format Conversion**: iOS version is playback-only
- ⚠️ **No UI Customization**: iOS version uses standard player interface

---

## Installation

### macOS
1. Download from **Mac App Store** (coming soon)
2. Or build from source:
```bash
   git clone https://github.com/OneOfWolvesBilly/HarmoniaPlayer.git
   cd HarmoniaPlayer
   open HarmoniaPlayer.xcworkspace
```
   Select **HarmoniaPlayer-macOS** target and build/run.

### iOS
1. Download from **App Store** (coming soon)
2. Or use TestFlight for beta testing (link TBA)

---

## Development Status

**Current Focus**: Harmonia Player (macOS) - MVP Development

### Roadmap
- 🎯 **Q4 2025 - Q1 2026**: Harmonia Player (macOS) - Beta Release
- 🎯 **Q1 2026 - Q2 2026**: Harmonia Player (iOS) - Beta Release
- 🎯 **Q2 2026**: Harmonia Player Pro (macOS) - IAP Features Release
- 📋 **Q3 2026+**: Harmonia Core (C++20) for Linux support

### Built On
- [**HarmoniaCore**](https://github.com/OneOfWolvesBilly/HarmoniaCore) (Swift implementation)
  - Cross-platform audio framework (Swift/C++20)
  - Provides playback, decoding, and metadata services
  - Real-time audio rendering with lock-free architecture

---

## Documentation

- [Architecture Overview](./docs/architecture.md)
- [Documentation Strategy](./docs/documentation.strategy.md)
- [Changelog](./CHANGELOG.md)

---

## License

MIT © 2025 Chih-hao (Billy) Chen — see [`LICENSE`](./LICENSE).

**Contact**: harmonia.audio.project@gmail.com

---

## Support Development

If you find Harmonia Player useful, consider supporting its development:

[💖 PayPal](https://paypal.me/HarmoniaSuite) | [☕ Buy Me a Coffee](https://buymeacoffee.com/harmonia.suite.project)

---