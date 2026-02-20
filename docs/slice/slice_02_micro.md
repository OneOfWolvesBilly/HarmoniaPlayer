# Slice 02 Micro-slices Specification

## Purpose

This document defines **Slice 2: Playlist Management** for HarmoniaPlayer.

Slice 2 focuses on **data models and state management** for playlists, without implementing actual playback orchestration.

---

## Slice 2 Overview

### Goals
- Define Track and Playlist data models
- Add playlist state to AppState
- Implement playlist operations (add/remove/reorder)
- Implement track selection
- Maintain testability and Clean Architecture

### Non-goals
- Actual audio playback (Slice 4)
- Metadata extraction from files (Slice 3)
- UI implementation (optional verification only)
- Playlist persistence (future)

### Dependencies
- Requires: Slice 1 (Foundation) complete
- Provides: Data structures and state for Slice 3 and 4

---

## Slice2-A: Track Model

### Goal
Define the Track data model as the fundamental unit of playable content.

### Scope
- Immutable identifier and URL
- Mutable metadata fields (title, artist, album)
- Optional duration
- Conform to Identifiable and Equatable

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Track.swift`

### Tests
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/TrackTests.swift`

### Public API shape

```swift
struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL
    
    // Basic metadata (UI-level only)
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    
    // Optional artwork (future)
    var artworkURL: URL?
}
```

### Initialization

```swift
// Primary initializer (all fields)
init(id: UUID = UUID(), 
     url: URL, 
     title: String, 
     artist: String = "", 
     album: String = "", 
     duration: TimeInterval? = nil)

// Convenience initializer (derive title from URL)
init(url: URL)
```

### Done criteria
- Track struct compiles and conforms to protocols
- Unit tests verify:
  - Identity (Identifiable)
  - Equality (Equatable)
  - Field access
  - Initialization variants
- No dependency on HarmoniaCore
- No dependency on UIKit/AppKit

### Suggested commit message
```
implement Track model with TDD

- Define Track as Identifiable, Equatable struct
- Include id, url, title, artist, album, duration
- Add convenience initializer from URL
```

---

## Slice2-B: Playlist Model

### Goal
Define the Playlist data model as a collection of tracks.

### Scope
- Immutable identifier
- Mutable name and track list
- Convenience computed properties
- Conform to Identifiable and Equatable

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/Playlist.swift`

### Tests
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/PlaylistTests.swift`

### Public API shape

```swift
struct Playlist: Identifiable, Equatable {
    let id: UUID
    var name: String
    var tracks: [Track]
    
    // Computed properties
    var isEmpty: Bool { tracks.isEmpty }
    var count: Int { tracks.count }
}
```

### Initialization

```swift
init(id: UUID = UUID(), 
     name: String = "Playlist", 
     tracks: [Track] = [])
```

### Done criteria
- Playlist struct compiles and conforms to protocols
- Unit tests verify:
  - Identity (Identifiable)
  - Equality (Equatable)
  - Field access and mutation
  - Computed properties
  - Empty playlist handling
- No dependency on HarmoniaCore
- No side effects (pure data)

### Suggested commit message
```
implement Playlist model with TDD

- Define Playlist as Identifiable, Equatable struct
- Include id, name, tracks
- Add isEmpty and count computed properties
```

---

## Slice2-C: Playlist Operations in AppState

### Goal
Add playlist state, playlist operations, and current-track state to AppState
without implementing actual audio playback.

### Scope
- Add `@Published` playlist state
- Implement CRUD operations for tracks
- Add `@Published` currentTrack state ← **pulled forward from Slice 2-D**
- Implement `play(trackID:)` for track selection ← **pulled forward from Slice 2-D**
- Maintain architectural boundaries
- No actual file I/O or audio operations

> **Note — why currentTrack is introduced here, not in Slice 2-D:**
> The Slice 2-C tests for `clearPlaylist()` and `removeTrack(_:)` require a
> pre-condition of "currentTrack is set". To set it without additional test
> infrastructure, `play(trackID:)` must exist in the same slice.
> Keeping both together avoids a temporary workaround in tests.
> Slice 2-D therefore becomes a **tests-only** slice (no AppState changes).

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)

### Tests
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStatePlaylistTests.swift` (new)

### Public API additions

```swift
@MainActor
final class AppState: ObservableObject {
    // ... existing Slice 1 state ...
    
    // MARK: - Playlist State (Slice 2-C)
    
    @Published private(set) var playlist: Playlist
    
    // MARK: - Current Track State (Slice 2-C)
    //
    // Pulled forward from Slice 2-D because clearPlaylist() and
    // removeTrack(_:) tests require the ability to pre-set currentTrack.
    @Published private(set) var currentTrack: Track?
    
    // MARK: - Playlist Operations (Slice 2-C)
    
    /// Load audio files into playlist
    /// - Note: Creates Track instances with URL-derived titles (Slice 3 will add metadata)
    func load(urls: [URL])
    
