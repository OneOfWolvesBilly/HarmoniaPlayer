//
//  FakePlaybackServiceTests.swift
//  HarmoniaPlayerTests
//
//  Slice 4-A: Verify FakePlaybackService call recording and stub behaviour.
//

import XCTest
@testable import HarmoniaPlayer

/// Unit tests for the upgraded FakePlaybackService (Slice 4-A).
///
/// Verifies call recording, state transitions, and error stubs so that
/// Slice 4-B/C/D tests can rely on this fake with confidence.
///
/// **Swift 6 / Xcode 26 note:**
/// `@MainActor` is required because `FakePlaybackService.state` is of type
/// `PlaybackState` which is used in `AppState` (`@MainActor`-isolated).
@MainActor
final class FakePlaybackServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeURL(_ filename: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(filename).mp3")
    }

    // MARK: - Slice 4-A: load() — Call Recording

    /// testFake_Load_RecordsURL
    ///
    /// Given: No stub configured
    /// When:  `load(url:)` is called
    /// Then:  `loadedURLs == [url]`
    func testFake_Load_RecordsURL() async throws {
        // Given
        let fake = FakePlaybackService()
        let url = makeURL("song")

        // When
        try await fake.load(url: url)

        // Then
        XCTAssertEqual(fake.loadedURLs, [url])
        XCTAssertEqual(fake.loadCallCount, 1)
    }

    /// testFake_Load_NoError_SetsLoadingState
    ///
    /// Given: No stub configured
    /// When:  `load(url:)` is called
    /// Then:  `state == .loading`
    func testFake_Load_NoError_SetsLoadingState() async throws {
        // Given
        let fake = FakePlaybackService()

        // When
        try await fake.load(url: makeURL("song"))

        // Then
        XCTAssertEqual(fake.state, .loading)
    }

    /// testFake_Load_StubbedError_Throws
    ///
    /// Given: `stubbedLoadError` is set
    /// When:  `load(url:)` is called
    /// Then:  Throws the stubbed error
    func testFake_Load_StubbedError_Throws() async {
        // Given
        let fake = FakePlaybackService()
        fake.stubbedLoadError = PlaybackError.failedToOpenFile

        // When / Then
        do {
            try await fake.load(url: makeURL("broken"))
            XCTFail("Expected error to be thrown")
        } catch let error as PlaybackError {
            XCTAssertEqual(error, .failedToOpenFile)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Slice 4-A: play() — Call Recording

    /// testFake_Play_RecordsCall
    ///
    /// Given: Any state
    /// When:  `play()` is called
    /// Then:  `playCallCount == 1`
    func testFake_Play_RecordsCall() async throws {
        // Given
        let fake = FakePlaybackService()

        // When
        try await fake.play()

        // Then
        XCTAssertEqual(fake.playCallCount, 1)
    }

    /// testFake_Play_StubbedError_Throws
    ///
    /// Given: `stubbedPlayError` is set
    /// When:  `play()` is called
    /// Then:  Throws the stubbed error; call is still recorded
    func testFake_Play_StubbedError_Throws() async {
        // Given
        let fake = FakePlaybackService()
        fake.stubbedPlayError = PlaybackError.outputError

        // When / Then
        do {
            try await fake.play()
            XCTFail("Expected error to be thrown")
        } catch let error as PlaybackError {
            XCTAssertEqual(error, .outputError)
            XCTAssertEqual(fake.playCallCount, 1,
                           "Call should be recorded even when error is thrown")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Slice 4-A: pause() — Call Recording

    /// testFake_Pause_RecordsCall
    ///
    /// Given: Any state
    /// When:  `pause()` is called
    /// Then:  `pauseCallCount == 1`
    func testFake_Pause_RecordsCall() async {
        // Given
        let fake = FakePlaybackService()

        // When
        await fake.pause()

        // Then
        XCTAssertEqual(fake.pauseCallCount, 1)
    }

    // MARK: - Slice 4-A: stop() — Call Recording

    /// testFake_Stop_RecordsCall
    ///
    /// Given: Any state
    /// When:  `stop()` is called
    /// Then:  `stopCallCount == 1`
    func testFake_Stop_RecordsCall() async {
        // Given
        let fake = FakePlaybackService()

        // When
        await fake.stop()

        // Then
        XCTAssertEqual(fake.stopCallCount, 1)
    }

    // MARK: - Slice 4-A: seek() — Call Recording

    /// testFake_Seek_RecordsSeconds
    ///
    /// Given: Any state
    /// When:  `seek(to: 42.0)` is called
    /// Then:  `seekedToSeconds == [42.0]`
    func testFake_Seek_RecordsSeconds() async throws {
        // Given
        let fake = FakePlaybackService()

        // When
        try await fake.seek(to: 42.0)

        // Then
        XCTAssertEqual(fake.seekedToSeconds, [42.0])
        XCTAssertEqual(fake.seekCallCount, 1)
    }

    /// testFake_Seek_StubbedError_Throws
    ///
    /// Given: `stubbedSeekError` is set
    /// When:  `seek(to:)` is called
    /// Then:  Throws the stubbed error; call is still recorded
    func testFake_Seek_StubbedError_Throws() async {
        // Given
        let fake = FakePlaybackService()
        fake.stubbedSeekError = PlaybackError.failedToDecode

        // When / Then
        do {
            try await fake.seek(to: 10.0)
            XCTFail("Expected error to be thrown")
        } catch let error as PlaybackError {
            XCTAssertEqual(error, .failedToDecode)
            XCTAssertEqual(fake.seekCallCount, 1,
                           "Call should be recorded even when error is thrown")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Slice 4-A: Query Stubs

    /// testFake_Duration_ReturnsStubbedValue
    ///
    /// Given: `stubbedDuration = 180.0`
    /// When:  `duration()` is called
    /// Then:  Returns `180.0`
    func testFake_Duration_ReturnsStubbedValue() async {
        // Given
        let fake = FakePlaybackService()
        fake.stubbedDuration = 180.0

        // When
        let result = await fake.duration()

        // Then
        XCTAssertEqual(result, 180.0)
    }

    /// testFake_CurrentTime_ReturnsStubbedValue
    ///
    /// Given: `stubbedCurrentTime = 45.5`
    /// When:  `currentTime()` is called
    /// Then:  Returns `45.5`
    func testFake_CurrentTime_ReturnsStubbedValue() async {
        // Given
        let fake = FakePlaybackService()
        fake.stubbedCurrentTime = 45.5

        // When
        let result = await fake.currentTime()

        // Then
        XCTAssertEqual(result, 45.5)
    }

    // MARK: - Slice 4-A: Initial State

    /// testFake_InitialState_IsIdle
    ///
    /// Given: Freshly created FakePlaybackService
    /// When:  `state` is read
    /// Then:  `.idle`
    func testFake_InitialState_IsIdle() {
        let fake = FakePlaybackService()
        XCTAssertEqual(fake.state, .idle)
    }

    /// testFake_AllCallCounts_ZeroOnInit
    ///
    /// Given: Freshly created FakePlaybackService
    /// When:  All call counts are read
    /// Then:  All are `0`
    func testFake_AllCallCounts_ZeroOnInit() {
        let fake = FakePlaybackService()
        XCTAssertEqual(fake.loadCallCount, 0)
        XCTAssertEqual(fake.playCallCount, 0)
        XCTAssertEqual(fake.pauseCallCount, 0)
        XCTAssertEqual(fake.stopCallCount, 0)
        XCTAssertEqual(fake.seekCallCount, 0)
        XCTAssertTrue(fake.loadedURLs.isEmpty)
        XCTAssertTrue(fake.seekedToSeconds.isEmpty)
    }
}
