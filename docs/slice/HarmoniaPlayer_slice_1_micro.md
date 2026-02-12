# HarmoniaPlayer Slice 1 Micro-slices (File Bundle)

This canvas contains **file-ready** contents for Slice 1 micro-slices, aligned to a consistent `docs/` layout. Copy each section into the target path.

---

## 1) Docs layout and naming

### Target paths
- `docs/development/DEVELOPMENT_PLAN.md`
- `docs/micro-slices/slice-1/SLICE_1_A.md`
- `docs/micro-slices/slice-1/SLICE_1_B.md`
- `docs/micro-slices/slice-1/SLICE_1_C.md`
- `docs/micro-slices/slice-1/SLICE_1_D.md`
- `docs/micro-slices/slice-1/TDD_MATRIX_SLICE_1.md`

### Naming rules (keep consistent)
- Use `DEVELOPMENT_PLAN.md` for the roadmap / milestone-level slices.
- Use `docs/micro-slices/slice-N/SLICE_N_X.md` for implementation units.
- Use a dedicated `TDD_MATRIX_*.md` per slice to keep tests explicit and reviewable.

### Commit guideline (docs-only)
- One micro-slice doc = one commit **only if** you want reviewable history.
- Otherwise: commit the whole slice-1 doc bundle in a single docs commit.

---

# 2) File: `docs/development/DEVELOPMENT_PLAN.md`

## HarmoniaPlayer Development Plan

### Purpose
HarmoniaPlayer is the reference implementation and validation app for HarmoniaCore.

### Principles
- **Never bypass HarmoniaCore** for playback semantics.
- **Single integration entry**: composition must go through a factory (CoreFactory).
- **Deterministic tests**: unit tests must not require audio devices.

### Milestone slices

#### Slice 1 — Foundation (Free)
Focus: wiring, configuration, and state container.

Deliverables:
- IAP abstraction (mock-only)
- Feature flags derived from IAP state
- CoreFactory as composition root with injectable provider
- AppState wiring (no behavior)
- Unit tests green

Non-goals:
- playlist operations
- metadata enrichment flow
- playback orchestration

#### Slice 2 — Playlist Management
(placeholder)

#### Slice 3 — Metadata
(placeholder)

#### Slice 4 — Playback
(placeholder)

#### Slice 5 — Integration
(placeholder)

---

# 3) File: `docs/micro-slices/slice-1/SLICE_1_A.md`

## Slice1-A: IAP Abstraction (Mock-only)

### Goal
Provide a minimal abstraction for Free/Pro gating without StoreKit integration.

### Scope
- Define `IAPManager` protocol
- Provide `MockIAPManager` for unit tests and local bootstrapping

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/IAPManager.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/MockIAPManager.swift`

### Public API shape
- `protocol IAPManager { var isProUnlocked: Bool { get } }`
- `final class MockIAPManager: IAPManager { ... }`

### Tests
- `App/HarmoniaPlayer/Tests/IAPManagerTests.swift` (recommended)

### Done criteria
- `MockIAPManager(isProUnlocked: true/false)` deterministic.
- No dependency on HarmoniaCore.
- No StoreKit code.

### Suggested commit message
- `feat(docs): add Slice1-A micro-slice spec (IAP abstraction)`

---

# 4) File: `docs/micro-slices/slice-1/SLICE_1_B.md`

## Slice1-B: Feature Flags / Product Policy Mapping

### Goal
Make Free/Pro decisions explicit and testable as data, not scattered `if` statements.

### Scope
- Define `CoreFeatureFlags` (or `PlayerFeatureFlags`)
- Map from `IAPManager` → flags

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/CoreFeatureFlags.swift`

### Suggested data model
- Immutable value type
- Example fields (adjust to your product policy):
  - `supportsFLAC: Bool`
  - `supportsExport: Bool`
  - `maxPlaylistSize: Int?` (nil = unlimited)

### Tests
- `App/HarmoniaPlayer/Tests/CoreFeatureFlagsTests.swift`
  - Free → expected flags
  - Pro → expected flags

### Done criteria
- Flags can be derived from IAP state with unit tests.
- No dependency on HarmoniaCore.
- Flags are immutable.

### Suggested commit message
- `feat(docs): add Slice1-B micro-slice spec (feature flags)`

---

# 5) File: `docs/micro-slices/slice-1/SLICE_1_C.md`

## Slice1-C: CoreFactory as Composition Root (Injectable Provider)

