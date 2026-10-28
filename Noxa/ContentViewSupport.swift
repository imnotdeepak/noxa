import FamilyControls
import SafariServices
import SwiftUI
import UIKit

struct NoxaDurationButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaTheme.font(15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(isSelected ? .black : NoxaTheme.primaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                isSelected ? NoxaTheme.accent : NoxaTheme.elevated,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? NoxaTheme.accent : NoxaTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .noxaAnimation(NoxaMotion.snappy, value: configuration.isPressed)
            .noxaAnimation(NoxaMotion.snappy, value: isSelected)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed { NoxaHaptics.selection() }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension FamilyControlsAuthorizationService {
    var statusDescription: String {
        switch state {
        case .unknown:
            return "Checking Screen Time access."
        case .notDetermined:
            return "Noxa needs Screen Time access before it can block distractions."
        case .denied:
            return "Access is denied. Re-enable it in Settings to use blocking."
        case .approved, .approvedWithDataAccess:
            return "Screen Time access is ready."
        }
    }
}

extension ScreenTimeAuthorizationState {
    var isApproved: Bool {
        self == .approved || self == .approvedWithDataAccess
    }
}

extension FamilyActivitySelection {
    func removing(_ existingSelection: FamilyActivitySelection) -> FamilyActivitySelection {
        var result = self
        result.applicationTokens.subtract(existingSelection.applicationTokens)
        result.categoryTokens.subtract(existingSelection.categoryTokens)
        result.webDomainTokens.subtract(existingSelection.webDomainTokens)
        return result
    }
}

extension SessionOutcome {
    var displayName: String {
        switch self {
        case .completed:
            return "Completed"
        case .endedEarly:
            return "Ended early"
        case .recoveredStale:
            return "Recovered after restart"
        case .failedToStart:
            return "Failed to start"
        case .interrupted:
            return "Interrupted"
        case .startPending:
            return "Starting"
        case .active:
            return "Active"
        }
    }
}

extension CloudSyncStatus {
    var title: String {
        switch self {
        case .idle:
            return "Cloud sync is ready"
        case .syncing:
            return "Syncing your Noxa data…"
        case .synced:
            return "Cloud sync is up to date"
        case .pending:
            return "Cloud sync is pending"
        case .failed:
            return "Cloud sync will retry"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .synced:
            return "checkmark.icloud"
        case .pending:
            return "clock.badge.checkmark"
        case .failed:
            return "exclamationmark.icloud"
        }
    }
}

extension CloudSyncService {
    var historyStatusDescription: String {
        switch status {
        case .synced:
            return "History is stored locally and synced securely to your Noxa account."
        case .syncing:
            return "History is stored locally and is syncing securely to your Noxa account."
        case .pending, .failed:
            return "History is safe on this device. Cloud sync will retry when you’re back online."
        case .idle:
            return "History is stored locally first and syncs securely after you sign in."
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService())
        .environmentObject(AnalyticsService.shared)
        .environmentObject(SubscriptionService())
        .environmentObject(FocusSessionService())
        .environmentObject(ScreenTimeRestrictionService())
        .environmentObject(DeviceActivityMonitoringService())
        .environmentObject(DailyLimitService())
        .environmentObject(RestrictionScheduleService())
        .environmentObject(WebsiteBlocklistService())
        .environmentObject(CloudSyncService())
        .environmentObject(FocusNotificationService())
        .environmentObject(OnboardingService())
        .environmentObject(FocusLaunchRouter())
}
