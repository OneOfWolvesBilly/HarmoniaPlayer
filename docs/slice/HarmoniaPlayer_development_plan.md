# HarmoniaPlayer Development Plan

> **Last Updated:** 2026-03-25
>
> This document defines the development strategy for HarmoniaPlayer,
> including slice breakdown, testing approach, and verification criteria.
>
> **Scope note:** Sections 2–10 cover Slices 1–6 (v0.1 foundation, now complete).
> Slices 7–9 are defined in their respective spec files and summarised in
> Section 11 of this document.

---

## 1. Development Philosophy

### 1.1 Core Principles

**HarmoniaPlayer is:**
1. **Reference Implementation** - Demonstrates how to use HarmoniaCore APIs correctly
2. **Validation Tool** - Ensures HarmoniaCore works as specified
3. **Real Integration** - Validates real HarmoniaCore behaviour in Slice 5 integration tests

**Therefore:**
- ✅ Test-Driven Development (TDD) with micro-slice red-green cycles
- ✅ Slices 1–4: fake service implementations for deterministic unit tests
- ✅ Slice 5-B: real HarmoniaCore-Swift services and real audio files
- ✅ `MockIAPManager` used across all slices (IAPManager is not a HarmoniaCore service)
- ❌ Do NOT call real audio I/O in unit tests (Slices 1–4)
- ❌ Do NOT use `FakePlaybackService` or `FakeTagReaderService` in integration tests (Slice 5-B)

### 1.2 Testing Strategy

**Test Pyramid for HarmoniaPlayer:**
```
               /\
              /  \
             /    \
            /      \
           /XCUITest\     Slice 6: end-to-end UI flows (XCUITest target)
          /----------\
         /Integration \   Slice 5-B: real HarmoniaCore + real audio files
        /--------------\
       /   Unit Tests   \ Slices 1–4: FakePlaybackService + FakeTagReaderService
      /------------------\
```

**Key Points:**
- Slices 1–4: all HarmoniaCore service collaborators are fakes — deterministic, no audio I/O
- Slice 5-B: `HarmoniaCoreProvider` (real adapters) + bundle audio resources
- Slice 6: XCUITest target — verifies UI flows via `accessibilityIdentifier`
- `MockIAPManager` used in all slices (IAPManager is external to HarmoniaCore)
- Both automated tests AND manual verification at each slice boundary

### 1.3 Development Workflow (TDD)

For each slice:

1. **Write Tests First** (Red)
   - Define expected behavior
   - Tests fail initially

2. **Implement Code** (Green)
   - Make tests pass
   - Minimal implementation

3. **Verify Manually** (Validate)
   - Run Xcode project
   - Verify actual behavior
   - Check audio output if applicable

4. **Refactor** (Clean)
   - Improve code quality
   - Tests still pass

---

## 2. Slice Breakdown

### Slice 1: 基礎操作 (Foundation)

**Scope:**
- CoreFactory construction
- AppState initialization
- IAPManager integration (Mock IAPManager only)
- Basic state management

**Deliverables:**
1. `CoreFactory.swift`
2. `AppState.swift` (basic structure)
3. `MockIAPManager.swift` (for testing)
4. `CoreFactoryTests.swift`
5. `AppStateInitTests.swift`
6. `SLICE_1_GUIDE.md` (setup and verification instructions)

**Test Files Required:**
- None (no audio needed yet)

**Tests to Write:**
```swift
// CoreFactoryTests.swift
func testCreatePlaybackService()
func testCreateTagReader()
func testFreeConfiguration()
func testProConfiguration()

// AppStateInitTests.swift
func testInitialization()
func testInitialState()
func testIAPIntegration()
```

**Verification Criteria:**
- ✅ All unit tests pass
- ✅ CoreFactory successfully creates services
- ✅ AppState initializes with correct initial state
- ✅ No crashes or errors

**Manual Verification:**
- Create Xcode project
- Run tests (⌘U)
- All tests green

---

### Slice 2: Playlist 管理操作 (Playlist Management)

**Scope:**
- Pure data operations (no metadata reading)
- load(urls:) - add URLs to playlist without reading tags
- removeTrack(trackID:)
- moveTrack(fromOffsets:toOffset:)
- clearPlaylist()

