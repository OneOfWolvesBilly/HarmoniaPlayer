//
//  SettingsStore.swift
//  HarmoniaPlayer / Shared / Models
//

import Foundation

/// Store owning the user settings, the Free/Pro tier state, and the UI
/// string bundle.
///
/// Extracted from `AppState`. Views whose body reads settings state observe
/// this store directly via `@Environment(SettingsStore.self)`.
///
/// The store persists its own `UserDefaults` keys on change and never
/// references another store: a ReplayGain mode change and a paywall
/// request leave the store only through the `onReplayGainModeChanged` /
/// `onPaywallRequested` closures, which the composition root wires.
@MainActor @Observable
final class SettingsStore {

    // MARK: - Persistence Keys

    private enum PersistenceKey {
        static let allowDuplicates  = "hp.allowDuplicateTracks"
        static let selectedLanguage = "hp.selectedLanguage"
        static let replayGainMode   = "hp.replayGainMode"
    }

    // MARK: - Persisted Settings

    /// Whether duplicate URLs are allowed in the playlist.
    ///
    /// Default: `false` — duplicates are skipped and reported via the alert
    /// store's `skippedDuplicateURLs`. Persisted on change.
    var allowDuplicateTracks = false {
        didSet {
            userDefaults.set(allowDuplicateTracks, forKey: PersistenceKey.allowDuplicates)
        }
    }

    /// BCP-47 language tag for the UI language override, or `"system"` to
    /// follow the system locale.
    ///
    /// Default: `"system"`. Persisted on change. A change takes effect after
    /// relaunch, keeping UI strings and system menus in sync.
    var selectedLanguage = "system" {
        didSet {
            userDefaults.set(selectedLanguage, forKey: PersistenceKey.selectedLanguage)
        }
    }

    /// Current ReplayGain application mode.
    ///
    /// Default: `.off`. Persisted on change, then reported through
    /// `onReplayGainModeChanged` so the effective playback volume can be
    /// re-applied without restarting the track.
    var replayGainMode: ReplayGainMode = .off {
        didSet {
            userDefaults.set(replayGainMode.rawValue, forKey: PersistenceKey.replayGainMode)
            onReplayGainModeChanged?(replayGainMode)
        }
    }

    // MARK: - UI Preferences

    /// UI layout and visibility preferences. Not persisted.
    ///
    /// Initialised to `.defaultPreferences` at app launch.
    var viewPreferences: ViewPreferences = .defaultPreferences

    // MARK: - Tier State

    /// Whether Pro features are unlocked.
    ///
    /// Read from the IAP manager at init and after every purchase or
    /// entitlement refresh.
    private(set) var isProUnlocked: Bool

    /// Feature flags derived from the IAP manager; tracks `isProUnlocked`.
    private(set) var featureFlags: CoreFeatureFlags

    // MARK: - Localization

    /// The `Bundle` used for all `NSLocalizedString(bundle:)` calls.
    ///
    /// Fixed at launch from the persisted `hp.selectedLanguage` value so that
    /// UI strings and system menus (which also require a restart) change
    /// together. Not recomputed when `selectedLanguage` changes.
    let languageBundle: Bundle

    // MARK: - Notifications

    /// Called after `replayGainMode` changes, with the new mode.
    /// Wired by the composition root; restore at init does not call it.
    @ObservationIgnored var onReplayGainModeChanged: ((ReplayGainMode) -> Void)?

    /// Called when `showPaywallIfNeeded()` finds the Free tier.
    /// Wired by the composition root to the paywall presentation.
    @ObservationIgnored var onPaywallRequested: (() -> Void)?

    // MARK: - Dependencies

    /// IAP manager (determines Free/Pro).
    private let iapManager: IAPManager

    /// UserDefaults store holding the settings keys.
    private let userDefaults: UserDefaults

    // MARK: - Initialization

    /// Creates the store, reading the tier from `iapManager` and restoring
    /// the persisted settings from `userDefaults`.
    ///
    /// Restore neither re-persists nor notifies: the persisted settings are
    /// assigned while `self` is still being initialised, which the
    /// `@Observable` macro routes through the init accessors instead of the
    /// setters, so the `didSet` observers do not run. Keep the restore
    /// assignments ahead of the stored properties that have no default.
    init(iapManager: IAPManager, userDefaults: UserDefaults) {
        if userDefaults.object(forKey: PersistenceKey.allowDuplicates) != nil {
            self.allowDuplicateTracks = userDefaults.bool(forKey: PersistenceKey.allowDuplicates)
        }
        if let lang = userDefaults.string(forKey: PersistenceKey.selectedLanguage) {
            self.selectedLanguage = lang
        }
        if let raw = userDefaults.string(forKey: PersistenceKey.replayGainMode),
           let mode = ReplayGainMode(rawValue: raw) {
            self.replayGainMode = mode
        }

        // Resolve the string bundle from the persisted language, fixed for
        // the process lifetime. A never-written key resolves English.
        let persistedLang = userDefaults.string(forKey: PersistenceKey.selectedLanguage) ?? "en"
        if persistedLang != "system",
           let path = Bundle.main.path(forResource: persistedLang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.languageBundle = bundle
        } else {
            self.languageBundle = .main
        }

        self.isProUnlocked = iapManager.isProUnlocked
        self.featureFlags = CoreFeatureFlags(iapManager: iapManager)

        self.iapManager = iapManager
        self.userDefaults = userDefaults
    }

    // MARK: - IAP

    /// Initiates the Pro purchase flow via the IAP manager.
    ///
    /// On success, `isProUnlocked` and `featureFlags` are refreshed from the
    /// IAP manager. Throws `IAPError` on failure or user cancellation.
    func purchasePro() async throws {
        try await iapManager.purchasePro()
        refreshTierState()
    }

    /// Refreshes Pro entitlements from the App Store via the IAP manager,
    /// then updates `isProUnlocked` and `featureFlags`.
    func refreshEntitlements() async {
        await iapManager.refreshEntitlements()
        refreshTierState()
    }

    // MARK: - Paywall

    /// Requests the Pro paywall if the user is on the Free tier.
    ///
    /// Calls `onPaywallRequested` and returns `true` when
    /// `isProUnlocked == false`. Returns `false` (and requests nothing) when
    /// Pro is already unlocked.
    ///
    /// Call this guard before any Pro-only action:
    /// ```swift
    /// guard !showPaywallIfNeeded() else { return }
    /// // proceed with Pro action
    /// ```
    @discardableResult
    func showPaywallIfNeeded() -> Bool {
        guard !isProUnlocked else { return false }
        onPaywallRequested?()
        return true
    }

    // MARK: - Private

    private func refreshTierState() {
        isProUnlocked = iapManager.isProUnlocked
        featureFlags = CoreFeatureFlags(iapManager: iapManager)
    }

    // WORKAROUND: Xcode 26 beta — swift::TaskLocal::StopLookupScope crash on deinit.
    // Required on all @MainActor classes that are deallocated in test contexts.
    // Remove when Xcode 26 stable is released.
    nonisolated deinit {}
}
