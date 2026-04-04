//
//  StoreKitIAPManager.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Production `IAPManager` backed by StoreKit 2.
//
//  DESIGN NOTES
//  ------------
//  - `isProUnlocked` is persisted in UserDefaults (`hp.isProUnlocked`) as a
//    fast-read cache so that `AppState` does not need to await an async call
//    during its synchronous init. The cache is refreshed at launch via
//    `refreshEntitlements()`, which is called from `HarmoniaPlayerApp.onAppear`.
//  - `purchasePro()` uses the StoreKit 2 `Product.purchase()` API and verifies
//    the result before setting `isProUnlocked = true`.
//  - `refreshEntitlements()` uses `Transaction.currentEntitlement(for:)` to
//    verify an existing purchase without re-purchasing.
//  - Requires App Store Connect product ID: `harmoniaplayer.pro`.
//
//  THREAD SAFETY
//  -------------
//  All mutations to `isProUnlocked` happen on the calling async context.
//  `isProUnlocked`'s `didSet` writes to UserDefaults synchronously, which is
//  safe from any thread.
//

import Foundation
import StoreKit

/// StoreKit 2-backed `IAPManager` for production builds.
///
/// Manages Pro unlock purchase and entitlement verification.
/// `isProUnlocked` is cached in `UserDefaults` for fast synchronous reads.
final class StoreKitIAPManager: IAPManager {

    // MARK: - Constants

    /// App Store Connect product ID for the Pro one-time purchase.
    static let productID = "harmoniaplayer.pro"

    /// UserDefaults key for persisting the Pro unlock state.
    private static let defaultsKey = "hp.isProUnlocked"

    // MARK: - State

    /// Whether Pro features are currently unlocked.
    ///
    /// Loaded from UserDefaults on init; updated after successful purchase or
    /// entitlement refresh. Persisted to UserDefaults in `didSet`.
    private(set) var isProUnlocked: Bool {
        didSet {
            defaults.set(isProUnlocked, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults

    // MARK: - Initialization

    /// Creates a `StoreKitIAPManager`.
    ///
    /// - Parameter userDefaults: Defaults store for persisting unlock state (default: `.standard`).
    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        // Fast-read cache; refreshed async by refreshEntitlements() at launch.
        self.isProUnlocked = userDefaults.bool(forKey: Self.defaultsKey)
    }

    // MARK: - IAPManager

    /// Verifies the current Pro entitlement with the App Store.
    ///
    /// Updates `isProUnlocked` based on the current transaction state.
    /// Call at app launch (e.g. in `HarmoniaPlayerApp.task`) to refresh stale cache.
    func refreshEntitlements() async {
        // currentEntitlements(for:) replaced currentEntitlement(for:) in macOS 15.4.
        // It returns an AsyncSequence; we take the first verified transaction.
        var foundVerified = false
        for await result in Transaction.currentEntitlements(for: Self.productID) {
            switch result {
            case .verified:
                foundVerified = true
            case .unverified:
                break
            }
        }
        isProUnlocked = foundVerified
    }

    /// Initiates the StoreKit 2 purchase sheet for the Pro product.
    ///
    /// On success, `isProUnlocked` is set to `true` and the transaction is finished.
    /// Throws `IAPError` on cancellation, verification failure, or fetch error.
    func purchasePro() async throws {
        // 1. Fetch the product from App Store Connect.
        let products: [Product]
        do {
            products = try await Product.products(for: [Self.productID])
        } catch {
            throw IAPError.purchaseFailed(error.localizedDescription)
        }

        guard let product = products.first else {
            throw IAPError.productNotFound
        }

        // 2. Present the purchase sheet.
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw IAPError.purchaseFailed(error.localizedDescription)
        }

        // 3. Handle the result.
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                isProUnlocked = true
                await transaction.finish()
            case .unverified:
                throw IAPError.verificationFailed
            }
        case .userCancelled:
            throw IAPError.userCancelled
        case .pending:
            // Ask to Buy or deferred — treated as cancelled from the user's perspective.
            throw IAPError.userCancelled
        @unknown default:
            throw IAPError.purchaseFailed("Unknown purchase result")
        }
    }
}