**Implementation Note:**
```swift
// Slice 2 implementation (NO metadata reading)
func load(urls: [URL]) {
    for url in urls {
        let track = Track(
            id: UUID(),
            url: url,
            title: url.lastPathComponent,  // Simple fallback
            artist: "",
            album: "",
            duration: nil
        )
        playlist.tracks.append(track)
    }
}
```

**Deliverables:**
1. Updated `AppState.swift` (playlist methods)
2. `PlaylistManagementTests.swift`
3. `SLICE_2_GUIDE.md`

**Test Files Required:**
- `test1.mp3`, `test2.mp3`, `test3.mp3` (for URL validation)

**Tests to Write:**
```swift
func testLoadURLs()
func testLoadMultipleURLs()
func testRemoveTrack()
func testMoveTrack()
func testClearPlaylist()
func testRemoveCurrentTrack()
```

**Verification Criteria:**
- ✅ All unit tests pass
- ✅ Playlist operations work correctly
- ✅ Track order maintained properly
- ✅ Edge cases handled (remove current track, empty playlist)

**Manual Verification:**
- Add breakpoints in playlist methods
- Verify playlist state in debugger
- Check track count and order

---

### Slice 3: 檢查 Metadata 資訊 (Metadata Reading)

**Scope:**
- enrichTrack(url:) using TagReaderPort
- Read title, artist, album, duration, artworkURL
- Test various formats (MP3, AAC, WAV, ALAC)
- Handle missing metadata gracefully

**Implementation Note:**
```swift
// Slice 3 adds metadata reading
func enrichTrack(url: URL) throws -> Track {
    let tags = try tagReader.readTags(from: url)
    
    return Track(
        id: UUID(),
        url: url,
        title: tags["title"] as? String ?? url.lastPathComponent,
        artist: tags["artist"] as? String ?? "",
        album: tags["album"] as? String ?? "",
        duration: tags["duration"] as? TimeInterval,
        artworkURL: tags["artworkURL"] as? URL
    )
}
```

**Deliverables:**
1. Updated `AppState.swift` (enrichTrack method)
2. `MetadataReadingTests.swift`
3. Test audio files with proper metadata
4. `SLICE_3_GUIDE.md`

**Test Files Required:**
- `test_with_tags.mp3` (full metadata: title, artist, album)
- `test_with_tags.m4a` (AAC with metadata)
- `test_no_tags.wav` (no metadata)
- `test_partial_tags.mp3` (some metadata missing)

**Tests to Write:**
```swift
func testReadMP3Metadata()
func testReadAACMetadata()
func testReadWAVNoMetadata()
func testPartialMetadata()
func testMissingFile()
func testCorruptFile()
```

**Verification Criteria:**
- ✅ All unit tests pass
- ✅ Correctly reads metadata from all formats
- ✅ Handles missing metadata gracefully
- ✅ Proper error handling for corrupt/missing files

**Manual Verification:**
- Load files with metadata
- Verify metadata appears correctly in Track objects
- Check fallback behavior (filename as title)

---

### Slice 4: Playback 控制 (Playback Control)

**Scope:**
- play(), pause(), stop(), seek(to:)
- play(trackID:) — async load-and-play for specific track
- Playback state transitions
- Current time / duration updates
- All tests use `FakePlaybackService` for deterministic control

**Deliverables:**
1. Updated `AppState.swift` (playback methods)
2. Upgraded `FakePlaybackService` with call recording and error stubs
3. `FakePlaybackServiceTests.swift`, `AppStatePlaybackStateTests.swift`
4. `AppStatePlaybackControlTests.swift`, `AppStatePlaybackTrackTests.swift`

**Test Files Required:**
- None — all Slice 4 tests use `FakePlaybackService` stubs

**Tests to Write:**
```swift
// FakePlaybackServiceTests.swift
func testFake_Load_RecordsURL()
func testFake_Play_StubbedError_Throws()
func testFake_Seek_RecordsSeconds()

// AppStatePlaybackStateTests.swift
func testInitialPlaybackState_IsIdle()
func testInitialCurrentTime_IsZero()

// AppStatePlaybackControlTests.swift
func testPlay_SetsPlayingState()
func testPlay_OnError_SetsLastError()
func testPause_SetsPausedState()
func testStop_SetsStoppedState()
func testStop_ResetsCurrentTimeToZero()
func testSeek_Success_UpdatesCurrentTime()
func testSeek_Error_DoesNotChangePlaybackState()

// AppStatePlaybackTrackTests.swift
func testPlayTrack_SetsCurrentTrack()
func testPlayTrack_CallsLoadThenPlay()
func testPlayTrack_LoadError_DoesNotCallPlay()
func testPlayTrack_UpdatesDuration()
func testPlayTrack_InvalidID_NoServiceCalls()
```

