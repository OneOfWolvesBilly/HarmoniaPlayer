# 🎵 Harmonia Player

A minimalist high-fidelity music player for macOS and iOS (iPadOS).  
Open-core under MIT: all source is public; advanced features are unlocked via App Store IAP.

---

## Overview

- **macOS & iOS targets in one workspace**, sharing a reusable core.
- **Open-Core + IAP Locked**: code is open; Pro features require an in-app purchase.
- **No database**: uses the file system and M3U8 playlists.
- **Privacy-first**: no telemetry, no analytics, no background network calls.

---

## Platforms

- **macOS**: native SwiftUI app; supports menu commands and sandboxed file access.  
- **iOS/iPadOS**: native SwiftUI app; supports background audio and file picker.

---

## Features

| Category | Free | Pro (IAP unlock) |
|---|---|---|
| Playback formats | MP3, AAC, WAV, AIFF | + FLAC, APE, ALAC, DSD |
| Metadata | ID3v2.4 / FLAC tags, CUE, embedded artwork & lyrics | Same |
| Audio pipeline | — | Bit-perfect path, sample-rate sync, ReplayGain |
| Conversion | — | FLAC/APE/DSD → AAC/ALAC/MP3 |
| Playlists | M3U8, no DB | Same |
| Privacy | No telemetry | No telemetry |

> Pro code lives in this repo but is **runtime-gated** by IAP.

---

## Architecture

- **App/**: platform shells (`macOS/`, `iOS/`, `Shared/`)
- **Features/**: `Free/` and `Pro/` UI + ViewModels (Pro paths call the IAP gate)
- **Adapters/**: platform-specific implementations behind protocols (ports)
- **Packages/HarmoniaCore/** (SPM): domain models + use cases + ports (MIT)
- **StoreKit/**: IAP manager + paywall UI

```
HarmoniaPlayer/
  HarmoniaPlayer.xcworkspace
  App/
    macOS/
    iOS/
    Shared/
  Features/
    Free/
    Pro/
  Adapters/
    AudioSession/
    FileAccess/  ...
  Packages/
    HarmoniaCore/
      Sources/HarmoniaCore/
      Tests/HarmoniaCoreTests/
      Package.swift
  StoreKit/
    IAPManager.swift
    PaywallView.swift
  README.md
```

---

## Open-Core & IAP Model

- License: **MIT** for the entire codebase.  
- Distribution: App Store; **Pro features require IAP** (`harmonia.pro.unlock`).  
- Runtime gate (example):

```swift
guard IAPManager.shared.isProUser else {
    showPaywall()
    return
}
// Pro-only action...
```

**App Store compliance**:
- Paid features are unlocked **only via IAP** (Guideline 3.1.1).  
- No external payment links in-app.  
- No dynamic code loading; all dependencies are built into the app.  
- “Free” and “Pro” coexist in one binary to avoid Guideline 4.3 (duplication).

For implementation details, see the developer guide:  
`docs/DEVELOPMENT_GUIDE.md` (architecture, IAP flow, code examples).

---

## Build from Source

**Requirements**: Xcode 15+, Swift 5.9+, macOS 13+.

1. Clone this repository.
2. Open `HarmoniaPlayer.xcworkspace`.
3. Select a scheme:
   - `Harmonia Player (macOS)`
   - `Harmonia Player (iOS)`
4. Run. (Pro features are visible but gated until an IAP purchase in the shipped build.)

> During development you can stub IAP state; production builds must use StoreKit 2.

---

## Roadmap

- Short term: macOS/iOS parity, playlist enhancements, lyric sync polish.  
- Mid term: Pro transcoding UX, AUv3 host (Pro), basic library views (still DB-less).  
- Long term: optional plugin SDK; iCloud/documents integration via adapters.

---

## Contributing

Issues and PRs are welcome for **core and free features**.  
For Pro behavior, please avoid removing the IAP gate in PRs—discussions are welcome in issues first.

---

## License

**MIT** © Chih-hao (Billy) Chen.  
This project is part of the HarmoniaSuite ecosystem.

---

## 💖 Support the Project

If you enjoy this project, consider supporting the  
[HarmoniaSuite ecosystem](https://github.com/OneOfWolvesBilly/HarmoniaSuite#funding--support).
