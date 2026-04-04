//
//  MockIAPManager.swift
//  HarmoniaPlayerTests
//
//  Created on 2026-02-11.
//

import Foundation
@testable import HarmoniaPlayer

/// Mock implementation of IAPManager for testing and development
///
/// This implementation provides deterministic Pro/Free status without
/// requiring StoreKit integration.
///
/// Usage:
/// ```swift
/// // Free tier
/// let freeIAP = MockIAPManager()
/// let freeIAP = MockIAPManager(isProUnlocked: false)
///
/// // Pro tier
/// let proIAP = MockIAPManager(isProUnlocked: true)
///
/// // Simulate successful purchase in tests
/// let mock = MockIAPManager(isProUnlocked: false)
/// mock.purchaseResult = .success
/// ```
///
/// Note: This is test code only. Real StoreKit implementation is in StoreKitIAPManager.
final class MockIAPManager: IAPManager {

    // MARK: - Purchase result configuration

    /// Controls what `purchasePro()` does when called in tests.
    enum PurchaseResult {
        /// Purchase succeeds; `isProUnlocked` flips to `true`.
        case success
        /// Purchase throws the given `IAPError`.
        case failure(IAPError)
    }

    // MARK: - IAPManager Protocol

    /// Pro unlock status — mutable so tests can simulate a successful purchase.
    private(set) var isProUnlocked: Bool

    // MARK: - Configurable behavior

    /// What `purchasePro()` will do. Default: `.failure(.notAvailable)`.
    var purchaseResult: PurchaseResult = .failure(.notAvailable)

    // MARK: - Call tracking

    var refreshEntitlementsCallCount = 0
    var purchaseProCallCount = 0

    // MARK: - Initialization

    /// Creates a mock IAP manager with specified Pro status
    ///
    /// - Parameter isProUnlocked: Whether Pro is unlocked (default: false)
    init(isProUnlocked: Bool = false) {
        self.isProUnlocked = isProUnlocked
    }

    // MARK: - IAPManager

    /// Stub: records the call. Does not change `isProUnlocked`.
    func refreshEntitlements() async {
        refreshEntitlementsCallCount += 1
    }

    /// Stub: applies `purchaseResult` — either unlocks Pro or throws.
    func purchasePro() async throws {
        purchaseProCallCount += 1
        switch purchaseResult {
        case .success:
            isProUnlocked = true
        case .failure(let error):
            throw error
        }
    }
}
