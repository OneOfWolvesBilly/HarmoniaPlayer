//
//  FakeCoreProvider.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-15.
//

import Foundation
@testable import HarmoniaPlayer

/// Fake service provider for testing
///
/// Records method calls for verification in tests.
/// Returns injectable stub service implementations.
///
/// **Usage — call count only:**
/// ```swift
/// let fake = FakeCoreProvider()
/// let factory = CoreFactory(featureFlags: flags, provider: fake)
/// _ = factory.makePlaybackService()
///
/// XCTAssertEqual(fake.makePlaybackServiceCallCount, 1)
/// XCTAssertTrue(fake.lastIsProUser!)
/// ```
///
/// **Usage — identity check (TagReader):**
/// ```swift
/// let knownFake = FakeTagReaderService()
/// let provider = FakeCoreProvider(tagReader: knownFake)
/// let sut = AppState(iapManager: MockIAPManager(), provider: provider)
/// XCTAssertTrue(sut.tagReaderService === knownFake)
/// ```
///
/// **Usage — playback service stub access (Slice 4):**
/// ```swift
/// let fakeService = FakePlaybackService()
/// let provider = FakeCoreProvider(playbackService: fakeService)
/// let sut = AppState(iapManager: MockIAPManager(), provider: provider)
/// await sut.play()
/// XCTAssertEqual(fakeService.playCallCount, 1)
/// ```
final class FakeCoreProvider: CoreServiceProviding {

    // MARK: - Call Recording

    /// Number of times makePlaybackService was called
    private(set) var makePlaybackServiceCallCount = 0

    /// Last isProUser parameter passed to makePlaybackService
    private(set) var lastIsProUser: Bool?

    /// Number of times makeTagReaderService was called
    private(set) var makeTagReaderServiceCallCount = 0

    /// Number of times makeLyricsService was called
    private(set) var makeLyricsServiceCallCount = 0

    // MARK: - Stubs

    /// The PlaybackService stub returned by makePlaybackService().
    ///
    /// Typed as `FakePlaybackService` so tests can access call recording
    /// and error stubs directly.
    var playbackServiceStub: FakePlaybackService

    /// The TagReaderService instance returned by makeTagReaderService().
    var tagReaderServiceStub: TagReaderService

    /// The LyricsService instance returned by makeLyricsService().
    /// Defaults to FakeLyricsService (no-op, safe across many test instances).
    /// Tests that need real LyricsService behaviour must inject one explicitly.
    var lyricsServiceStub: LyricsService

    // MARK: - Initialization

    init(
        playbackService: FakePlaybackService = FakePlaybackService(),
        tagReader: TagReaderService = FakeTagReaderService(),
        lyricsService: LyricsService = FakeLyricsService()
    ) {
        self.playbackServiceStub = playbackService
        self.tagReaderServiceStub = tagReader
        self.lyricsServiceStub = lyricsService
    }

    // MARK: - CoreServiceProviding

    func makePlaybackService(isProUser: Bool) -> PlaybackService {
        makePlaybackServiceCallCount += 1
        lastIsProUser = isProUser
        return playbackServiceStub
    }

    func makeTagReaderService() -> TagReaderService {
        makeTagReaderServiceCallCount += 1
        return tagReaderServiceStub
    }

    func makeLyricsService() -> LyricsService {
        makeLyricsServiceCallCount += 1
        return lyricsServiceStub
    }
}

// MARK: - FakePlaybackService

/// Fake PlaybackService for deterministic test setups.
///
/// Records all method calls and supports configurable error stubs,
/// enabling Slice 4 tests to verify exactly which service methods
/// are called and simulate failure scenarios deterministically.
///
/// **Call recording:**
/// - `loadCallCount` / `loadedURLs` — how many times and with which URLs `load` was called
/// - `playCallCount` — how many times `play()` was called
/// - `pauseCallCount` — how many times `pause()` was called
/// - `stopCallCount` — how many times `stop()` was called
/// - `seekCallCount` / `seekedToSeconds` — seek call count and argument history
///
/// **Error stubs:**
/// - `stubbedLoadError` — if set, `load()` throws this error
/// - `stubbedPlayError` — if set, `play()` throws this error
/// - `stubbedSeekError` — if set, `seek(to:)` throws this error
///
/// **Query stubs:**
/// - `stubbedDuration` — returned by `duration()`
/// - `stubbedCurrentTime` — returned by `currentTime()`
///
/// **Usage:**
/// ```swift
/// let fake = FakePlaybackService()
/// fake.stubbedPlayError = PlaybackError.outputError
///
/// do {
///     try await fake.play()
///     XCTFail("Expected error")
/// } catch {
///     XCTAssertEqual(fake.playCallCount, 1)
/// }
/// ```
final class FakePlaybackService: PlaybackService {

    // MARK: - Call Recording

    /// Number of times `load(url:)` was called.
    private(set) var loadCallCount = 0

