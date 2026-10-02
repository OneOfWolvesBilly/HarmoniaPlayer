//
//  HarmoniaPlayerAppTests.swift
//  HarmoniaPlayerTests
//

import XCTest

/// Tests for `HarmoniaPlayerApp` — the launch-time bootstrap performed by
/// the app entry point.
///
/// The test bundle is hosted in the app, so `HarmoniaPlayerApp.init` has
/// already run in this process when a test executes. The tests read the
/// state that launch left behind.
final class HarmoniaPlayerAppTests: XCTestCase {

    /// The crash-on-exception policy must come from the launch
    /// registration. The registration domain is read directly because
    /// `bool(forKey:)` would also be satisfied by a persisted preference.
    func testLaunch_RegistersCrashOnExceptionsDefault() {
        let registered = UserDefaults.standard
            .volatileDomain(forName: UserDefaults.registrationDomain)

        XCTAssertEqual(
            registered["NSApplicationCrashOnExceptions"] as? Bool,
            true,
            "HarmoniaPlayerApp.init must register NSApplicationCrashOnExceptions = true"
        )
    }
}
