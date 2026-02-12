# HarmoniaPlayer Development Plan

> **Last Updated:** 2026-02-11
> 
> This document defines the development strategy for HarmoniaPlayer,
> including slice breakdown, testing approach, and verification criteria.

---

## 1. Development Philosophy

### 1.1 Core Principles

**HarmoniaPlayer is:**
1. **Reference Implementation** - Demonstrates how to use HarmoniaCore APIs correctly
2. **Validation Tool** - Ensures HarmoniaCore works as specified
3. **Real Integration** - Always uses real HarmoniaCore, not mocks

**Therefore:**
- ✅ Use real HarmoniaCore-Swift in all tests
- ✅ Use real audio files for validation
- ✅ Test-Driven Development (TDD)
- ❌ Do NOT mock HarmoniaCore services
- ⚠️ Only mock external systems (IAPManager via StoreKit)

### 1.2 Testing Strategy

**Test Pyramid for HarmoniaPlayer:**
```
        /\
       /E2E\      Manual verification
      /------\
     /集成測試\    Complete flows with real HarmoniaCore
    /----------\
   / Unit Test  \  Component tests with real HarmoniaCore
  /--------------\
```

**Key Points:**
- All tests use real HarmoniaCore-Swift
- Test audio files required for validation
- Both automated tests AND manual verification

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
- play(trackID:) - load and play specific track
- Playback state transitions
- Current time / duration updates
- Uses real PlaybackService from HarmoniaCore

**Deliverables:**
1. Updated `AppState.swift` (playback methods)
2. `PlaybackControlTests.swift`
3. `SLICE_4_GUIDE.md`

**Test Files Required:**
- `test_playback.mp3` (10 seconds, valid audio)
- `test_short.mp3` (1 second)
- `test_unsupported.xyz` (unsupported format)

**Tests to Write:**
```swift
func testPlayPauseStop()
func testPlaySpecificTrack()
func testSeek()
func testPlaybackStateTransitions()
func testDurationRetrieval()
func testCurrentTimeUpdates()
func testPlayUnsupportedFormat()
func testPlayMissingFile()
```

**Verification Criteria:**
- ✅ All unit tests pass
- ✅ Playback state transitions correctly
- ✅ Can play, pause, stop, seek
- ✅ Duration and current time accurate
- ✅ Proper error handling

**Manual Verification:**
- **CRITICAL:** Actually hear audio output
- Play/pause/stop buttons work
- Seek bar functions correctly
- State indicator updates

---

### Slice 5: 集成測試 (Integration Tests)

**Scope:**
- Complete flow: load → enrich metadata → play
- Error handling: corrupt files, unsupported formats
- Pro feature gating: FLAC/DSD format restrictions
- Multi-track switching
- Edge cases and error scenarios

**Deliverables:**
1. `IntegrationTests.swift`
2. Complete test audio suite
3. `SLICE_5_GUIDE.md`
4. Final verification checklist

**Test Files Required:**
- `test_complete_flow.mp3` (full metadata, good audio)
- `test_corrupt.mp3` (intentionally corrupted)
- `test_flac.flac` (Pro format)
- `test_track1.mp3`, `test_track2.mp3` (for switching)

**Tests to Write:**
```swift
func testCompletePlaybackFlow()
func testMetadataEnrichmentAndPlay()
func testErrorHandlingCorruptFile()
func testErrorHandlingUnsupportedFormat()
func testProFormatGating()
func testTrackSwitching()
func testPlaylistPlaythrough()
func testMultipleLoadCycles()
```

**Verification Criteria:**
- ✅ All integration tests pass
- ✅ Complete user workflows function correctly
- ✅ Error handling robust
- ✅ Pro gating works (Free can't play FLAC)
- ✅ No memory leaks
- ✅ No crashes under normal and error conditions

**Manual Verification:**
- Complete user scenario testing
- Load multiple files
- Play through entire playlist
- Test all error conditions
- Verify Pro restrictions

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

| File | Purpose | Metadata | Duration | Format |
|------|---------|----------|----------|--------|
| test1.mp3 | Basic load | None | N/A | MP3 |
| test2.mp3 | Basic load | None | N/A | MP3 |
| test3.mp3 | Basic load | None | N/A | MP3 |
| test_with_tags.mp3 | Metadata read | Full | 5s | MP3 |
| test_with_tags.m4a | AAC metadata | Full | 5s | AAC |
| test_no_tags.wav | No metadata | None | 5s | WAV |
| test_partial_tags.mp3 | Partial metadata | Title only | 5s | MP3 |
| test_playback.mp3 | Playback | None | 10s | MP3 |
| test_short.mp3 | Quick test | None | 1s | MP3 |
| test_corrupt.mp3 | Error handling | N/A | N/A | Corrupt |
| test_flac.flac | Pro gating | None | 5s | FLAC |
| test_track1.mp3 | Switching | None | 5s | MP3 |
| test_track2.mp3 | Switching | None | 5s | MP3 |
| test_complete_flow.mp3 | Integration | Full | 10s | MP3 |

**Metadata Template (where applicable):**
```
Title: Test Track [N]
Artist: Test Artist
Album: Test Album
Duration: [actual duration]
```

### 3.3 Test File Location

```
Tests/
├── Resources/
│   ├── Audio/
│   │   ├── test1.mp3
│   │   ├── test2.mp3
│   │   ├── test_with_tags.mp3
│   │   └── ...
│   └── Info.plist  (for Bundle.module access)
└── HarmoniaPlayerTests/
    ├── Slice1/
    ├── Slice2/
    └── ...
```

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
│       │   │   │   ├── Track.swift
│       │   │   │   ├── Playlist.swift
│       │   │   │   ├── PlaybackState.swift
│       │   │   │   ├── PlaybackError.swift
│       │   │   │   └── ViewPreferences.swift
│       │   │   ├── Services/
│       │   │   │   ├── CoreFactory.swift
│       │   │   │   ├── IAPManager.swift
│       │   │   │   └── MockIAPManager.swift
│       │   │   └── AppState.swift
│       │   └── macOS/
│       │       └── Free/
│       │           └── HarmoniaPlayerApp.swift
│       └── Tests/
│           ├── Resources/
│           │   └── Audio/
│           └── HarmoniaPlayerTests/
│               ├── Slice1/
│               ├── Slice2/
│               ├── Slice3/
│               ├── Slice4/
│               └── Slice5/
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
  └── feat/slice-5-integration
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
feat(slice-1): implement CoreFactory and AppState initialization
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
| **Total** | **15-22 hours** | - |

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

## 10. Success Criteria

**HarmoniaPlayer v0.1 is complete when:**

- ✅ All 5 slices implemented and tested
- ✅ Can load audio files and display metadata
- ✅ Can play, pause, stop, seek audio
- ✅ Playlist management works correctly
- ✅ Error handling is robust
- ✅ Pro feature gating works
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

### Test Audio Generation

```bash
# Generate silent test file (requires ffmpeg)
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -acodec libmp3lame test_silent.mp3

# Add metadata
ffmpeg -i input.mp3 -metadata title="Test Track" -metadata artist="Test Artist" output.mp3
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-11  
**Author:** Claude (with user guidance)  
**Status:** Active Development Plan