    /// Resets all call counters. Use in tests to get a clean baseline
    /// after setup (e.g. after loadTrackIntoSUT()).
    func resetCounts() {
        loadCallCount = 0
        playCallCount = 0
        pauseCallCount = 0
        stopCallCount = 0
        seekCallCount = 0
        seekedToSeconds = []
        loadedURLs = []
        setVolumeCallCount = 0
        lastSetVolume = nil
    }

    /// Ordered list of URLs passed to `load(url:)`.
    private(set) var loadedURLs: [URL] = []

    /// Number of times `play()` was called.
    private(set) var playCallCount = 0

    /// Number of times `pause()` was called.
    private(set) var pauseCallCount = 0

    /// Number of times `stop()` was called.
    private(set) var stopCallCount = 0

    /// Number of times `seek(to:)` was called.
    private(set) var seekCallCount = 0

    /// Ordered list of `seconds` values passed to `seek(to:)`.
    private(set) var seekedToSeconds: [TimeInterval] = []

    /// Number of times `setVolume(_:)` was called.
    private(set) var setVolumeCallCount = 0

    /// Last volume value passed to `setVolume(_:)`.
    private(set) var lastSetVolume: Float?

    // MARK: - Stub Configuration

    /// If set, `load(url:)` throws this error instead of transitioning state.
    var stubbedLoadError: Error? = nil

    /// If set, `play()` throws this error instead of transitioning state.
    var stubbedPlayError: Error? = nil

    /// If set, `seek(to:)` throws this error instead of succeeding.
    var stubbedSeekError: Error? = nil

    /// Value returned by `duration()`.
    var stubbedDuration: TimeInterval = 0

    /// Value returned by `currentTime()`.
    var stubbedCurrentTime: TimeInterval = 0

    // MARK: - PlaybackService

    var state: PlaybackState = .idle

    func load(url: URL) async throws {
        loadCallCount += 1
        loadedURLs.append(url)
        if let error = stubbedLoadError { throw error }
        state = .loading
    }

    func play() async throws {
        playCallCount += 1
        if let error = stubbedPlayError { throw error }
        state = .playing
    }

    func pause() async {
        pauseCallCount += 1
        state = .paused
    }

    func stop() async {
        stopCallCount += 1
        state = .stopped
    }

    func seek(to seconds: TimeInterval) async throws {
        seekCallCount += 1
        seekedToSeconds.append(seconds)
        if let error = stubbedSeekError { throw error }
    }

    func currentTime() async -> TimeInterval { stubbedCurrentTime }
    func duration() async -> TimeInterval { stubbedDuration }

    func setVolume(_ volume: Float) async {
        setVolumeCallCount += 1
        lastSetVolume = volume
    }
}

// MARK: - FakeLyricsService

/// No-op LyricsService for tests that do not exercise lyrics behaviour.
///
/// All methods return empty / no-result. Tests that want real behaviour must
/// inject `DefaultLyricsService()` (or a custom fake) explicitly via
/// `FakeCoreProvider(lyricsService:)`.
///
/// **Why a separate fake?** Constructing many `DefaultLyricsService` instances
/// across the test suite (one per `FakeCoreProvider`) triggers an Xcode 26
/// beta Swift runtime double-free when those instances coexist or
/// successively allocate at the same address. `FakeLyricsService` is a tiny
/// final class with no closure storage and no Locale dependency, sidestepping
/// the toolchain bug entirely.
final class FakeLyricsService: LyricsService {
    func resolveAvailability(for track: Track) -> LyricsResolution {
        .none
    }

    func resolveContent(
        for track: Track,
        source: LyricsSource,
        languageCode: String?,
        encodingName: String?
    ) throws -> String {
        throw LyricsServiceError.noEmbeddedLyrics
    }

    func stripLRCTimestamps(_ raw: String) -> String { raw }

    func detectEncoding(of data: Data) -> String.Encoding { .utf8 }
}

// MARK: - StubLyricsService

/// Configurable LyricsService stub for tests that need to verify AppState's
/// reactions to specific `LyricsResolution` outputs.
///
/// Unlike `FakeLyricsService` (no-op), this stub lets tests dictate exactly
/// what `resolveAvailability(for:)` returns for any given track, so AppState
/// publisher chains and action methods can be exercised without relying on
/// the real `DefaultLyricsService` (which suffers from a Xcode 26 beta
/// runtime double-free when multiple instances coexist).
final class StubLyricsService: LyricsService {
    /// What `resolveAvailability(for:)` should return.
    /// Defaults to `.none` so unconfigured tests behave like FakeLyricsService.
    var stubbedResolution: LyricsResolution = .none

    /// Records each call to `resolveAvailability(for:)` for assertion.
    private(set) var resolveAvailabilityCallCount = 0
    private(set) var lastResolvedTrack: Track?

    func resolveAvailability(for track: Track) -> LyricsResolution {
        resolveAvailabilityCallCount += 1
        lastResolvedTrack = track
        return stubbedResolution
    }

    func resolveContent(
        for track: Track,
        source: LyricsSource,
        languageCode: String?,
        encodingName: String?
    ) throws -> String {
        ""
    }

    func stripLRCTimestamps(_ raw: String) -> String { raw }
    func detectEncoding(of data: Data) -> String.Encoding { .utf8 }
}
