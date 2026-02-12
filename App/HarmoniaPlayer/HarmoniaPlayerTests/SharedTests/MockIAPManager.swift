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
/// ```
///
/// Note: This is test code only. Real StoreKit implementation will be
/// added to the main target in future slices.
final class MockIAPManager: IAPManager {
    
    // MARK: - IAPManager Protocol
    
    /// Pro unlock status (immutable after initialization)
    let isProUnlocked: Bool
    
    // MARK: - Initialization
    
    /// Creates a mock IAP manager with specified Pro status
    ///
    /// - Parameter isProUnlocked: Whether Pro is unlocked (default: false)
    init(isProUnlocked: Bool = false) {
        self.isProUnlocked = isProUnlocked
    }
}
