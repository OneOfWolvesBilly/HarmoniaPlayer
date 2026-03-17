//
//  FreeTierIAPManager.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Production `IAPManager` implementation for the Free tier build.
//
//  DESIGN NOTES
//  ------------
//  - This class satisfies the `IAPManager` protocol required by `AppState`.
//  - In the Free build, Pro features are never unlocked; this implementation
//    always returns `false` for `isProUnlocked` without any StoreKit calls.
//  - When the Pro IAP tier is introduced, a `StoreKitIAPManager` will replace
//    this class in the Pro build target while leaving the Free build unchanged.
//

import Foundation

/// Production `IAPManager` for the Free tier.
///
/// Always returns `false` for `isProUnlocked`. No StoreKit integration is
/// performed. Pro features gated by `AppState` will remain unavailable.
final class FreeTierIAPManager: IAPManager {

    /// Always `false`; Pro features are not available in the Free tier.
    var isProUnlocked: Bool { false }
}