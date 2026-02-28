# Slice 03 Micro-slices Specification

## Purpose

This document defines **Slice 3: Metadata Extraction** for HarmoniaPlayer.

Slice 3 integrates `TagReaderService` into `AppState.load(urls:)` to enrich
`Track` instances with real metadata (title, artist, album, duration),
replacing the URL-derived placeholders created in Slice 2.

---

## Slice 3 Overview

### Goals
- Upgrade `FakeTagReaderService` to support configurable stubs for testing
- Make `AppState.load(urls:)` async and call `TagReaderService.readMetadata(for:)`
- Gracefully degrade on metadata failure: fall back to `Track(url:)` rather than dropping the file
- Maintain Clean Architecture and TDD discipline

### Non-goals
- Actual audio playback (Slice 4)
- Format validation / Pro gating (Slice 4)
- Album artwork loading (future)
- Tag writing / metadata editing (future)
- UI implementation (Slice 5)

### Dependencies
- Requires: Slice 1 complete — `TagReaderService` already injected in `AppState`
- Requires: Slice 2 complete — `load(urls:)` exists
- Provides: Enriched `Track` instances for Slice 4 (Playback)

---

## Slice3-A: Configurable FakeTagReaderService

### Goal
Upgrade `FakeTagReaderService` to support per-URL metadata stubs and error
stubs, enabling deterministic test setups for Slice 3-B and 3-C.

### Scope
- Add `stubbedMetadata: [URL: Track]` for configuring return values
- Add `stubbedErrors: [URL: Error]` for simulating failures
- Add call recording (`readMetadataCallCount`, `requestedURLs`)
- Default behaviour (no stub): return `Track(url:)` as before
- No changes to `TagReaderService` protocol or `AppState`

### Files
- `App/HarmoniaPlayer/HarmoniaPlayerTests/FakeInfrastructure/FakeTagReaderService.swift` (modify)

### Tests
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/FakeTagReaderServiceTests.swift` (new)

### Public API shape

```swift
final class FakeTagReaderService: TagReaderService {

    // Call recording
    private(set) var readMetadataCallCount = 0
    private(set) var requestedURLs: [URL] = []

    // Stub configuration
    var stubbedMetadata: [URL: Track] = [:]
    var stubbedErrors: [URL: Error] = [:]

    func readMetadata(for url: URL) async throws -> Track {
        readMetadataCallCount += 1
        requestedURLs.append(url)

        if let error = stubbedErrors[url] { throw error }
        return stubbedMetadata[url] ?? Track(url: url)
    }
}
```

### Done criteria
- `FakeTagReaderService` compiles in test target
- Stub errors take precedence over stub metadata
- Call recording is accurate
- `FakeCoreProvider.makeTagReaderService()` returns the upgraded fake

### Suggested commit message
```
feat(slice-3a): upgrade FakeTagReaderService with stub support with TDD

- Add stubbedMetadata and stubbedErrors per URL for deterministic test setup
- Add requestedURLs call recording to complement existing readMetadataCallCount
- Add FakeTagReaderServiceTests
```

---

## Slice3-B: Async Metadata Loading in AppState

### Goal
Update `AppState.load(urls:)` to call `TagReaderService.readMetadata(for:)`
for each URL and append the returned (metadata-enriched) `Track` to the playlist.

### Scope
- Change `load(urls:)` signature from synchronous to `async`
- Call `tagReaderService.readMetadata(for:)` per URL
- Append returned `Track` to `playlist.tracks`
- Error handling is a placeholder only (Slice 3-C completes it)
- Tests written before implementation (TDD)

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateMetadataTests.swift` (new)

### Public API change

```swift
// Before (Slice 2):
func load(urls: [URL])

// After (Slice 3-B):
func load(urls: [URL]) async
```

> **Note — Swift 6 / Xcode 26:** `AppState` is `@MainActor`. Test classes
> must also be `@MainActor`. Test methods calling `async` functions must be
> `async`. XCTest supports `async` test functions natively — no
> `await MainActor.run {}` wrappers needed.

### Done criteria
- `AppState.load(urls:)` is async
- `TagReaderService.readMetadata(for:)` is called for each URL
- Returned `Track` (with real metadata) is appended to playlist
- All Slice 3-B tests green
- All previous Slice 2 tests still green (update call sites to `await` where needed)
- No module boundary violations

### Suggested commit message
```
feat: integrate TagReaderService into AppState.load (Slice 3-B)

- Make load(urls:) async
- Call tagReaderService.readMetadata(for:) per URL
- Append metadata-enriched Track to playlist
- Add AppStateMetadataTests for happy-path coverage
```

---

## Slice3-C: Graceful Degradation on Metadata Failure

### Goal
When `TagReaderService.readMetadata(for:)` throws, fall back to a URL-derived
`Track(url:)` rather than dropping the file or propagating the error.

### Scope
- Replace error placeholder from Slice 3-B with explicit `do/catch` fallback
- On error: append `Track(url:)` (URL-derived title)
- No error is surfaced to the user in this slice (UI error handling in Slice 4+)
- No file is ever silently dropped

### Files
- `App/HarmoniaPlayer/HarmoniaPlayer/Shared/Models/AppState.swift` (modify)
- `App/HarmoniaPlayer/HarmoniaPlayerTests/SharedTests/AppStateMetadataTests.swift` (extend)