**Verification Criteria:**
- ✅ All unit tests pass (no real audio required)
- ✅ Playback state transitions correctly (idle → loading → playing → paused → stopped)
- ✅ Duration updated from service stub after load
- ✅ Error mapping via `mapToPlaybackError` works correctly
- ✅ `currentTime` reset by `stop()`

**Manual Verification:**
- Confirm `playbackState` transitions in debugger using stub values
- Confirm `lastError` populated on stubbed failure paths

---

### Slice 5: HarmoniaCore Integration + Integration Tests

**Scope:**
- **5-A** — HarmoniaCore adapters + format gating (unit tests with `FakePlaybackService`):
  - `HarmoniaPlaybackServiceAdapter`: bridges sync `HarmoniaCore.PlaybackService`
    to async `HarmoniaPlayer.PlaybackService`
  - `HarmoniaTagReaderAdapter`: bridges `TagReaderPort` (sync, `TagBundle`)
    to async `TagReaderService` (returns `Track`)
  - `HarmoniaCoreProvider`: replace placeholder classes with real adapter instances
  - `AppState.play(trackID:)`: add format gating for FLAC/DSF/DFF on Free tier
- **5-B** — Integration tests using real `HarmoniaCoreProvider` + real audio files:
  - Complete flow: `load(urls:)` → metadata enrichment → `play(trackID:)`
  - Error handling: corrupt files, unsupported formats
  - Pro feature gating: FLAC rejected on Free tier
  - Multi-track switching, stop state reset

**Deliverables:**
1. `HarmoniaPlaybackServiceAdapter.swift`
2. `HarmoniaTagReaderAdapter.swift`
3. Updated `HarmoniaCoreProvider.swift` (real services, no placeholders)
4. Updated `AppState.swift` (format gating in `play(trackID:)`)
5. `AppStateFormatGatingTests.swift` (unit tests — `FakePlaybackService`)
6. `IntegrationTests.swift` (real `HarmoniaCoreProvider`, real audio resources)

**Test Files Required (5-A):**
- None — format gating tests use `FakePlaybackService`

**Test Files Required (5-B):**
- `test_tagged.mp3` — valid MP3, ID3 tags with title ≠ filename
- `test_playback.mp3` — valid MP3, ≥ 3 seconds
- `test_track2.mp3` — second valid MP3 for track-switching
- `test_corrupt.mp3` — zero-byte or invalid header
- `test_format.flac` — any content, `.flac` extension only

**Tests to Write:**
```swift
// AppStateFormatGatingTests.swift (5-A, FakePlaybackService)
func testFormatGating_FLAC_FreeTier_SetsUnsupportedFormat()
func testFormatGating_FLAC_FreeTier_NoServiceCalls()
func testFormatGating_DSF_FreeTier_SetsUnsupportedFormat()
func testFormatGating_FLAC_ProTier_Proceeds()
func testFormatGating_MP3_FreeTier_Proceeds()

// IntegrationTests.swift (5-B, HarmoniaCoreProvider)
func testIntegration_CompletePlaybackFlow()
func testIntegration_MetadataEnrichment()
func testIntegration_CorruptFile_SetsError()
func testIntegration_UnsupportedFormat_Free()
func testIntegration_TrackSwitching()
func testIntegration_StopResetsState()
```

**Verification Criteria:**
- ✅ All 5-A format gating tests pass (no real audio)
- ✅ All 5-B integration tests pass (real HarmoniaCore)
- ✅ Pro gating works (Free tier rejects FLAC/DSF/DFF before service call)
- ✅ Metadata enrichment reads real ID3 tags from bundle resource
- ✅ No crashes under normal and error conditions

**Manual Verification:**
- Load valid MP3 and confirm `playbackState == .playing`
- Load tagged MP3 and confirm title comes from ID3, not filename
- Load `.flac` on Free tier and confirm `lastError == .unsupportedFormat`

