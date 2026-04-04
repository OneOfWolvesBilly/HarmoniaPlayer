//
//  IAPManager.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-11.
//

import Foundation

// MARK: - IAPError

/// Errors that can be thrown by IAP operations.
enum IAPError: Error, Equatable {
    /// The product could not be fetched from App Store Connect.
    case productNotFound
    /// The purchase result could not be verified by StoreKit.
    case verificationFailed
    /// The user cancelled the purchase sheet.
    case userCancelled
    /// The purchase failed for an underlying reason.
    case purchaseFailed(String)
    /// IAP is not available (e.g. Free tier stub).
    case notAvailable
}

// MARK: - IAPManager

/// Abstraction for In-App Purchase management
///
/// This protocol provides a minimal interface for determining Pro unlock status
/// and performing purchase / restore operations.
///
/// For development and testing, use `MockIAPManager` from the test target.
protocol IAPManager: AnyObject {
    /// Whether Pro features are unlocked
    ///
    /// - Returns: `true` if user has purchased Pro, `false` for Free tier
    var isProUnlocked: Bool { get }

    /// Refreshes entitlements from the App Store.
    ///
    /// Call at app launch to verify existing purchases.
    /// On completion, `isProUnlocked` reflects the current entitlement state.
    func refreshEntitlements() async

    /// Initiates the Pro purchase flow.
    ///
    /// Throws `IAPError` on failure or cancellation.
    /// On success, `isProUnlocked` is set to `true`.
    func purchasePro() async throws
}