### Public API shape (final load implementation)

```swift
func load(urls: [URL]) async {
    for url in urls {
        do {
            let track = try await tagReaderService.readMetadata(for: url)
            playlist.tracks.append(track)
        } catch {
            // Graceful fallback: URL-derived track; error surfaced in Slice 4
            playlist.tracks.append(Track(url: url))
        }
    }
}
```

### Done criteria
- `load(urls:)` never drops a URL, even on metadata error
- Fallback produces a `Track(url:)` with URL-derived title
- All Slice 3-C tests green
- All previous tests still green

### Suggested commit message
```
feat: graceful fallback for metadata errors in AppState.load (Slice 3-C)

- Replace error placeholder with explicit do/catch
- Fall back to Track(url:) when TagReaderService throws
- File is never dropped regardless of metadata error
- Extend AppStateMetadataTests with error fallback cases
```

---

## Slice 3 TDD Matrix

### Test principles
- All tests deterministic — no real file I/O
- No audio device dependencies
- Use `FakeTagReaderService` with stubs for all metadata behaviour
- **Swift 6 / Xcode 26:** Test class must be `@MainActor`. Test methods calling
  `async` functions must be `async`.

---

### Slice3-A: FakeTagReaderService

| Test | Given | When | Then |
|------|-------|------|------|
| `testFake_DefaultBehaviour` | No stub | `readMetadata(url)` | Returns `Track(url:)` |
| `testFake_StubbedMetadata` | `stubbedMetadata[url] = track` | `readMetadata(url)` | Returns stubbed track |
| `testFake_StubbedError` | `stubbedErrors[url] = err` | `readMetadata(url)` | Throws error |
| `testFake_RecordsCallCount` | Any | 3 calls | `readMetadataCallCount == 3` |
| `testFake_RecordsURLs` | Any | url1, url2 | `requestedURLs == [url1, url2]` |

---

### Slice3-B: Happy Path

| Test | Given | When | Then |
|------|-------|------|------|
| `testLoad_CallsTagReaderForEachURL` | 3 URLs | `await load(urls:)` | `readMetadataCallCount == 3` |
| `testLoad_UsesMetadataTitle` | Stub with title "Real Title" | `await load(urls:)` | `track.title == "Real Title"` |
| `testLoad_UsesMetadataArtist` | Stub with artist "Artist X" | `await load(urls:)` | `track.artist == "Artist X"` |
| `testLoad_UsesMetadataAlbum` | Stub with album "Album Y" | `await load(urls:)` | `track.album == "Album Y"` |
| `testLoad_UsesMetadataDuration` | Stub with duration 180.0 | `await load(urls:)` | `track.duration == 180.0` |
| `testLoad_MultipleURLs_AllEnriched` | 2 stubbed URLs | `await load(urls:)` | Both tracks enriched |
| `testLoad_IsAdditive_WithMetadata` | Playlist with 1 track + 1 URL | `await load(urls:)` | Playlist has 2 tracks |

---

### Slice3-C: Error Fallback

| Test | Given | When | Then |
|------|-------|------|------|
| `testLoad_MetadataError_FallsBackToURLTitle` | `stubbedErrors[url]` set | `await load(urls:)` | Track has URL-derived title |
| `testLoad_MetadataError_DoesNotDropFile` | Error stub for 1 URL | `await load(urls:)` | `playlist.tracks.count == 1` |
| `testLoad_PartialError_SuccessTracksEnriched` | URL1 succeeds, URL2 throws | `await load(urls:)` | Track1 has metadata |
| `testLoad_PartialError_BothTracksAdded` | URL1 succeeds, URL2 throws | `await load(urls:)` | `playlist.tracks.count == 2` |
| `testLoad_AllErrors_FallsBackAll` | All URLs throw | `await load(urls:)` | All tracks have URL-derived titles |

---

## Slice 3 Completion Gate

### Required before Slice 4

- ✅ `FakeTagReaderService` supports `stubbedMetadata` and `stubbedErrors`
- ✅ `AppState.load(urls:)` is `async`
- ✅ `TagReaderService.readMetadata(for:)` called for each URL
- ✅ Real metadata replaces URL-derived placeholders on success
- ✅ Graceful fallback to `Track(url:)` on metadata failure
- ✅ No file is ever silently dropped
- ✅ All Slice 3 tests green
- ✅ All Slice 1 and Slice 2 tests still green
- ✅ Clean Architecture maintained (no module boundary violations)

### Verification

```bash
⌘U in Xcode
```

Expected output:
```
Slice 1 tests:   All passing
Slice 2 tests:   All passing
Slice 3-A tests: All passing
Slice 3-B tests: All passing
Slice 3-C tests: All passing
```

---

## Related Slices

- **Slice 1 (Foundation)** — Prerequisite; `TagReaderService` injected in `AppState`
- **Slice 2 (Playlist Management)** — Prerequisite; `load(urls:)` exists
- **Slice 4 (Playback)** — Uses enriched `Track` instances; adds format validation and playback
- **Slice 5 (Integration)** — Adds UI; calls `await appState.load(urls:)` in drag-and-drop handlers