    /// Clear all tracks from playlist
    /// - Note: Also sets currentTrack to nil
    func clearPlaylist()
    
    /// Remove a specific track by ID
    /// - Note: Also sets currentTrack to nil if removed track was selected
    func removeTrack(_ trackID: Track.ID)
    
    /// Reorder tracks (for drag-and-drop support)
    func moveTrack(fromOffsets: IndexSet, toOffset: Int)

    // MARK: - Track Selection (Slice 2-C, tested further in Slice 2-D)

    /// Select a track by ID (does not start playback)
    /// - Note: Actual playback control added in Slice 4
    func play(trackID: Track.ID)
}
```

### Implementation notes

**Initialization**
- `playlist` initialised to `Playlist(name: "Session")` with empty tracks
- `currentTrack` initialised to `nil`

**load(urls:)**
- Create Track instances with URL-derived titles
- Append to existing playlist (additive)
- No format validation (Slice 4)
- No metadata extraction (Slice 3)

**clearPlaylist()**
- Reset playlist.tracks to empty array
- Set currentTrack to nil

**removeTrack(_:)**
- Check currentTrack **before** removing from array
- If removed track matches currentTrack, set currentTrack to nil
- Find and remove track by ID from playlist.tracks
- No effect if ID not found

**moveTrack(fromOffsets:toOffset:)**
- Use standard Swift `Array.move(fromOffsets:toOffset:)`
- Typical pattern for SwiftUI List reordering

**play(trackID:)**
- Find track in playlist by ID using `first { $0.id == trackID }`
- Set currentTrack to found track, or nil if not found
- Does NOT call playbackService.play() (Slice 4)
- Does NOT load audio (Slice 4)

### Done criteria
- AppState compiles with new playlist and currentTrack state
- Unit tests verify:
  - Initial playlist is empty (pre-condition test)
  - Initial currentTrack is nil (pre-condition test)
  - load() adds tracks with correct URL-derived titles
  - load() is additive (appends to existing tracks)
  - clearPlaylist() empties the list and sets currentTrack to nil
  - removeTrack() removes correct track; sets currentTrack to nil if it was selected
  - removeTrack() with invalid ID has no effect
  - removeTrack() with different ID leaves currentTrack unchanged
  - moveTrack() reorders correctly
- Operations do not trigger any HarmoniaCore calls
- No file I/O performed
- No dependency on UIKit/AppKit

### Suggested commit message
```
implement playlist operations and track selection in AppState with TDD

- Add playlist state (Slice 2-C)
- Implement load, clear, remove, move operations
- Add currentTrack state (pulled forward from Slice 2-D)
- Implement play(trackID:) for track selection (no audio, Slice 4)
- Use URL-derived titles (metadata extraction in Slice 3)
```

---

## Slice2-D: Track Selection (Tests Only)

### Goal
Verify `play(trackID:)` behaviour across edge cases with a dedicated test file.

> **Note:** `currentTrack` state and `play(trackID:)` were implemented in
> Slice 2-C. This slice adds **only** the test file — AppState.swift is
> **not modified** here.

### Scope
- Write dedicated test suite for `play(trackID:)` behaviour
- Verify all edge cases (valid ID, invalid ID, empty playlist, switch track)
- Verify `play(trackID:)` does not call `playbackService`
- No AppState implementation changes (already done in Slice 2-C)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateTrackSelectionTests.swift` (new)
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` — **no changes**

### Tests
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateTrackSelectionTests.swift` (new)

### Verified behaviour

```swift
// These are already implemented; this slice only adds tests:

@Published private(set) var currentTrack: Track?

func play(trackID: Track.ID)
// - Sets currentTrack to matching track, or nil if not found
// - Does NOT call playbackService.play() (Slice 4)
```

### Done criteria
- Dedicated test file compiles and all tests pass
- Tests verify:
  - Initial currentTrack is nil
  - play(trackID:) sets currentTrack correctly
  - play(trackID:) switches currentTrack when called again
  - play(trackID:) with invalid ID sets currentTrack to nil
  - play(trackID:) on empty playlist sets currentTrack to nil
  - No playback service calls made
- No dependency on playback orchestration
- State changes are deterministic

### Suggested commit message
```
add track selection tests with TDD (Slice 2-D)

- Test play(trackID:) edge cases in dedicated test file
- Verify no playback service calls
- AppState unchanged (implemented in Slice 2-C)
```

---

## Slice 2 TDD Matrix

### Test principles
- All tests must be deterministic
- No file I/O dependencies
- No audio device dependencies
- Pure state management tests
- **Swift 6 / Xcode 26:** AppState is `@MainActor`. Test classes that test
  AppState must also be annotated `@MainActor`. XCTest executes
  `@MainActor`-isolated test classes on the main actor automatically, so no
  `await MainActor.run {}` wrappers are needed in individual test methods.

---

### Slice2-A: Track Model

