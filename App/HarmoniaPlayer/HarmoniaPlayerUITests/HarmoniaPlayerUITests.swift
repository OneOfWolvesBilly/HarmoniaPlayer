//
//  HarmoniaPlayerUITests.swift
//  HarmoniaPlayerUITests
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  XCUITest suite for Slice 6-B. Verifies that all required UI elements are
//  accessible after app launch. These tests do not exercise playback — they
//  confirm that the view hierarchy is correctly assembled and that all
//  accessibility identifiers required by future interaction tests are present.
//
//  TEST STRATEGY
//  -------------
//  Each test launches the app, activates the window (required on macOS to
//  expose the accessibility tree), and checks for the existence of a single
//  element. This keeps each test focused and makes failures easy to diagnose.
//
//  macOS NOTE
//  ----------
//  `window.click()` in `setUpWithError` is required on macOS + SwiftUI:
//  without it the accessibility tree may not be fully exposed and
//  `waitForExistence` can time out even when the element is visible.
//

import XCTest

final class HarmoniaPlayerUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Force English so menu item labels and UI strings are predictable
        // regardless of system language or previously saved language preference.
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-hp.selectedLanguage", "en",
        ]
        app.launch()
        app.activate()
        // Click the window to ensure macOS exposes the full accessibility tree.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10),
                      "Main window must appear within 10 seconds of launch")
        window.click()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch Tests

    /// Verifies the two primary regions of the layout are present:
    /// the add-files button (always visible) and the play-pause transport button.
    func testAppLaunches_ShowsPlaylistAndPlayer() {
        XCTAssertTrue(app.buttons["add-files-button"].waitForExistence(timeout: 5),
                      "Add-files button must be visible on launch")
        XCTAssertTrue(app.buttons["play-pause-button"].waitForExistence(timeout: 5),
                      "Play-pause button must be visible on launch")
    }

    // MARK: - Transport Control Tests

    /// Verifies the play/pause toggle button is accessible.
    func testPlayPauseButton_Exists() {
        XCTAssertTrue(app.buttons["play-pause-button"].waitForExistence(timeout: 5),
                      "play-pause-button must exist in PlayerView")
    }

    /// Verifies the stop button is accessible.
    func testStopButton_Exists() {
        XCTAssertTrue(app.buttons["stop-button"].waitForExistence(timeout: 5),
                      "stop-button must exist in PlayerView")
    }

    /// Verifies the seek slider is accessible and can be interacted with.
    func testProgressSlider_Exists() {
        XCTAssertTrue(app.sliders["progress-slider"].waitForExistence(timeout: 5),
                      "progress-slider must exist in PlayerView")
    }

    // MARK: - Mode Control Tests

    /// Verifies the repeat cycle button is accessible.
    func testRepeatButton_Exists() {
        XCTAssertTrue(app.buttons["repeat-button"].waitForExistence(timeout: 5),
                      "repeat-button must exist in PlayerView")
    }

    /// Verifies the shuffle toggle button is accessible.
    func testShuffleButton_Exists() {
        XCTAssertTrue(app.buttons["shuffle-button"].waitForExistence(timeout: 5),
                      "shuffle-button must exist in PlayerView")
    }

    // MARK: - Playlist Tests

    /// Verifies the add-files button is accessible.
    func testAddFilesButton_Exists() {
        XCTAssertTrue(app.buttons["add-files-button"].waitForExistence(timeout: 5),
                      "add-files-button must exist in PlaylistView toolbar")
    }
    // MARK: - Slice 6-C: Settings

    /// Opens Settings via the app menu bar.
    ///
    /// Waits for the menu item to exist before clicking to avoid
    /// timing failures caused by menu-open delays.
    private func openSettingsWindow() {
        let harmoniaMenu = app.menuBarItems["HarmoniaPlayer"]
        XCTAssertTrue(harmoniaMenu.waitForExistence(timeout: 5),
                      "HarmoniaPlayer menu bar item must exist")
        harmoniaMenu.click()
        let settingsItem = harmoniaMenu.menus.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 3),
                      "Settings… menu item must appear after clicking menu")
        settingsItem.click()
    }

    func testSettingsWindow_OpensViaMenu() {
        openSettingsWindow()
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5),
                      "Settings window must open via HarmoniaPlayer menu")
    }

    func testAllowDuplicateTracksToggle_ExistsInSettings() {
        openSettingsWindow()
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5),
                      "Precondition: Settings window must open")
        // Use descendants to find the toggle regardless of how macOS renders it
        let toggle = settingsWindow.descendants(matching: .any)["allow-duplicates-toggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "allow-duplicates-toggle must exist in Settings"
        )
    }

}