---

### Slice 6: UI MVP (SwiftUI Views)

**Scope:**
- Implement the minimum SwiftUI views that let a user actually play music
- Wire `AppState` into the app entry point via `@EnvironmentObject`
- Add `FreeTierIAPManager` (production Free-tier `IAPManager` implementation)
- All views are thin: display state, forward events to `AppState` only
- No `import HarmoniaCore` in any View file

**Deliverables:**
1. `Shared/Views/TrackRowView.swift` — single track row (title, duration, playing indicator)
2. `Shared/Views/PlaylistView.swift` — track list + add-files button + delete key support
3. `Shared/Views/PlayerView.swift` — now-playing info + progress slider + transport controls
4. `Shared/Views/ContentView.swift` — `HSplitView` combining playlist and player panels
5. `Shared/Services/FreeTierIAPManager.swift` — production `IAPManager` (always Free)
6. Updated `macOS/Free/HarmoniaPlayerApp.swift` — inject `AppState`, set `ContentView` as root
7. `HarmoniaPlayerUITests/UITests.swift` — XCUITest target (new target in project)

**New Files (Shared/Views/):**
```
HarmoniaPlayer/Shared/Views/
├── TrackRowView.swift
├── PlaylistView.swift
├── PlayerView.swift
└── ContentView.swift
```

**Accessibility Identifiers (required for XCUITest):**
```
"playlist-list"
"add-files-button"
"play-pause-button"
"stop-button"
"progress-slider"
"now-playing-title"
"playback-status-label"
```

**Module Boundary Rules:**
- Views import `SwiftUI` only
- Views access state via `@EnvironmentObject var appState: AppState`
- Views never import `HarmoniaCore`, `PlaybackService`, or any service directly
- `Task { await appState.someMethod() }` is the only way Views trigger actions

**Tests to Write (XCUITest):**
```swift
func testPlaylistShowsAddedTracks()
func testTapTrackStartsPlayback()
func testPlayPauseButton_TogglesState()
func testStopButton_ResetsState()
func testProgressSlider_Exists()
func testRemoveTrack_RemovesFromList()
```

**Verification Criteria:**
- ✅ App launches showing a real UI (not blank/Text placeholder)
- ✅ User can open audio files via the Add button or drag-and-drop
- ✅ User can tap a track row to start playback
- ✅ Play/Pause/Stop buttons reflect and control `playbackState`
- ✅ Progress slider displays `currentTime` / `duration`
- ✅ All XCUITest cases pass
- ✅ No `import HarmoniaCore` in any View file
- ✅ All Slice 1–5 unit tests still green

**Manual Verification:**
- Launch app, drag an MP3 into the playlist → track row appears
- Double-click track → playback starts, button changes to Pause
- Click Pause → button changes to Play, state shows "Paused"
- Click Stop → progress resets to 0:00, state shows "Stopped"

---

## 3. Test Audio File Specifications

### 3.1 File Naming Convention

```
test_<purpose>.<ext>

Examples:
- test_with_tags.mp3
- test_no_tags.wav
- test_corrupt.mp3
- test_playback.mp3
```

### 3.2 Required Test Files

Slices 1–4 require no audio files. All unit tests use `FakePlaybackService`
and `FakeTagReaderService`.

Slice 5-B requires the following audio resources added to the test target bundle:

| File | Slice | Purpose | Metadata | Duration |
|------|-------|---------|----------|----------|
| test_tagged.mp3 | 5-B | Metadata enrichment | Full (title ≠ filename) | ≥ 3s |
| test_playback.mp3 | 5-B | Complete flow, stop test | Optional | ≥ 3s |
| test_track2.mp3 | 5-B | Track switching | Optional | ≥ 3s |
| test_corrupt.mp3 | 5-B | Error handling | N/A | N/A (zero-byte) |
| test_format.flac | 5-B | Format gating verification | N/A | N/A (.flac ext) |

### 3.3 Test File Location

```
HarmoniaPlayerTests/
└── Resources/
    └── Audio/                  # Slice 5-B only
        ├── test_tagged.mp3
        ├── test_playback.mp3
        ├── test_track2.mp3
        ├── test_corrupt.mp3
        └── test_format.flac
```

