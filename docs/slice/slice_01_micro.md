# Slice 01 Micro-slices Specification

## Purpose

This document defines **Slice 1: Foundation (Free)** for HarmoniaPlayer.

Slice 1 focuses on the minimum composition and state wiring for HarmoniaPlayer Free,
without implementing any playback behavior, playlist operations, or metadata logic.

---

## Slice 1 Overview

### Goals
- Define IAP abstraction for Free/Pro gating
- Define feature flags derived from IAP state
- Create CoreFactory as the single testable integration entry point to HarmoniaCore
- Wire AppState with services and minimal published state
- Define base error types and UI preference types
- Verify TagReader wiring

### Non-goals
- Playlist operations
- Metadata parsing or enrichment workflow
- Playback state machine orchestration
- UI features beyond app bootstrapping

### Constraints
- Do not change folder layout.
- `Shared/Services/CoreFactory.swift` is the only integration entry point with HarmoniaCore.
- Unit tests must be deterministic (no audio device dependency).
- `MockIAPManager` lives in the **test target only** — never in the main target.
- All `Fake*` types live in the **test target only**.

### Dependencies
- Requires: None (first slice)
- Provides: Wiring and base types for Slice 2 and beyond

---

## Slice1-A: IAP Abstraction

### Scope
- Define `IAPManager` protocol
- Provide `MockIAPManager` for unit tests and local bootstrapping

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/IAPManager.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/macOS/Free/HarmoniaPlayerApp.swift` (updated to minimal version)

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/MockIAPManager.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/IAPManagerTests.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/HarmoniaPlayerTests.swift` (test target bootstrap)

### Public API shape

```swift
protocol IAPManager: AnyObject {
    var isProUnlocked: Bool { get }
}

final class MockIAPManager: IAPManager {
    let isProUnlocked: Bool
    init(isProUnlocked: Bool)
}
```

### Done criteria
- `MockIAPManager(isProUnlocked: true/false)` behaves deterministically
- No dependency on HarmoniaCore
- No StoreKit code
- `MockIAPManager` is in the test target, not the main target

### Suggested commit message
```
feat(slice-1a): implement IAP abstraction with TDD
```

---

## Slice1-B: CoreFeatureFlags

### Scope
- Define `CoreFeatureFlags` as an immutable value type
- Derive flags from `IAPManager` state

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/CoreFeatureFlags.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/CoreFeatureFlagsTests.swift`

### Public API shape

```swift
struct CoreFeatureFlags: Equatable {
    let isProEnabled: Bool

    static func make(from iap: IAPManager) -> CoreFeatureFlags
}
```

### Done criteria
- Flags can be derived from IAP state (Free vs Pro) with unit tests
- No dependency on HarmoniaCore
- Flags are immutable value types

### Suggested commit message
```
feat(slice-1b): implement CoreFeatureFlags with TDD
```

---

## Slice1-C: CoreFactory as Composition Root

### Scope
- Define `CoreServiceProviding` protocol to abstract HarmoniaCore construction
- Implement `CoreFactory` to hold `CoreFeatureFlags` and delegate to provider
- Implement `HarmoniaCoreProvider` as the production provider
- Implement `FakeCoreProvider` in the test target for deterministic tests

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreServiceProviding.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreFactory.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaCoreProvider.swift`

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/FakeCoreProvider.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/CoreFactoryTests.swift`

### Public API shape

```swift
protocol CoreServiceProviding: AnyObject {
    func makePlaybackService(isProUser: Bool) -> PlaybackService
    func makeTagReaderService() -> TagReaderService
}

struct CoreFactory {
    let flags: CoreFeatureFlags
    private let provider: CoreServiceProviding

    init(flags: CoreFeatureFlags, provider: CoreServiceProviding)

    func makePlaybackService() -> PlaybackService
    func makeTagReaderService() -> TagReaderService
}
```

> HarmoniaCore types (`PlaybackService`, `TagReaderService`) are referenced
> only inside `CoreFactory`, `HarmoniaCoreProvider`, and tests that explicitly
> validate wiring.

### FakeCoreProvider shape (test target)

```swift
final class FakeCoreProvider: CoreServiceProviding {
    private(set) var makePlaybackServiceCallCount = 0
    private(set) var lastIsProUser: Bool?
    private(set) var makeTagReaderServiceCallCount = 0

    var playbackServiceStub: PlaybackService
    var tagReaderServiceStub: TagReaderService

