# Harmonia Player

A minimalist high-fidelity music player for **macOS**.  
Part of the [HarmoniaSuite](https://github.com/OneOfWolvesBilly/HarmoniaSuite) ecosystem.

Harmonia Player follows an **open-core** model with optional **Pro** features available via **App Store In-App Purchase (macOS)**.  
It is built on the Apple/Swift implementation of [**HarmoniaCore**](https://github.com/OneOfWolvesBilly/HarmoniaCore).

## Features

- Clean playback UI with SwiftUI
- Queue and playlist management
- Gapless playback (where supported)
- Metadata reading (ID3/MP4 tags)
- **macOS Pro (IAP):** FLAC/DSD playback, metadata editing, and format conversion

---

## Supported Formats

| Format | Codec | macOS (Free) | macOS Pro (IAP) | iOS (Media Library via AVFoundation) |
|---|---|---|---|---|
| MP3 | MPEG-1 Layer III | ✅ | ✅ | ✅ |
| AAC / ALAC | MPEG-4 AAC / Apple Lossless | ✅ | ✅ | ✅ |
| WAV / AIFF | PCM 16–24-bit | ✅ | ✅ | – *(Media Library does not expose arbitrary files)* |
| FLAC | Free Lossless Audio Codec | – | ✅ *(embedded decoder)* | – |
| DSD (DSF/DFF) | Direct Stream Digital | – | ✅ *(embedded decoder)* | – |

> **Note (iOS):** On iOS, Harmonia Player can only play tracks available via the system **Media Library** (Apple Music / iTunes–synced items) using **AVFoundation**.  
> **Direct file import/decoding is not available on iOS** (no Files app or sandbox-path playback).  
> Supported codecs on iOS are limited to **MP3**, **AAC**, and **ALAC**; **FLAC/DSD** are not available on iOS.
---

## Install (Source Build)
- Clone the repo and open `HarmoniaPlayer.xcworkspace` in Xcode.
- Select the **`HarmoniaPlayer-macOS`** target and build/run.

---

## Documents
- Architecture: [`docs/architecture.md`](./docs/architecture.md)
- Documentation strategy: [`docs/documentation.strategy.md`](./docs/documentation.strategy.md)
- Changelog: [`CHANGELOG.md`](./CHANGELOG.md)

---

## License
MIT © 2025 Chih-hao (Billy) Chen — see [`LICENSE`](./LICENSE).

**Contact:** harmonia.audio.project@gmail.com