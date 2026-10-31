import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UIKit
import os

/// Owns Instagram's separate website and native-app restrictions.
@MainActor
enum InstagramSiteProtectionService {
    private static let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "instagram-app-block")
    private static let expiryActivity = DeviceActivityName("noxa.instagram.app-block.expiry")
    private static let activityCenter = DeviceActivityCenter()
    /// Left over from the removed Full Block mode; cleared on every reconcile.
    private static let legacyFullBlockSettings = ManagedSettingsStore(
        named: ManagedSettingsStore.Name("noxa.instagram.full-block")
    )
    private static let appSettings = ManagedSettingsStore(
        named: ManagedSettingsStore.Name("noxa.instagram.app-block")
    )

    /// Lets the block work without the picker; a pick replaces it.
    static let instagramBundleIdentifier = "com.burbn.instagram"

    static var isAppBlockApplied: Bool {
        appSettings.shield.applications != nil
            || appSettings.application.blockedApplications != nil
    }

    /// The native-app block is a separate choice from Safari filtering.
    static func shouldApplyAppBlock(
        mode: InstagramSiteMode,
        isEnabled: Bool,
        allowedUntil: Date?,
        appSelection: FamilyActivitySelection?,
        now: Date = Date()
    ) -> Bool {
        mode == .distractionFree
            && isEnabled
            // No pick yet means the bundle ID; a pick must be exactly one app.
            && (appSelection.map { $0.applicationTokens.count <= 1 } ?? true)
            // Release slightly before entitlement expiry, including when its
            // Device Activity callback lands on a whole-minute boundary.
            && (allowedUntil.map { $0 > now.addingTimeInterval(16 * 60) } ?? false)
    }

    /// `x-safari-https` asks iOS to use Safari rather than hand instagram.com
    /// to the blocked app. Fall back to the plain link if iOS rejects it.
    static func openInSafari() {
        guard let safariURL = URL(string: "x-safari-https://www.instagram.com/"),
              let webURL = URL(string: "https://www.instagram.com/") else { return }
        UIApplication.shared.open(safariURL) { opened in
            if !opened { UIApplication.shared.open(webURL) }
        }
    }

    static func reconcile(store: AppGroupStore? = nil, now: Date = Date()) {
        let store = store ?? .shared
        let appSelection = (try? store.loadInstagramAppSelection()) ?? nil
        let applyApp = shouldApplyAppBlock(
            mode: store.instagramSiteMode,
            isEnabled: store.instagramAppBlockEnabled,
            allowedUntil: store.safariFilterAllowedUntil,
            appSelection: appSelection,
            now: now
        )
        legacyFullBlockSettings.clearAllSettings()
        if applyApp, let expiry = store.safariFilterAllowedUntil {
            do {
                try scheduleExpiryRelease(for: expiry)
            } catch {
                // A block without its release wake could outlive paid access.
                appSettings.clearAllSettings()
                logger.error("Could not schedule Instagram release: \(error.localizedDescription, privacy: .public)")
                return
            }
        } else {
            activityCenter.stopMonitoring([expiryActivity])
        }

        if applyApp {
            // Not a shield: iOS shields an app's website with the app, and
            // this mode must keep instagram.com usable in Safari.
            appSettings.shield.applications = nil
            appSettings.application.blockedApplications = blockedApps(for: appSelection)
        } else {
            appSettings.clearAllSettings()
        }
    }

    static func blockedApps(for selection: FamilyActivitySelection?) -> Set<Application> {
        if let token = selection?.applicationTokens.first {
            return [Application(token: token)]
        }
        return [Application(bundleIdentifier: instagramBundleIdentifier)]
    }

    private static func scheduleExpiryRelease(for expiry: Date) throws {
        let calendar = Calendar.autoupdatingCurrent
        let roundedExpiry = calendar.dateInterval(of: .minute, for: expiry)?.start ?? expiry
        let releaseAt = roundedExpiry.addingTimeInterval(-15 * 60)
        let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute]
        try activityCenter.startMonitoring(
            expiryActivity,
            during: DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: releaseAt),
                intervalEnd: calendar.dateComponents(components, from: roundedExpiry),
                repeats: false
            )
        )
    }
}
