import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UIKit
import os

/// Owns the YouTube app block that goes with hiding Shorts in Safari. The
/// app can't be filtered, so while Shorts are hidden it is blocked and
/// YouTube stays usable as a website, where the Safari filter hides Shorts.
@MainActor
enum YouTubeShortsProtectionService {
    private static let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "youtube-app-block")
    private static let expiryActivity = DeviceActivityName("noxa.youtube.app-block.expiry")
    private static let activityCenter = DeviceActivityCenter()
    private static let appSettings = ManagedSettingsStore(
        named: ManagedSettingsStore.Name("noxa.youtube.app-block")
    )

    /// Lets the block work without the picker. Choosing the app in Apple's
    /// picker still replaces it, in case this ID ever stops matching.
    static let youtubeBundleIdentifier = "com.google.ios.youtube"

    static var isAppBlockApplied: Bool {
        appSettings.application.blockedApplications != nil
    }

    static func shouldApplyAppBlock(
        shortsHidden: Bool,
        isEnabled: Bool,
        allowedUntil: Date?,
        appSelection: FamilyActivitySelection?,
        now: Date = Date()
    ) -> Bool {
        shortsHidden
            && isEnabled
            // No pick yet means the bundle ID; a pick must be exactly one app.
            && (appSelection.map { $0.applicationTokens.count <= 1 } ?? true)
            // Release slightly before entitlement expiry, as Instagram does.
            && (allowedUntil.map { $0 > now.addingTimeInterval(16 * 60) } ?? false)
    }

    /// `x-safari-https` keeps the link in Safari instead of the blocked app.
    static func openInSafari() {
        guard let safariURL = URL(string: "x-safari-https://m.youtube.com/"),
              let webURL = URL(string: "https://m.youtube.com/") else { return }
        UIApplication.shared.open(safariURL) { opened in
            if !opened { UIApplication.shared.open(webURL) }
        }
    }

    static func reconcile(store: AppGroupStore? = nil, now: Date = Date()) {
        let store = store ?? .shared
        let appSelection = (try? store.loadYouTubeAppSelection()) ?? nil
        let applyApp = shouldApplyAppBlock(
            shortsHidden: store.youtubeShortsHidden,
            isEnabled: store.youtubeAppBlockEnabled,
            allowedUntil: store.safariFilterAllowedUntil,
            appSelection: appSelection,
            now: now
        )
        if applyApp, let expiry = store.safariFilterAllowedUntil {
            do {
                try scheduleExpiryRelease(for: expiry)
            } catch {
                // A block without its release wake could outlive paid access.
                appSettings.clearAllSettings()
                logger.error("Could not schedule YouTube release: \(error.localizedDescription, privacy: .public)")
                return
            }
        } else {
            activityCenter.stopMonitoring([expiryActivity])
        }

        if applyApp {
            // Not a shield: iOS shields an app's website with the app, and
            // youtube.com must stay usable in Safari.
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
        return [Application(bundleIdentifier: youtubeBundleIdentifier)]
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