    init(playbackService: PlaybackService = FakePlaybackService(),
         tagReader: TagReaderService = FakeTagReaderService())
}
```

### Done criteria
- `CoreFactory` can be unit-tested without touching audio devices
- HarmoniaCore types are referenced only inside `CoreFactory` and `HarmoniaCoreProvider`
- `FakeCoreProvider` records all calls for assertion
- No UI references

### Suggested commit message
```
feat(slice-1c): implement CoreFactory with injectable provider
```

---

## Slice1-D: AppState Wiring

### Scope
- Implement `AppState` as `@MainActor ObservableObject`
- Wire `IAPManager`, `CoreFeatureFlags`, `CoreFactory`, and core service handles
- Expose minimal published state (`isProUnlocked`)
- No playback, playlist, or metadata behavior

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateTests.swift`

### Public API shape

```swift
@MainActor
final class AppState: ObservableObject {

    // MARK: - Services (internal let for test access)
    let playbackService: PlaybackService
    let tagReaderService: TagReaderService

    // MARK: - Published State
    @Published private(set) var isProUnlocked: Bool

    // MARK: - Initialization
    init(iapManager: IAPManager, provider: CoreServiceProviding)
}
```

> `nonisolated deinit {}` must be added if the Xcode 26 beta malloc crash
> (`swift::TaskLocal::StopLookupScope`) occurs with existential types in
> `@Published` on `@MainActor` classes.

### Done criteria
- `AppState` initialization is deterministic and unit-tested
- `AppState` contains no playback/playlist/metadata workflow logic
- `playbackService` and `tagReaderService` are `internal let` (accessible from tests)
- No SwiftUI views depend on HarmoniaCore directly; only via `AppState` wiring

### Suggested commit message
```
feat(slice-1d): implement AppState wiring with TDD
```

---

## Slice1-E: Error Types and UI Preferences

### Scope
- Define `PlaybackError` enum
- Add `error(PlaybackError)` case to `PlaybackState`
- Define `ViewPreferences` and `LayoutPreset`
- Add `viewPreferences` and `lastError` published state to `AppState`
- No behavior — type definitions and state wiring only

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/PlaybackError.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/ViewPreferences.swift`

Modified:
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/PlaybackState.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`

Test target only:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/PlaybackErrorTests.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/ViewPreferencesTests.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/PlaybackStateTests.swift`

### Public API shape

```swift
enum PlaybackError: Error, Equatable {
    case unsupportedFormat
    case failedToOpenFile
    case failedToDecode
    case outputError
    case coreError(String)
}

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(PlaybackError)   // NEW in Slice 1-E
}

struct ViewPreferences: Equatable {
    var isWaveformVisible: Bool
    var isPlaylistVisible: Bool
    var layoutPreset: LayoutPreset

    static let defaultPreferences = ViewPreferences(
        isWaveformVisible: true,
        isPlaylistVisible: true,
        layoutPreset: .standard
    )
}

enum LayoutPreset: String, CaseIterable, Equatable {
    case compact
    case standard
    case waveformFocused
}
```

```swift
// AppState additions
@Published var viewPreferences: ViewPreferences = .defaultPreferences
@Published private(set) var lastError: PlaybackError?
```

### Done criteria
- `PlaybackError` defined and `Equatable` conformance works for all cases including `coreError(String)`
- `PlaybackState.error(PlaybackError)` case present and comparable
- `ViewPreferences` and `LayoutPreset` defined with correct defaults
- `AppState.viewPreferences` initialized to `.defaultPreferences`
- `AppState.lastError` initialized to `nil`; nothing sets it in this slice
- No playback or metadata logic introduced
- No dependency on HarmoniaCore

### Suggested commit message
```
feat(slice-1e): implement PlaybackError, ViewPreferences, and error state with TDD
```

---

## Slice1-F: TagReader Wiring Verification

### Scope
- Verify `makeTagReaderService()` is called exactly once during `AppState.init`
- Verify `tagReaderService` is the exact instance returned by the provider
- Verify no `TagReaderService` methods are called during `AppState.init`
- Test-only additions — no new production logic

### Files
Modified (visibility change only if `tagReaderService` is currently `private`):
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`

Modified test files:
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/CoreFactoryTests.swift`
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateTests.swift`

> `tagReaderService` must be `internal let` for test access.
> If already internal, no production file change is needed.

### FakeTagReaderService shape (test target)

```swift
final class FakeTagReaderService: TagReaderService {
    private(set) var readMetadataCallCount = 0
}
```

### Done criteria
- `tagReaderService` is accessible from the test target
- `makeTagReaderService()` called exactly once during `AppState.init`
- `tagReaderService` instance is the one returned by the provider (`===`)
- No `TagReaderService` methods called during `AppState.init`
- No new production logic introduced

### Suggested commit message
```
feat(slice-1f): add TagReader wiring verification tests
```

