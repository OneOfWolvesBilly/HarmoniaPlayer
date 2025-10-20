# 🎧 Harmonia Player Development Guide

This document explains the structure, Open-Core licensing model, and IAP integration used in **Harmonia Player**.

---

## 🚀 Project Structure

All source code (including paid feature implementations) lives in a **single public GitHub repository**, divided by functionality:

```
HarmoniaPlayer/
 ├─ App/
 │  ├─ macOS/                 # macOS-specific (AppKit/MenuBar Commands)
 │  ├─ iOS/                   # iOS/iPadOS-specific (Background Session Setup)
 │  └─ Shared/                # Common startup logic and root views
 ├─ Features/
 │  ├─ Free/                  # Free-tier UI/ViewModels
 │  └─ Pro/                   # Pro features (IAP Locked)
 ├─ Adapters/
 │  ├─ AudioSession/
 │  │  ├─ AudioSessionPort.swift
 │  │  ├─ MacAudioSessionImpl.swift
 │  │  └─ iOSAudioSessionImpl.swift
 │  ├─ FileAccess/
 │  │  ├─ FileAccessPort.swift
 │  │  ├─ MacFileAccessImpl.swift
 │  │  └─ iOSFileAccessImpl.swift
 │  └─ ... (other platform-differentiated modules)
 ├─ Packages/
 │  └─ HarmoniaCore/
 │     ├─ Sources/HarmoniaCore/
 │     └─ Package.swift
 ├─ StoreKit/
 │  ├─ IAPManager.swift
 │  └─ PaywallView.swift
 ├─ README.md
 └─ LICENSE (MIT)
```

---

## 🔑 Core Principles for IAP Integration

### Principle 1: Centralized IAP State Management

All purchase state is managed by **StoreKit/IAPManager.swift**, which persists unlock status.

```swift
final class IAPManager: ObservableObject {
    static let shared = IAPManager()
    @Published var isProUser: Bool = false

    func purchasePro() { /* StoreKit purchase logic */ }
    func restorePurchases() { /* Restore logic */ }
}
```

### Principle 2: Runtime IAP Locking

Every Pro entry point checks IAP status before execution:

```swift
import StoreKit

func startPlayback(url: URL) {
    if url.pathExtension == "flac" {
        guard IAPManager.shared.isProUser else {
            NotificationCenter.default.post(name: .showPaywall, object: "Hi-Res Playback")
            return
        }
        Features.Pro.HiResDecoder.decode(url: url)
    } else {
        // Free playback logic
    }
}
```

### Principle 3: UI-Level Paywall Integration

Any UI element that triggers Pro functionality should be disabled or hidden for non-Pro users.

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
                    // Navigate to PaywallView
                }
            }
        }
    }
}
```

---

## ⚠️ App Store Review Considerations

| Phase | Recommendation |
|-------|----------------|
| **Initial submission** | Include only core functionality (Free). Keep Pro code present but not visually exposed until IAP is approved. |
| **After IAP approval** | Enable visible Paywall and Pro feature entry points. |
| **External payments** | ❌ Never include PayPal or Buy Me a Coffee links inside the app. Such links belong only in GitHub/README. |

---

## 🧱 Notes for Development

- All features (Free & Pro) are under MIT license but Pro features must call IAPManager checks.  
- App Store distribution uses IAP as the only unlock method (Guideline 3.1.1).  
- Platform-specific implementations live in `Adapters/` and are selected via `#if os(macOS)` or `#if os(iOS)`.  
- HarmoniaCore defines domain models and business logic shared across all platforms.

---

## ✅ Summary

- **Single public repo**: transparent Open-Core model.  
- **IAP gating**: protects revenue without hiding code.  
- **No duplication**: one binary supports both Free and Pro.  
- **Fully compliant**: satisfies Apple’s guidelines for IAP-only monetization.