All audio resources must be added to the test target under
Build Phases → Copy Bundle Resources.

---

## 4. Verification Checklist

### Per-Slice Verification

After completing each slice:

- [ ] All unit tests pass (⌘U in Xcode)
- [ ] No compiler warnings
- [ ] Code follows Swift style guidelines
- [ ] Manual verification completed
- [ ] Documentation updated (SLICE_N_GUIDE.md)
- [ ] Ready for next slice

### Final Verification (After Slice 5)

- [ ] All tests pass (full test suite)
- [ ] Manual testing of complete user workflows
- [ ] Audio output verified (can actually hear playback)
- [ ] Error handling tested (corrupt files, missing files)
- [ ] Pro gating verified (FLAC restriction works)
- [ ] Memory profiling (no leaks)
- [ ] Performance acceptable (no UI freezing)
- [ ] Code review completed
- [ ] Documentation complete

---

## 5. Development Environment Setup

### 5.1 Project Structure

```
HarmoniaPlayer/
├── App/
│   └── HarmoniaPlayer/
│       ├── HarmoniaPlayer/
│       │   ├── Shared/
│       │   │   ├── Models/
│       │   │   │   ├── AppState.swift
│       │   │   │   ├── CoreFeatureFlags.swift
│       │   │   │   ├── PlaybackError.swift
│       │   │   │   ├── PlaybackState.swift
│       │   │   │   ├── Playlist.swift
│       │   │   │   ├── Track.swift
│       │   │   │   └── ViewPreferences.swift
│       │   │   └── Services/
│       │   │       ├── CoreFactory.swift
│       │   │       ├── CoreServiceProviding.swift
│       │   │       ├── HarmoniaCoreProvider.swift
│       │   │       ├── IAPManager.swift
│       │   │       ├── PlaybackService.swift
│       │   │       └── TagReaderService.swift
│       │   └── macOS/
│       │       └── Free/
│       │           └── HarmoniaPlayerApp.swift
│       └── HarmoniaPlayerTests/
│           ├── FakeInfrastructure/
│           │   ├── FakeCoreProvider.swift
│           │   ├── FakeTagReaderService.swift
│           │   └── MockIAPManager.swift
│           ├── SharedTests/
│           │   ├── AppStateErrorHandlingTests.swift
│           │   ├── AppStateMetadataTests.swift
│           │   ├── AppStatePlaybackControlTests.swift
│           │   ├── AppStatePlaybackStateTests.swift
│           │   ├── AppStatePlaybackTrackTests.swift
│           │   ├── AppStatePlayerlistTests.swift
│           │   ├── AppStateTests.swift
│           │   ├── AppStateTrackSelectionTests.swift
│           │   ├── CoreFactoryTests.swift
│           │   ├── CoreFeatureFlagsTests.swift
│           │   ├── FakePlaybackServiceTests.swift
│           │   ├── FakeTagReaderServiceTests.swift
│           │   ├── IAPManagerTests.swift
│           │   ├── PlaybackErrorTests.swift
│           │   ├── PlaybackStateTests.swift
│           │   ├── PlaylistTests.swift
│           │   ├── TrackTests.swift
│           │   └── ViewPreferencesTests.swift
│           └── HarmoniaPlayerTests.swift
└── docs/
    ├── DEVELOPMENT_PLAN.md  (this file)
    ├── SLICE_1_GUIDE.md
    ├── SLICE_2_GUIDE.md
    └── ...
```

### 5.2 Dependencies

**Package.swift:**
```swift
dependencies: [
    .package(
        url: "https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift.git",
        from: "0.1.0"
    )
]
```

### 5.3 Test Target Configuration

**In Xcode Project:**
- Target: HarmoniaPlayerTests
- Host Application: HarmoniaPlayer-macOS-Free
- Bundle Resources: Tests/Resources/
- Dependencies: HarmoniaCore (via SPM)

---

## 6. Code Quality Standards

### 6.1 Testing Standards

**Every test must:**
- Have a clear, descriptive name
- Test one behavior
- Be independent (no test order dependency)
- Clean up resources (if any)
- Use XCTAssert variants appropriately