### Goal
Create a single, testable integration entry point to HarmoniaCore.

### Scope
- Define a provider abstraction to avoid creating real audio pipelines in unit tests.
- Implement `CoreFactory` to:
  - hold `CoreFeatureFlags`
  - create service instances via provider
  - expose effective product mode (Free/Pro)

### Design rules
- `CoreFactory` is the **only** place that is allowed to integrate HarmoniaCore in the player layer.
- Unit tests must not require audio devices.

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreServiceProviding.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreFactory.swift`
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaCoreProvider.swift` (production provider)

### Provider contract (recommended)
- Define a protocol with factory methods for the minimal services you need in Slice 1:
  - Playback service creation
  - Tag reader creation

### Tests
- `App/HarmoniaPlayer/Tests/CoreFactoryTests.swift`
  - Use `FakeCoreProvider` (in test target) to validate:
    - flags passed/selected correctly
    - provider methods invoked as expected

### Done criteria
- CoreFactory is unit-testable with fake provider.
- HarmoniaCore references are localized to `CoreFactory` and `HarmoniaCoreProvider`.
- No UI references.

### Suggested commit message
- `feat(docs): add Slice1-C micro-slice spec (CoreFactory + provider)`

---

# 6) File: `docs/micro-slices/slice-1/SLICE_1_D.md`

## Slice1-D: AppState Wiring (No Behavior)

### Goal
Provide a single observable state container that wires factory + services.

### Scope
- Implement `AppState` as `ObservableObject`
- Initialize:
  - `IAPManager`
  - `CoreFeatureFlags`
  - `CoreFactory`
  - core service handles (as references only)
- Expose minimal published state:
  - `isProUnlocked` (or derived from flags)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift`

### Tests
- `App/HarmoniaPlayer/Tests/AppStateInitTests.swift`
  - init does not crash
  - derived state matches IAP input
  - dependencies are wired correctly

### Done criteria
- AppState initialization deterministic and unit-tested.
- AppState contains **no** playlist/metadata/playback orchestration.
- Views do not import HarmoniaCore.

### Suggested commit message
- `feat(docs): add Slice1-D micro-slice spec (AppState wiring)`

---

# 7) File: `docs/micro-slices/slice-1/TDD_MATRIX_SLICE_1.md`

## Slice 1 TDD Matrix

### Test principles
- Unit tests must be deterministic.
- No audio device dependency.
- Prefer fake providers over mocking framework magic.

---

## Slice1-A — IAP Abstraction

### Unit tests
| Test | Given | When | Then |
|---|---|---|---|
| `testMockIAPManager_DefaultIsFree` | new MockIAPManager() | read `isProUnlocked` | false |
| `testMockIAPManager_ProUnlocked` | MockIAPManager(true) | read `isProUnlocked` | true |

### Notes
- No HarmoniaCore import.

---

## Slice1-B — Feature Flags

### Unit tests
| Test | Given | When | Then |
|---|---|---|---|
| `testFeatureFlags_Free` | IAP = free | derive flags | matches Free policy |
| `testFeatureFlags_Pro` | IAP = pro | derive flags | matches Pro policy |

### Notes
- Keep flags as pure data.

---

## Slice1-C — CoreFactory

### Unit tests
| Test | Given | When | Then |
|---|---|---|---|
| `testCoreFactory_UsesFreeFlags` | flags=Free + fake provider | make services | provider called with Free config |
| `testCoreFactory_UsesProFlags` | flags=Pro + fake provider | make services | provider called with Pro config |
| `testCoreFactory_DoesNotTouchAudioDevices` | fake provider only | run tests | no device access required |

### Recommended fakes
- `FakeCoreProvider` should record calls (call count + last args).

---

## Slice1-D — AppState

### Unit tests
| Test | Given | When | Then |
|---|---|---|---|
| `testAppState_InitFree` | free IAP + fake provider | init AppState | isPro=false, services wired |
| `testAppState_InitPro` | pro IAP + fake provider | init AppState | isPro=true, services wired |
| `testAppState_NoBehaviorInInit` | fake provider | init AppState | no playback invoked |

### Notes
- If you expose services as properties, tests should verify they are non-nil and consistent.

---

## Slice 1 Completion Gate
- All tests above green.
- No playlist/metadata/playback orchestration code merged.
- HarmoniaCore references remain localized to CoreFactory + provider.

---

## Suggested docs commit message (bundle)
- `docs(player): add Slice 1 micro-slices and TDD matrix`