---

## Slice 1 TDD Matrix

### Test principles
- All tests must be deterministic
- No audio device dependencies
- `MockIAPManager` and all `Fake*` types in test target only
- **Swift 6 / Xcode 26:** Test classes that test `AppState` must be `@MainActor`.
  XCTest executes `@MainActor`-isolated test classes on the main actor automatically,
  so no `await MainActor.run {}` wrappers are needed in individual test methods.

---

### Slice1-A: IAPManager

| Test | Given | When | Then |
|------|-------|------|------|
| `testMock_IsProUnlocked_False` | `MockIAPManager(isProUnlocked: false)` | read `isProUnlocked` | `false` |
| `testMock_IsProUnlocked_True` | `MockIAPManager(isProUnlocked: true)` | read `isProUnlocked` | `true` |
| `testMock_ConformsToIAPManager` | `let _: IAPManager = MockIAPManager(isProUnlocked: false)` | compile | ✅ |

---

### Slice1-B: CoreFeatureFlags

| Test | Given | When | Then |
|------|-------|------|------|
| `testFlags_FreeUser_IsProEnabledFalse` | `MockIAPManager(isProUnlocked: false)` | `CoreFeatureFlags.make(from:)` | `isProEnabled == false` |
| `testFlags_ProUser_IsProEnabledTrue` | `MockIAPManager(isProUnlocked: true)` | `CoreFeatureFlags.make(from:)` | `isProEnabled == true` |
| `testFlags_Equatable_SameValues` | Two flags with same `isProEnabled` | `==` | `true` |
| `testFlags_Equatable_DifferentValues` | `isProEnabled: true` vs `false` | `==` | `false` |

---

### Slice1-C: CoreFactory

| Test | Given | When | Then |
|------|-------|------|------|
| `testFactory_FreeFlags_PassesFalseToProvider` | `CoreFeatureFlags(isProEnabled: false)` + `FakeCoreProvider` | `factory.makePlaybackService()` | `lastIsProUser == false` |
| `testFactory_ProFlags_PassesTrueToProvider` | `CoreFeatureFlags(isProEnabled: true)` + `FakeCoreProvider` | `factory.makePlaybackService()` | `lastIsProUser == true` |
| `testFactory_CallsMakePlaybackService_Once` | `FakeCoreProvider` | `factory.makePlaybackService()` called once | `makePlaybackServiceCallCount == 1` |
| `testFactory_CallsMakeTagReaderService_Once` | `FakeCoreProvider` | `factory.makeTagReaderService()` called once | `makeTagReaderServiceCallCount == 1` |
| `testFactory_PlaybackService_IsNotNil` | `FakeCoreProvider` | `factory.makePlaybackService()` | non-nil |
| `testFactory_TagReaderService_IsNotNil` | `FakeCoreProvider` | `factory.makeTagReaderService()` | non-nil |

---

### Slice1-D: AppState Wiring

| Test | Given | When | Then |
|------|-------|------|------|
| `testAppState_Init_DoesNotCrash` | `MockIAPManager(isProUnlocked: false)` + `FakeCoreProvider` | `AppState(iapManager:provider:)` | no crash |
| `testAppState_FreeUser_IsProUnlockedFalse` | `MockIAPManager(isProUnlocked: false)` | read `isProUnlocked` | `false` |
| `testAppState_ProUser_IsProUnlockedTrue` | `MockIAPManager(isProUnlocked: true)` | read `isProUnlocked` | `true` |
| `testAppState_Init_CallsMakePlaybackService` | `FakeCoreProvider` | `AppState.init` | `makePlaybackServiceCallCount == 1` |
| `testAppState_PlaybackService_IsNotNil` | `FakeCoreProvider` | read `sut.playbackService` | non-nil |
| `testAppState_PlaybackService_IsFromProvider` | `FakeCoreProvider` with known `FakePlaybackService` | read `sut.playbackService` | same instance (`===`) |
| `testAppState_FreeUser_ProviderReceivesFalse` | `MockIAPManager(isProUnlocked: false)` + `FakeCoreProvider` | `AppState.init` | `fakeProvider.lastIsProUser == false` |

---

### Slice1-E: Error Types and UI Preferences