**Example:**
```swift
func testPlaybackStateTransitionsFromIdleToPlaying() throws {
    // Arrange
    let factory = CoreFactory()
    let iap = MockIAPManager(isProUser: false)
    let appState = AppState(factory: factory, iap: iap)
    
    let testURL = Bundle.module.url(forResource: "test_playback", withExtension: "mp3")!
    appState.load(urls: [testURL])
    
    // Act
    try appState.play(trackID: appState.playlist.tracks[0].id)
    
    // Assert
    XCTAssertEqual(appState.playbackState, .playing)
}
```

### 6.2 Implementation Standards

**Code must:**
- Follow Swift API Design Guidelines
- Use clear, descriptive names
- Include documentation comments for public APIs
- Handle errors explicitly
- Use `@MainActor` for UI-related code

**Example:**
```swift
/// Loads audio files into the playlist.
/// 
/// Files are added without metadata enrichment in this implementation.
/// Use `enrichTrack(url:)` separately for metadata reading.
/// 
/// - Parameter urls: Array of file URLs to load
func load(urls: [URL]) {
    for url in urls {
        let track = Track(
            id: UUID(),
            url: url,
            title: url.lastPathComponent,
            artist: "",
            album: "",
            duration: nil
        )
        playlist.tracks.append(track)
    }
}
```

---

## 7. Git Workflow

### 7.1 Branch Strategy

```
main
  ├── feat/slice-1-foundation
  ├── feat/slice-2-playlist
  ├── feat/slice-3-metadata
  ├── feat/slice-4-playback
  ├── feat/slice-5-integration
  └── feat/slice-6-ui-mvp
```

### 7.2 Commit Message Format

Follow HarmoniaPlayer style:

```
<type>(<scope>): <subject>
- <change 1>
- <change 2>
- <change 3>
```

**Example:**
```
feat(slice 1): implement CoreFactory and AppState initialization
- Add CoreFactory with makePlaybackService and makeTagReader
- Add AppState with basic initialization
- Add MockIAPManager for testing
- Add CoreFactoryTests and AppStateInitTests
```

### 7.3 PR Requirements

Before merging each slice:
- [ ] All tests pass
- [ ] Manual verification completed
- [ ] Code reviewed
- [ ] Documentation updated
- [ ] No merge conflicts

---

## 8. Timeline Estimation

| Slice | Estimated Time | Complexity |
|-------|---------------|------------|
| Slice 1 | 2-3 hours | Low |
| Slice 2 | 2-3 hours | Low |
| Slice 3 | 3-4 hours | Medium |
| Slice 4 | 4-6 hours | High |
| Slice 5 | 4-6 hours | High |
| Slice 6 | 3-5 hours | Medium |
| **Total** | **18-27 hours** | - |

**Note:** These are estimates for implementation only, not including:
- Xcode project setup
- Test audio file preparation
- Documentation writing
- Code review and iteration

---

## 9. Risk Mitigation

### 9.1 Potential Issues

| Risk | Impact | Mitigation |
|------|--------|------------|
| HarmoniaCore API changes | High | Pin to specific version, update together |
| Test audio file issues | Medium | Prepare multiple backup files |
| Platform-specific bugs | Medium | Test on multiple macOS versions |
| Performance issues | Low | Profile early, optimize if needed |

### 9.2 Fallback Plans

**If HarmoniaCore has issues:**
1. Document the issue in HarmoniaCore repo
2. Implement workaround in HarmoniaPlayer (temporary)
3. Fix in HarmoniaCore
4. Remove workaround

**If tests are flaky:**
1. Investigate root cause
2. Add retry logic if necessary (audio I/O timing)
3. Use longer timeouts for CI environment

---

## 10. Success Criteria (Slices 1–6)

**Slices 1–6 are complete. All criteria below have been met:**

- ✅ All 6 slices implemented and tested
- ✅ Can load audio files and display metadata
- ✅ Can play, pause, stop, seek audio
- ✅ Playlist management works correctly
- ✅ SwiftUI UI is functional — user can operate the app without code
- ✅ Error handling is robust
- ✅ Pro feature gating works (format gating for FLAC/DSD)
- ✅ No crashes or memory leaks
- ✅ Documentation complete
- ✅ Code reviewed and approved
- ✅ Ready for user testing

---

## Appendix A: Quick Reference

### Running Tests

```bash
# All tests
swift test

# Specific test file
swift test --filter HarmoniaPlayerTests.CoreFactoryTests

# In Xcode
⌘U (Run all tests)
⌃⌥⌘U (Run tests in current file)
```

