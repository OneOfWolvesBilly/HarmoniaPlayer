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

    // MARK: - Stubs

    /// The PlaybackService stub returned by makePlaybackService().
    ///
    /// Typed as `FakePlaybackService` so tests can access call recording
    /// and error stubs directly.
    var playbackServiceStub: FakePlaybackService

    /// The TagReaderService instance returned by makeTagReaderService().
    var tagReaderServiceStub: TagReaderService

    // MARK: - Initialization

    init(
        playbackService: FakePlaybackService = FakePlaybackService(),
        tagReader: TagReaderService = FakeTagReaderService()
    ) {
        self.playbackServiceStub = playbackService
        self.tagReaderServiceStub = tagReader
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
}
