//
//  PlaylistCollectionLoadTests.swift
//  HarmoniaPlayerTests
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import Harmonia_Player

/// Tests for `PlaylistCollection.load(urls:)`: appending, duplicate and
/// format gating, metadata enrichment and its error fallback, the
/// blocking-operation flag, the security-scoped bookmark capture, the
/// background metadata refresh, and the `onTracksAppended` notification.
@MainActor
final class PlaylistCollectionLoadTests: XCTestCase {

    // MARK: - Lifecycle

    private var createdSuiteNames: [String] = []

    override func tearDown() async throws {
        for name in createdSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private struct Fixture {
        let sut: PlaylistCollection
        let tagReader: FakeTagReaderService
        let store: FakePlaylistStore
        let alertCenter: AlertCenter
        let settingsStore: SettingsStore
    }

    private func makeSUT() -> Fixture {
        let suiteName = "hp-test-\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let tagReader = FakeTagReaderService()
        let store = FakePlaylistStore()
        let alertCenter = AlertCenter()
        let settingsStore = SettingsStore(iapManager: MockIAPManager(), userDefaults: defaults)
        let sut = PlaylistCollection(
            tagReaderService: tagReader,
            fileDropService: FileDropService(),
            playlistStore: store,
            undoManager: UndoManager(),
            alertCenter: alertCenter,
            settingsStore: settingsStore,
            userDefaults: defaults
        )
        return Fixture(sut: sut, tagReader: tagReader, store: store,
                       alertCenter: alertCenter, settingsStore: settingsStore)
    }

    private func makeURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0).mp3") }
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).mp3")
    }

    // MARK: - load(urls:)

    func testLoad_EmptyPlaylist_AddsTrack() async {
        let f = makeSUT()

        await f.sut.load(urls: makeURLs(["song"]))

        XCTAssertEqual(f.sut.playlist.count, 1)
    }

    func testLoad_ExistingPlaylist_AppendsTrack() async {
        let f = makeSUT()
        await f.sut.load(urls: makeURLs(["a"]))

        await f.sut.load(urls: makeURLs(["b"]))

        XCTAssertEqual(f.sut.playlist.count, 2)
    }

    func testLoad_MultipleURLs_AddsAll() async {
        let f = makeSUT()

        await f.sut.load(urls: makeURLs(["a", "b"]))

        XCTAssertEqual(f.sut.playlist.count, 2)
    }

    func testLoad_DerivesTitleFromFilename() async {
        let f = makeSUT()

        await f.sut.load(urls: [URL(fileURLWithPath: "/tmp/my-song.mp3")])

        XCTAssertEqual(f.sut.playlist.tracks.first?.title, "my-song")
    }

    // MARK: - load(urls:) duplicate handling

    func testLoad_DuplicateURL_DefaultBehaviour_IsSkipped() async {
        let f = makeSUT()
        let url = makeURLs(["track1"])[0]
        await f.sut.load(urls: [url])
        XCTAssertEqual(f.sut.playlist.tracks.count, 1, "Precondition")

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.count, 1,
                       "Duplicate should be skipped when allowDuplicateTracks == false")
        XCTAssertEqual(f.alertCenter.skippedDuplicateURLs.count, 1,
                       "Skipped URL should be reported")
    }

    func testLoad_DuplicateURL_WhenAllowed_IsAdded() async {
        let f = makeSUT()
        f.settingsStore.allowDuplicateTracks = true
        let url = makeURLs(["track1"])[0]
        await f.sut.load(urls: [url])
        XCTAssertEqual(f.sut.playlist.tracks.count, 1, "Precondition")

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.count, 2,
                       "Duplicate should be added when allowDuplicateTracks == true")
        XCTAssertTrue(f.alertCenter.skippedDuplicateURLs.isEmpty,
                      "skippedDuplicateURLs must be empty when duplicate is allowed")
    }

    // MARK: - isPerformingBlockingOperation

    func testIsPerformingBlockingOperation_InitiallyFalse() {
        let f = makeSUT()

        XCTAssertFalse(f.sut.isPerformingBlockingOperation)
    }

    func testLoad_ResetsBlockingFlagOnCompletion() async {
        let f = makeSUT()

        await f.sut.load(urls: [URL(fileURLWithPath: "/tmp/a.mp3")])

        XCTAssertFalse(f.sut.isPerformingBlockingOperation,
                       "Flag must be reset after load(urls:) completes")
    }

    // MARK: - Bookmark capture during load

    /// Verifies that `load(urls:)` produces a Track whose URL round-trips
    /// through encode / decode and remains accessible, which confirms that
    /// the per-URL security-scoped access fires during load.
    func testLoad_BookmarkCapturedAfterLoad() async throws {
        let f = makeSUT()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaylistCollectionLoadTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realFile = tempDir.appendingPathComponent("track.mp3")
        try Data("audio-bytes".utf8).write(to: realFile)

        await f.sut.load(urls: [realFile])

        XCTAssertEqual(f.sut.playlists[0].tracks.count, 1,
            "load(urls:) must add exactly one track for a single valid URL.")
        let loaded = try XCTUnwrap(f.sut.playlists[0].tracks.first)
        XCTAssertEqual(loaded.url, realFile,
            "Track URL must match the input URL exactly.")
        XCTAssertTrue(loaded.isAccessible,
            "Newly loaded track with real on-disk file must be accessible.")

        let encoded = try JSONEncoder().encode(loaded)
        let restored = try JSONDecoder().decode(Track.self, from: encoded)
        XCTAssertEqual(restored.url, realFile,
            "URL must roundtrip through encode/decode under .withSecurityScope.")
        XCTAssertTrue(restored.isAccessible,
            "Restored track must remain accessible (bookmark resolves AND "
            + "startAccessingSecurityScopedResource succeeds).")
    }

    // MARK: - Metadata enrichment

    func testLoad_CallsTagReaderForEachURL() async {
        let f = makeSUT()
        let urls = [makeURL("a"), makeURL("b"), makeURL("c")]

        await f.sut.load(urls: urls)

        XCTAssertEqual(f.tagReader.readMetadataCallCount, 3,
                       "load(urls:) must call readMetadata once per URL")
    }

    func testLoad_UsesMetadataTitle() async {
        let f = makeSUT()
        let url = makeURL("song")
        f.tagReader.stubbedMetadata[url] = Track(url: url, title: "Real Title", artist: "", album: "")

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.first?.title, "Real Title",
                       "load(urls:) must use the title returned by TagReaderService")
    }

    func testLoad_UsesMetadataArtist() async {
        let f = makeSUT()
        let url = makeURL("song")
        f.tagReader.stubbedMetadata[url] = Track(url: url, title: "Title", artist: "Artist X", album: "")

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.first?.artist, "Artist X",
                       "load(urls:) must use the artist returned by TagReaderService")
    }

    func testLoad_UsesMetadataAlbum() async {
        let f = makeSUT()
        let url = makeURL("song")
        f.tagReader.stubbedMetadata[url] = Track(url: url, title: "Title", artist: "Artist", album: "Album Y")

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.first?.album, "Album Y",
                       "load(urls:) must use the album returned by TagReaderService")
    }

    func testLoad_UsesMetadataDuration() async {
        let f = makeSUT()
        let url = makeURL("song")
        f.tagReader.stubbedMetadata[url] = Track(url: url, title: "Title", artist: "Artist",
                                                 album: "Album", duration: 180.0)

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.first?.duration, 180.0,
                       "load(urls:) must use the duration returned by TagReaderService")
    }

    func testLoad_MultipleURLs_AllEnriched() async throws {
        let f = makeSUT()
        let urlA = makeURL("track-a")
        let urlB = makeURL("track-b")
        f.tagReader.stubbedMetadata[urlA] = Track(url: urlA, title: "Title A", artist: "Artist A", album: "Album A")
        f.tagReader.stubbedMetadata[urlB] = Track(url: urlB, title: "Title B", artist: "Artist B", album: "Album B")

        await f.sut.load(urls: [urlA, urlB])

        XCTAssertEqual(f.sut.playlist.count, 2)
        XCTAssertEqual(try XCTUnwrap(f.sut.playlist.tracks[safe: 0]).title, "Title A",
                       "First track should have metadata from URL A")
        XCTAssertEqual(try XCTUnwrap(f.sut.playlist.tracks[safe: 1]).title, "Title B",
                       "Second track should have metadata from URL B")
    }

    func testLoad_IsAdditive_WithMetadata() async throws {
        let f = makeSUT()
        let urlA = makeURL("existing")
        f.tagReader.stubbedMetadata[urlA] = Track(url: urlA, title: "Existing Track", artist: "", album: "")
        await f.sut.load(urls: [urlA])
        XCTAssertEqual(f.sut.playlist.count, 1, "Pre-condition: playlist should have 1 track")

        let urlB = makeURL("new")
        f.tagReader.stubbedMetadata[urlB] = Track(url: urlB, title: "New Track", artist: "", album: "")
        await f.sut.load(urls: [urlB])

        XCTAssertEqual(f.sut.playlist.count, 2,
                       "load(urls:) must remain additive when integrating metadata")
        XCTAssertEqual(try XCTUnwrap(f.sut.playlist.tracks[safe: 0]).title, "Existing Track")
        XCTAssertEqual(try XCTUnwrap(f.sut.playlist.tracks[safe: 1]).title, "New Track")
    }

    /// A track restored with `artworkData == nil` is picked up by the
    /// background re-read and refilled.
    func testRefresh_FillsArtworkWhenNil() async {
        let f = makeSUT()
        let url = makeURL("art-song")
        f.tagReader.stubbedMetadata[url] = Track(url: url, title: "Song")
        await f.sut.load(urls: [url])
        XCTAssertNil(f.sut.playlist.tracks.first?.artworkData,
                     "precondition: loaded track has no artwork yet")

        var enriched = Track(url: url, title: "Song")
        enriched.artworkData = Data([0xAA, 0xBB, 0xCC])
        f.tagReader.stubbedMetadata[url] = enriched

        await f.sut.refreshMetadataIfNeeded()

        XCTAssertEqual(f.sut.playlist.tracks.first?.artworkData, Data([0xAA, 0xBB, 0xCC]),
                       "refresh must refill artwork for a nil-artwork track")
    }

    // MARK: - Metadata error fallback

    func testLoad_MetadataError_FallsBackToURLDerivedTrack() async {
        let f = makeSUT()
        let url = makeURL("song")
        f.tagReader.stubbedErrors[url] = PlaybackError.failedToOpenFile

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.sut.playlist.tracks.first?.title, "song",
                       "On metadata error, track title must be derived from the URL filename")
    }

    func testLoad_MetadataError_SetsLastError() async {
        let f = makeSUT()
        let url = makeURL("song")
        f.tagReader.stubbedErrors[url] = PlaybackError.failedToOpenFile

        await f.sut.load(urls: [url])

        XCTAssertEqual(f.alertCenter.lastError, .failedToOpenFile,
                       "On metadata error, lastError must be set to .failedToOpenFile")
    }

    func testLoad_PartialError_SuccessfulURLsStillEnriched() async throws {
        let f = makeSUT()
        let goodURL = makeURL("good")
        let badURL = makeURL("bad")
        f.tagReader.stubbedMetadata[goodURL] = Track(url: goodURL, title: "Good Track", artist: "Artist", album: "Album")
        f.tagReader.stubbedErrors[badURL] = PlaybackError.failedToOpenFile

        await f.sut.load(urls: [goodURL, badURL])

        XCTAssertEqual(f.sut.playlist.count, 2)
        XCTAssertEqual(try XCTUnwrap(f.sut.playlist.tracks[safe: 0]).title, "Good Track",
                       "Successful URL must still be enriched with metadata")
        XCTAssertEqual(try XCTUnwrap(f.sut.playlist.tracks[safe: 1]).title, "bad",
                       "Erroring URL must fall back to URL-derived title")
    }

    func testLoad_NoError_LastErrorRemainsNil() async {
        let f = makeSUT()
        let url = makeURL("clean")
        f.tagReader.stubbedMetadata[url] = Track(url: url, title: "Clean Track", artist: "", album: "")

        await f.sut.load(urls: [url])

        XCTAssertNil(f.alertCenter.lastError,
                     "lastError must remain nil when all metadata reads succeed")
    }

    func testLoad_MultipleErrors_LastErrorIsSet() async {
        let f = makeSUT()
        let urlA = makeURL("a")
        let urlB = makeURL("b")
        f.tagReader.stubbedErrors[urlA] = PlaybackError.failedToOpenFile
        f.tagReader.stubbedErrors[urlB] = PlaybackError.failedToOpenFile

        await f.sut.load(urls: [urlA, urlB])

        XCTAssertNotNil(f.alertCenter.lastError,
                        "lastError must be set when at least one metadata read fails")
    }

    // MARK: - Format gate at load time

    func testLoad_FLAC_FreeTier_BlockedAsUnsupported() async {
        let f = makeSUT()

        await f.sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])

        XCTAssertTrue(f.sut.playlist.tracks.isEmpty, "FLAC must be blocked at load time")
        XCTAssertEqual(f.alertCenter.skippedUnsupportedURLs.count, 1,
                       "FLAC must appear in skippedUnsupportedURLs")
    }

    func testLoad_DSF_FreeTier_BlockedAsUnsupported() async {
        let f = makeSUT()

        await f.sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dsf")])

        XCTAssertTrue(f.sut.playlist.tracks.isEmpty, "DSF must be blocked at load time")
        XCTAssertEqual(f.alertCenter.skippedUnsupportedURLs.count, 1)
    }

    func testLoad_DFF_FreeTier_BlockedAsUnsupported() async {
        let f = makeSUT()

        await f.sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dff")])

        XCTAssertTrue(f.sut.playlist.tracks.isEmpty, "DFF must be blocked at load time")
        XCTAssertEqual(f.alertCenter.skippedUnsupportedURLs.count, 1)
    }

    func testLoad_UnsupportedFormat_BlockedWithAlert() async {
        let f = makeSUT()

        await f.sut.load(urls: [URL(fileURLWithPath: "/tmp/test.xyz")])

        XCTAssertTrue(f.sut.playlist.tracks.isEmpty, "Unsupported format must not be added")
        XCTAssertEqual(f.alertCenter.skippedUnsupportedURLs.count, 1)
    }

    // MARK: - onTracksAppended

    func testLoad_CallsOnTracksAppendedWithAddedIDs() async {
        let f = makeSUT()
        var received: [[Track.ID]] = []
        f.sut.onTracksAppended = { received.append($0) }

        await f.sut.load(urls: makeURLs(["a", "b"]))

        XCTAssertEqual(received.count, 1, "onTracksAppended must be called once per load")
        XCTAssertEqual(received.first, f.sut.playlist.tracks.map(\.id),
                       "onTracksAppended must carry the added ids in playlist order")
    }

    func testLoad_NothingAdded_DoesNotCallOnTracksAppended() async {
        let f = makeSUT()
        let url = makeURL("dup")
        await f.sut.load(urls: [url])
        var callCount = 0
        f.sut.onTracksAppended = { _ in callCount += 1 }

        await f.sut.load(urls: [url])

        XCTAssertEqual(callCount, 0, "a load that adds nothing must not notify")
    }

    // MARK: - Pro-format gating rows, disabled while the Pro formats cannot
    // enter a playlist. Bodies preserved for the Pro program.
    //
    // /// FLAC must be added to the playlist for Free users.
    // /// Paywall is shown only when the user attempts to play the track.
    // func testLoad_FLAC_FreeTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1,
    //                    "FLAC must be added to playlist for Free user")
    // }
    //
    // func testLoad_FLAC_FreeTier_NoPaywall() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
    //     XCTAssertFalse(sut.showPaywall,
    //                    "Loading FLAC must not trigger Paywall — only playing does")
    // }
    //
    // func testLoad_DSF_FreeTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dsf")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1)
    // }
    //
    // func testLoad_DFF_FreeTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: false)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.dff")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1)
    // }
    //
    // func testLoad_FLAC_ProTier_AddsToPlaylist() async {
    //     makeSUT(isProUnlocked: true)
    //     await sut.load(urls: [URL(fileURLWithPath: "/tmp/test.flac")])
    //     XCTAssertEqual(sut.playlist.tracks.count, 1,
    //                    "FLAC must be added for Pro user")
    //     XCTAssertFalse(sut.showPaywall)
    // }
    //
    // func testPlayGate_FLAC_FreeTier_ShowsPaywall() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertTrue(sut.showPaywall,
    //                   "Playing FLAC on Free tier must show Paywall")
    // }
    //
    // func testPlayGate_FLAC_FreeTier_DoesNotPlay() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertEqual(fakePlaybackService.loadCallCount, 0,
    //                    "PlaybackService must not be called for format-gated track")
    // }
    //
    // func testPlayGate_FLAC_ProTier_Proceeds() async {
    //     makeSUT(isProUnlocked: true)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertEqual(fakePlaybackService.loadCallCount, 1)
    // }
    //
    // func testPlayGate_FLAC_ProTier_NoPaywall() async {
    //     makeSUT(isProUnlocked: true)
    //     let track = await addTrack(extension: "flac")
    //     await sut.play(trackID: track.id)
    //     XCTAssertFalse(sut.showPaywall)
    // }
    //
    // /// Given playlist [MP3, FLAC, MP3] and paywallDismissedThisSession == true,
    // /// when trackDidFinishPlaying() fires after MP3[0],
    // /// FLAC is silently skipped and MP3[2] plays.
    // func testAutoPlay_FLAC_DismissedSession_SilentSkip() async {
    //     makeSUT(isProUnlocked: false)
    //     let mp3a = URL(fileURLWithPath: "/tmp/track1.mp3")
    //     let flac = URL(fileURLWithPath: "/tmp/track2.flac")
    //     let mp3b = URL(fileURLWithPath: "/tmp/track3.mp3")
    //     await sut.load(urls: [mp3a, flac, mp3b])
    //
    //     await sut.play(trackID: sut.playlist.tracks[0].id)
    //     sut.paywallDismissedThisSession = true
    //     fakePlaybackService.resetCounts()
    //
    //     await sut.trackDidFinishPlaying()
    //
    //     XCTAssertEqual(sut.currentTrack?.url, mp3b,
    //                    "FLAC must be silently skipped; MP3[2] should be playing")
    //     XCTAssertFalse(sut.showPaywall,
    //                    "Paywall must not appear when paywallDismissedThisSession is true")
    // }
    //
    // /// Given playlist [MP3, FLAC] and paywallDismissedThisSession == false,
    // /// when trackDidFinishPlaying() fires after MP3[0],
    // /// Paywall is shown for the FLAC track.
    // func testAutoPlay_FLAC_NotDismissed_ShowsPaywall() async {
    //     makeSUT(isProUnlocked: false)
    //     let mp3 = URL(fileURLWithPath: "/tmp/track1.mp3")
    //     let flac = URL(fileURLWithPath: "/tmp/track2.flac")
    //     await sut.load(urls: [mp3, flac])
    //
    //     await sut.play(trackID: sut.playlist.tracks[0].id)
    //     XCTAssertFalse(sut.paywallDismissedThisSession, "Pre-condition")
    //
    //     await sut.trackDidFinishPlaying()
    //
    //     XCTAssertTrue(sut.showPaywall,
    //                   "Paywall must appear when paywallDismissedThisSession is false")
    // }
    //
    // /// Playing a format-gated FLAC must show Paywall but must NOT set lastError.
    // func testPlayGate_FLAC_FreeTier_DoesNotSetLastError() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //
    //     await sut.play(trackID: track.id)
    //
    //     XCTAssertNil(sut.lastError,
    //                  "lastError must not be set when format gate blocks playback — Paywall is sufficient feedback")
    // }
    //
    // /// Playing a format-gated FLAC must post bringMainWindowToFront notification.
    // func testPlayGate_FLAC_FreeTier_PostsBringMainWindowToFrontNotification() async {
    //     makeSUT(isProUnlocked: false)
    //     let track = await addTrack(extension: "flac")
    //
    //     var notificationReceived = false
    //     let observer = NotificationCenter.default.addObserver(
    //         forName: .bringMainWindowToFront,
    //         object: nil,
    //         queue: .main
    //     ) { _ in notificationReceived = true }
    //     defer { NotificationCenter.default.removeObserver(observer) }
    //
    //     await sut.play(trackID: track.id)
    //
    //     XCTAssertTrue(notificationReceived,
    //                   "bringMainWindowToFront must be posted when format gate blocks FLAC on Free tier")
    // }
    //
    // /// FLAC is a recognised format (Pro-only) and must be added to the playlist
    // /// via importPlaylist — same as load(urls:) behaviour. Format gate at play time.
    // func testImportPlaylist_FLAC_AddsToPlaylist() async throws {
    //     makeSUT(isProUnlocked: false)
    //     let m3u8 = try makeM3U8(filenames: ["track.flac"])
    //
    //     await sut.importPlaylist(from: m3u8)
    //
    //     XCTAssertEqual(sut.playlist.tracks.count, 1,
    //                    "FLAC must be added to playlist via importPlaylist — gated at play time, not load time")
    // }
}