### Manual Verification

```bash
# Open project
open App/HarmoniaPlayer/HarmoniaPlayer.xcodeproj

# Build and run
⌘R

# Run with debugger
⌘Y (then ⌘R)
```

### Test Audio Generation (Slice 5-B)

```bash
# Generate silent test file (requires ffmpeg)
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -acodec libmp3lame test_playback.mp3

# Add metadata tags
ffmpeg -i test_playback.mp3 -metadata title="Test Track" \
  -metadata artist="Test Artist" -metadata album="Test Album" \
  test_tagged.mp3

# Generate corrupt file
echo -n "" > test_corrupt.mp3
```
---

## 11. Slices 7–9 Overview

Slices 7–9 were scoped after Slice 6 completion. Each slice has its own
spec file; this section provides a summary for orientation.

### 11.1 Scope Evolution

The original plan targeted Slice 6 as the v0.1 gate. After completing
Slice 6, the scope was extended:

- **Slices 7–8** — additional Free tier features required for a releasable v0.1
- **Slice 9** — Pro tier gated behind StoreKit 2 IAP (v0.2)

### 11.2 Slice 7: UX and Data Layer (Free)

**Spec:** `docs/slice/slice_07_micro.md`
**Developer spec:** `docs/slice/HarmoniaPlayer_slice_micro/HarmoniaPlayer_slice_7_micro.md`

| Sub-slice | Content | Status |
|---|---|---|
| 7-A | Volume control end-to-end (AudioOutputPort → PlayerView) | ✅ Complete |
| 7-B | Multiple playlist tabs (create, rename, delete) | ✅ Complete |
| 7-C | M3U8 playlist import / export (absolute + relative paths) | ✅ Complete |
| 7-D | Drag-to-reorder tracks in PlaylistView | Pending |
| 7-E | Persistence via UserDefaults (playlists, settings, volume) | Pending |
| 7-F | UI localisation — 24 languages including Arabic RTL | Pending |
| 7-G | Column customization + sort; Track model expansion (Groups A–E) | Pending |
| 7-H | File Info Panel (read-only tech info + editable source URL) | Pending |

**Testing approach:** Unit tests (FakePlaybackService) for all AppState behaviour.
Column customization persisted via `@AppStorage` in View layer (not AppState).

### 11.3 Slice 8: UX Polish and Advanced Playback (Free)

**Spec:** `docs/slice/slice_08_micro_draft.md`
**Status:** Draft — review before implementation begins

| Sub-slice | Content |
|---|---|
| 8-A | Menu bar disabled states + Play/Pause label fix + UndoManager (⌘Z / ⌘Y) |
| 8-C | Mini Player floating window (⌘M, always on top) |
| 8-D | ReplayGain volume normalisation (off / track / album mode) |

> 8-B (Music Library / folder scanning) — removed; conflicts with foobar2000
> design philosophy (no library management).
>
> 8-E (Play statistics + track rating) — deferred to backlog; fields already
> defined in Track model Group E (Slice 7-G).

**v0.1 gate:** Slice 8 complete.

### 11.4 Slice 9: Pro Tier — IAP and Tag Editor

**Spec:** `docs/slice/slice_09_micro_draft.md`
**Status:** Draft — review before implementation begins

| Sub-slice | Content |
|---|---|
| 9-A | StoreKit 2 IAP + Paywall UI |
| 9-B | Tag Editor — basic fields (Groups A+B + bpm + comment) |
| 9-C | Tag Editor — sort fields (sortTitle, sortArtist, etc.) |
| 9-D | Tag Editor — artwork (embedded album art) |
| 9-E | Tag Editor — lyrics (USLT embedded lyrics) |

**Pro feature gating** for FLAC/DSD is already implemented in
`AppState.play(trackID:)` (Slice 5-A). Slice 9-A only needs to provide a
real `isProUser == true` after purchase.

**v0.2 gate:** Slice 9 complete.

### 11.5 Version Targets

| Version | Gate | Description |
|---|---|---|
| v0.1 | Slice 8 complete | Free tier feature complete; first public release |
| v0.2 | Slice 9 complete | Pro tier; Tag Editor + FLAC/DSD via App Store IAP |