| Test | Given | When | Then |
|------|-------|------|------|
| `testPlaybackError_Equatable_SameCase` | `.unsupportedFormat` vs `.unsupportedFormat` | `==` | `true` |
| `testPlaybackError_Equatable_DifferentCase` | `.failedToOpenFile` vs `.failedToDecode` | `==` | `false` |
| `testPlaybackError_CoreError_SameString` | `.coreError("X")` vs `.coreError("X")` | `==` | `true` |
| `testPlaybackError_CoreError_DifferentString` | `.coreError("X")` vs `.coreError("Y")` | `==` | `false` |
| `testPlaybackError_AllCasesExist` | Exhaustive switch | compile | all 5 cases present |
| `testPlaybackError_ConformsToError` | `let _: Error = PlaybackError.outputError` | compile | ✅ |
| `testPlaybackState_ErrorCase_Equatable` | `.error(.unsupportedFormat)` vs `.error(.unsupportedFormat)` | `==` | `true` |
| `testPlaybackState_ErrorCase_NotEqualWhenPayloadDiffers` | `.error(.failedToOpenFile)` vs `.error(.failedToDecode)` | `==` | `false` |
| `testPlaybackState_ErrorIsNotPlaying` | `.error(.outputError)` | `!= .playing` | `true` |
| `testViewPreferences_DefaultValues` | `.defaultPreferences` | read fields | `isWaveformVisible=true`, `isPlaylistVisible=true`, `layoutPreset=.standard` |
| `testViewPreferences_Equatable_SameFields` | Two instances with same values | `==` | `true` |
| `testViewPreferences_Equatable_DifferentFields` | Different `isWaveformVisible` | `==` | `false` |
| `testViewPreferences_Mutable_LayoutPreset` | Default preferences | set `layoutPreset = .compact` | `.compact` |
| `testLayoutPreset_AllCasesCount` | `LayoutPreset.allCases` | `.count` | `3` |
| `testLayoutPreset_RawValues` | Each case | `.rawValue` | `"compact"`, `"standard"`, `"waveformFocused"` |
| `testAppState_InitialViewPreferences_MatchesDefault` | Fresh `AppState` | read `viewPreferences` | equals `.defaultPreferences` |
| `testAppState_InitialLastError_IsNil` | Fresh `AppState` | read `lastError` | `nil` |
| `testAppState_ViewPreferences_IsMutable` | Fresh `AppState` | set `viewPreferences.layoutPreset = .compact` | `.compact` |

---

### Slice1-F: TagReader Wiring Verification

| Test | Given | When | Then |
|------|-------|------|------|
| `testCoreFactory_CallsMakeTagReaderService_Once` | `FakeCoreProvider` | `factory.makeTagReaderService()` called once | `makeTagReaderServiceCallCount == 1` |
| `testCoreFactory_TagReaderService_IsNotNil` | `FakeCoreProvider` | `factory.makeTagReaderService()` | non-nil |
| `testAppState_Init_CallsMakeTagReaderService` | `FakeCoreProvider` | `AppState.init` | `makeTagReaderServiceCallCount == 1` |
| `testAppState_TagReaderService_IsNotNil` | `FakeCoreProvider` | read `sut.tagReaderService` | non-nil |
| `testAppState_TagReaderService_IsFromProvider` | `FakeCoreProvider` with known `FakeTagReaderService` | read `sut.tagReaderService` | same instance (`===`) |
| `testAppState_TagReaderService_NoMethodsCalled` | `FakeCoreProvider` with `FakeTagReaderService` | `AppState.init` completes | `readMetadataCallCount == 0` |

---

## Slice 1 Completion Gate

### Required before Slice 2

- ✅ All Slice 1-A through 1-F tests green
- ✅ `IAPManager` protocol and `MockIAPManager` (test target) defined
- ✅ `CoreFeatureFlags` defined and tested
- ✅ `CoreFactory` with injectable provider defined
- ✅ `AppState` wiring complete:
  - `isProUnlocked: Bool`
  - `viewPreferences: ViewPreferences`
  - `lastError: PlaybackError?`
  - `playbackService: PlaybackService` (internal let)
  - `tagReaderService: TagReaderService` (internal let)
- ✅ `PlaybackError` enum defined
- ✅ `PlaybackState.error(PlaybackError)` case present
- ✅ `ViewPreferences` and `LayoutPreset` defined
- ✅ `makeTagReaderService()` called exactly once during `AppState.init`
- ✅ `tagReaderService` is the instance returned by the provider
- ✅ No playlist / playback / metadata behavior implemented
- ✅ `MockIAPManager` and `FakeCoreProvider` in test target only

---

## Related slices

- **Slice 2 (Playlist Management)** — Requires Slice 1 complete; adds Track/Playlist models and AppState operations
- **Slice 3 (Metadata)** — Calls `tagReaderService.readMetadata(for:)`; needs `tagReaderService` wired
- **Slice 4 (Playback)** — Sets `lastError`; needs `PlaybackState.error(_:)` and `PlaybackError` defined