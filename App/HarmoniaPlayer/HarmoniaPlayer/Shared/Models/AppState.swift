//
//  AppState.swift
//  HarmoniaPlayer
//
//  Created on 2026-02-15.
//

import Foundation
import Combine

/// Application state container (composition root)
///
/// **Responsibilities:**
/// - Wire all dependencies (IAP → Flags → Factory → Services)
/// - Expose minimal published state for UI
/// - **No behavior** - wiring only
///
/// **Design:**
/// - Single source of truth for app-wide state
/// - Uses dependency injection via initializer
/// - All services created through CoreFactory
///
/// **Usage:**
/// ```swift
/// let iapManager = MockIAPManager(isProUnlocked: false)
/// let appState = AppState(iapManager: iapManager)
///
/// // In SwiftUI
/// ContentView()
///     .environmentObject(appState)
/// ```
@MainActor
final class AppState: ObservableObject {
    
    // MARK: - Dependencies
    
    /// IAP manager (determines Free/Pro)
    private let iapManager: IAPManager
    
    /// Feature flags (derived from IAP)
    let featureFlags: CoreFeatureFlags
    
    // MARK: - Services
    
    /// Playback service (placeholder in Slice 1)
    let playbackService: PlaybackService
    
    /// Tag reader service (placeholder in Slice 1)
    let tagReaderService: TagReaderService
    
    // MARK: - Published State
    
    /// Whether Pro features are unlocked
    ///
    /// Derived from feature flags. UI can observe this for Pro gating.
    @Published private(set) var isProUnlocked: Bool
    
    // MARK: - Lifecycle
    
    // MARK: - Initialization
    
    /// Initialize AppState with dependencies
    ///
    /// - Parameters:
    ///   - iapManager: IAP manager
    ///   - provider: Service provider
    ///
    /// **Wiring flow:**
    /// ```
    /// IAPManager
    ///     ↓
    /// CoreFeatureFlags (derived)
    ///     ↓
    /// CoreFactory (with flags)
    ///     ↓
    /// Services (created via factory)
    /// ```
    init(
        iapManager: IAPManager,
        provider: CoreServiceProviding
    ) {
        // Step 1: Store IAP manager
        self.iapManager = iapManager
        
        // Step 2: Derive feature flags from IAP
        self.featureFlags = CoreFeatureFlags(iapManager: iapManager)
        
        // Step 3: Create factory with flags
        let coreFactory = CoreFactory(
            featureFlags: featureFlags,
            provider: provider
        )
        
        // Step 4: Create services via factory
        self.playbackService = coreFactory.makePlaybackService()
        self.tagReaderService = coreFactory.makeTagReaderService()
        
        // Step 5: Expose Pro unlock state
        self.isProUnlocked = iapManager.isProUnlocked
    }
    
    // WORKAROUND: Xcode 26 beta - swift::TaskLocal::StopLookupScope bug
    // Remove when Xcode 26 stable is released
    nonisolated deinit {}
}
