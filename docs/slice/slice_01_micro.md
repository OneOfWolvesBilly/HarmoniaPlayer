docs/micro-slices/SLICE_1_MICRO.md
Slice 1: Foundation (Free) — Micro-slices
Purpose

Define the minimum composition and state wiring for HarmoniaPlayer Free.
Keep behavior out of Slice 1. Only wiring and configuration belong here.

Non-goals (Slice 1)

No playlist operations

No metadata parsing/enrichment workflow

No playback state machine orchestration

No UI features beyond app bootstrapping

Constraints

Do not change folder layout.

Treat Shared/Services/CoreFactory.swift as the only integration entry with HarmoniaCore.

Keep unit tests deterministic (no audio device dependency).

Slice1-A: IAP Abstraction (Mock-only)
Goal

Provide a minimal abstraction for Free/Pro gating without StoreKit integration.

Scope

Define IAPManager protocol

Provide MockIAPManager for unit tests and local bootstrapping

Files

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/IAPManager.swift

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/MockIAPManager.swift

Tests

App/HarmoniaPlayer/Tests/IAPManagerTests.swift (optional but recommended)

Done Criteria

MockIAPManager(isProUnlocked: true/false) behaves deterministically.

No dependency on HarmoniaCore.

No StoreKit code.

Suggested Commit Message

feat(player): add IAPManager abstraction for Free/Pro gating

Slice1-B: Feature Flags / Product Policy Mapping
Goal

Make Free/Pro decisions explicit and testable as data, not scattered if statements.

Scope

Define CoreFeatureFlags (or PlayerFeatureFlags)

Map from IAPManager → flags

Files

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/CoreFeatureFlags.swift

Alternative location: Shared/Services/ is acceptable, but keep it pure-data.

Tests

App/HarmoniaPlayer/Tests/CoreFeatureFlagsTests.swift

Done Criteria

Flags can be derived from IAP state (Free vs Pro) with unit tests.

No dependency on HarmoniaCore.

Flags are immutable value types.

Suggested Commit Message

feat(player): introduce CoreFeatureFlags derived from IAP state

Slice1-C: CoreFactory as Composition Root (Injectable Provider)
Goal

Create a single, testable integration entry point to HarmoniaCore.

Scope

Define a provider abstraction to avoid creating real audio pipelines in unit tests.

Implement CoreFactory to:

hold CoreFeatureFlags

produce service instances via provider

expose “effective product mode” (Free/Pro) for wiring

Design Notes

To keep tests deterministic, CoreFactory must not force real audio device creation in tests.
Use one of these patterns:

Preferred: Provider protocol + real provider in production, fake provider in tests.

Files

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreServiceProviding.swift

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/CoreFactory.swift

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Services/HarmoniaCoreProvider.swift (production implementation; may be very small)

Tests

App/HarmoniaPlayer/Tests/CoreFactoryTests.swift

Use FakeCoreProvider to assert:

CoreFactory passes correct flags/config

CoreFactory calls provider methods

Done Criteria

CoreFactory can be unit-tested without touching audio devices.

HarmoniaCore types are referenced only inside:

CoreFactory

HarmoniaCoreProvider

(and tests that explicitly validate wiring)

No UI references.

Suggested Commit Message

feat(player): add CoreFactory with injectable HarmoniaCore provider

Slice1-D: AppState Wiring (No Behavior)
Goal

Provide a single observable state container that wires factory + services.

Scope

Implement AppState as ObservableObject

Initialize:

iap

flags

coreFactory

core service handles (playback/tag reader) as references, not “run workflows”

Expose minimal published state:

isProUnlocked (or derived from flags)

Files

App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift

Tests

App/HarmoniaPlayer/Tests/AppStateInitTests.swift

Assert:

init does not crash

derived state matches IAP input

dependencies are wired (factory + services present)

Done Criteria

AppState initialization is deterministic and unit-tested.

AppState contains no playback/playlist/metadata workflow logic.

No SwiftUI Views depend on HarmoniaCore directly; only via AppState wiring.

Suggested Commit Message

feat(player): add AppState wiring for Slice1 foundation

Slice 1 Completion Checklist (All micro-slices)

Unit tests green.

No playlist / playback behavior implemented.

No metadata workflow implemented.

HarmoniaCore integration is localized to CoreFactory + Provider.

App can boot with AppState injected (UI can be minimal).

Optional: Minimal App Bootstrap (Not a micro-slice, but practical)

If needed to validate wiring in runtime:

HarmoniaPlayerApp.swift creates AppState() and injects it into the environment.

No additional features.

Suggested commit:

chore(player): wire AppState into app entry point

Micro-slice Commit Ordering (Recommended)

Slice1-A (IAP)

Slice1-B (Flags)

Slice1-C (CoreFactory + Provider)

Slice1-D (AppState)

(Optional) App bootstrap wiring