| Test | Given | When | Then |
|------|-------|------|------|
| `testTrack_HasUniqueID` | Two Track instances | Compare IDs | IDs are different |
| `testTrack_Equatable` | Two Tracks with same fields | Compare with == | Are equal |
| `testTrack_InitWithURL` | URL | Create Track | Title derived from filename |
| `testTrack_InitWithAllFields` | All parameters | Create Track | All fields match |

---

### Slice2-B: Playlist Model

| Test | Given | When | Then |
|------|-------|------|------|
| `testPlaylist_HasUniqueID` | Two Playlist instances | Compare IDs | IDs are different |
| `testPlaylist_Equatable` | Two Playlists with same fields | Compare with == | Are equal |
| `testPlaylist_IsEmpty` | Empty playlist | Check isEmpty | Returns true |
| `testPlaylist_IsNotEmpty` | Playlist with 1 track | Check isEmpty | Returns false |
| `testPlaylist_Count` | Playlist with 3 tracks | Check count | Returns 3 |

---

### Slice2-C: Playlist Operations

| Test | Given | When | Then |
|------|-------|------|------|
| `testInitial_PlaylistIsEmpty` | Fresh AppState | Read playlist | playlist.isEmpty == true |
| `testInitial_CurrentTrackIsNil` | Fresh AppState | Read currentTrack | currentTrack == nil |
| `testLoad_EmptyPlaylist_AddsTrack` | Empty playlist + [URL] | load(urls:) | Playlist has 1 track |
| `testLoad_ExistingPlaylist_AppendsTrack` | Playlist with 1 track + [URL] | load(urls:) | Playlist has 2 tracks |
| `testLoad_MultipleURLs_AddsAll` | Empty playlist + [URL1, URL2] | load(urls:) | Playlist has 2 tracks |
| `testLoad_DerivesTitleFromFilename` | URL `/tmp/my-song.mp3` | load(urls:) | track.title == "my-song" |
| `testClearPlaylist_WithTracks_EmptiesPlaylist` | Playlist with 3 tracks | clearPlaylist() | Playlist is empty |
| `testClearPlaylist_NilsCurrentTrack` | Playlist with currentTrack set | clearPlaylist() | currentTrack is nil |
| `testRemoveTrack_ExistingID_RemovesTrack` | Playlist with 3 tracks | removeTrack(id) | Playlist has 2 tracks |
| `testRemoveTrack_InvalidID_NoChange` | Playlist with 3 tracks | removeTrack(invalid) | Playlist still has 3 tracks |
| `testRemoveTrack_CurrentTrack_NilsCurrentTrack` | currentTrack set + remove same ID | removeTrack(currentTrack.id) | currentTrack is nil |
| `testRemoveTrack_OtherTrack_KeepsCurrentTrack` | currentTrack set + remove different ID | removeTrack(otherId) | currentTrack unchanged |
| `testMoveTrack_ValidIndices_Reorders` | Playlist [A,B,C] | moveTrack(0→3) | Playlist is [B,C,A] |

---

### Slice2-D: Track Selection

| Test | Given | When | Then |
|------|-------|------|------|
| `testPlay_ValidID_SetsCurrentTrack` | Playlist with 3 tracks | play(trackID) | currentTrack set correctly |
| `testPlay_SwitchTrack_UpdatesCurrentTrack` | currentTrack set to track A | play(trackB.id) | currentTrack switches to track B |
| `testPlay_InvalidID_ClearsCurrentTrack` | Playlist with 3 tracks | play(invalid) | currentTrack is nil |
| `testPlay_EmptyPlaylist_ClearsCurrentTrack` | Empty playlist | play(anyID) | currentTrack is nil |
| `testPlay_DoesNotCallPlaybackService` | Any playlist | play(trackID) | No service calls made |

---

## Slice 2 Completion Gate

### Required before Slice 3

- ✅ All Slice 2 tests green
- ✅ Track and Playlist models defined and tested
- ✅ AppState has playlist state and operations
- ✅ AppState has currentTrack state (implemented in Slice 2-C)
- ✅ Track selection implemented via play(trackID:) (no playback)
- ✅ No file I/O performed
- ✅ No audio device dependencies
- ✅ No HarmoniaCore playback calls
- ✅ Clean Architecture maintained

### Verification

Run all tests:
```bash
⌘U in Xcode
```

Expected output:
```
Slice 1 tests: All passing
Slice 2-A tests: All passing
Slice 2-B tests: All passing
Slice 2-C tests: All passing (13 tests)
Slice 2-D tests: All passing
```

---

## Suggested documentation commit (optional)

If you want to commit this spec document to your repository:

```
docs(player): add Slice 2 micro-slices specification

- Define Track and Playlist models
- Specify playlist operations in AppState
- Specify track selection
- Include TDD matrix
```

---

## Related slices

- **Slice 1 (Foundation)** - Required prerequisite
- **Slice 3 (Metadata)** - Will enrich Track with actual metadata
- **Slice 4 (Playback)** - Will connect track selection to actual playback
- **Slice 5 (Integration)** - Will add UI and end-to-end workflows