//
//  IAPManager.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-11.
//

import Foundation

/// Abstraction for In-App Purchase management
///
/// This protocol provides a minimal interface for determining Pro unlock status.
/// Platform-specific implementations (StoreKit on macOS/iOS) will be added later.
///
/// For development and testing, use `MockIAPManager` from the test target.
protocol IAPManager {
    /// Whether Pro features are unlocked
    ///
    /// - Returns: `true` if user has purchased Pro, `false` for Free tier
    var isProUnlocked: Bool { get }
}
