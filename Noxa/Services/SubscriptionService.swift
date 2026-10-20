import Combine
import Foundation
import RevenueCat

struct SubscriptionPlan: Identifiable {
    let package: Package

    var id: String { package.storeProduct.productIdentifier }
    var title: String { package.storeProduct.localizedTitle }
    var displayPrice: String { package.storeProduct.localizedPriceString }
    var isAnnual: Bool { id == SubscriptionService.annualProductID }

    var periodDescription: String {
        if id == SubscriptionService.monthlyProductID { return "Billed monthly" }
        if id == SubscriptionService.annualProductID { return "Billed annually" }
        return "Auto-renewing subscription"
    }
}

@MainActor
final class SubscriptionService: NSObject, ObservableObject {
    static let monthlyProductID = "com.lycheecorp.noxa.monthly"
    static let annualProductID = "com.lycheecorp.noxa.annual"
    static let productIDs = [monthlyProductID, annualProductID]
    static let entitlementID = "noxa_focus_app_blocker_pro"

    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var hasAccess = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var boundUserID: UUID?
    @Published var message: String?

    private let defaults: UserDefaults
    private var isConfigured = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func canEnterApp(for userID: UUID?) -> Bool {
        guard let userID else { return false }
        return hasLoaded && hasAccess && boundUserID == userID
    }

    var activePlanDisplayName: String {
        switch activeProductID {
        case Self.monthlyProductID:
            return "Noxa Monthly"
        case Self.annualProductID:
            return "Noxa Annual"
        default:
            return "Noxa Subscription"
        }
    }

    func bind(to userID: UUID) async {
        guard boundUserID != userID || !hasLoaded else {
            await refreshEntitlements()
            return
        }

        hasLoaded = false
        hasAccess = false
        AppGroupStore.shared.setSafariFilterAllowedUntil(nil)
        activeProductID = nil
        plans = []
        message = nil
        boundUserID = userID

        guard let apiKey = AppConfiguration.revenueCatPublicSDKKey else {
            hasLoaded = true
            #if DEBUG
            message = "RevenueCat is not configured. Add its public iOS SDK key to Info.plist."
            #else
            message = "Subscriptions are temporarily unavailable. Please try again later."
            #endif
            return
        }

        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let accountID = userID.uuidString.lowercased()
            let customerInfo: CustomerInfo

            if !isConfigured {
                Purchases.configure(withAPIKey: apiKey, appUserID: accountID)
                Purchases.shared.delegate = self
                isConfigured = true
                customerInfo = try await Purchases.shared.customerInfo()
            } else if Purchases.shared.appUserID != accountID {
                customerInfo = try await Purchases.shared.logIn(accountID).customerInfo
            } else {
                customerInfo = try await Purchases.shared.customerInfo()
            }

            Purchases.shared.attribution.setAttributes(["$posthogUserId": accountID])
            apply(customerInfo)

            if !defaults.bool(forKey: migrationKey(for: userID)) {
                let synchronizedInfo = try await Purchases.shared.syncPurchases()
                apply(synchronizedInfo)
                defaults.set(true, forKey: migrationKey(for: userID))
            }

            try await loadOfferings()
        } catch {
            guard boundUserID == userID else { return }
            message = userMessage(for: error)
        }
    }

    func unbind() async {
        boundUserID = nil
        hasAccess = false
        AppGroupStore.shared.setSafariFilterAllowedUntil(nil)
        activeProductID = nil
        hasLoaded = false
        plans = []
        purchasingProductID = nil
        message = nil

        guard isConfigured, !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }

    func load() async {
        guard let boundUserID else { return }
        await bind(to: boundUserID)
    }

    func refreshEntitlements() async {
        guard isConfigured, let expectedUserID = boundUserID else { return }
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            guard boundUserID == expectedUserID else { return }
            apply(customerInfo)
            if plans.isEmpty {
                try await loadOfferings()
            }
        } catch {
            guard boundUserID == expectedUserID else { return }
            message = userMessage(for: error)
        }
    }

    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async -> Bool {
        guard isConfigured, !isLoading, boundUserID != nil else { return false }
        isLoading = true
        purchasingProductID = plan.id
        message = nil
        AnalyticsService.shared.capture(.purchaseStarted(productID: plan.id))
        defer {
            purchasingProductID = nil
            isLoading = false
        }

        do {
            let result = try await Purchases.shared.purchase(package: plan.package)
            apply(result.customerInfo)
            if result.userCancelled {
                AnalyticsService.shared.capture(.purchaseCancelled(productID: plan.id))
                return false
            }
            if hasAccess {
                AnalyticsService.shared.capture(.purchaseCompleted(productID: plan.id))
                message = "Your Noxa subscription is active."
            }
            return hasAccess
        } catch {
            message = userMessage(for: error)
            return false
        }
    }

    func restorePurchases() async {
        guard isConfigured, !isLoading, boundUserID != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            apply(customerInfo)
            message = hasAccess
                ? "Your Noxa subscription has been restored."
                : "No active Noxa subscription was found for this account."
        } catch {
            message = userMessage(for: error)
        }
    }

    private func loadOfferings() async throws {
        let offerings = try await Purchases.shared.offerings()
        let offering = offerings.current ?? offerings.all.values.first
        let availablePlans = offering?.availablePackages
            .filter { Self.productIDs.contains($0.storeProduct.productIdentifier) }
            .map(SubscriptionPlan.init(package:)) ?? []
        plans = availablePlans.sorted {
            (Self.productIDs.firstIndex(of: $0.id) ?? .max)
                < (Self.productIDs.firstIndex(of: $1.id) ?? .max)
        }
        if plans.isEmpty {
            #if DEBUG
            message = "No RevenueCat offering contains Noxa's monthly and annual products."
            #else
            message = "Subscriptions are temporarily unavailable. Please try again later."
            #endif
        }
    }

    private func apply(_ customerInfo: CustomerInfo) {
        let activeEntitlement = customerInfo.entitlements.active[Self.entitlementID]
        hasAccess = activeEntitlement != nil
        AppGroupStore.shared.setSafariFilterAllowedUntil(activeEntitlement?.expirationDate)
        activeProductID = activeEntitlement?.productIdentifier
        if hasAccess, message?.contains("unavailable") == true {
            message = nil
        }
    }

    private func migrationKey(for userID: UUID) -> String {
        "revenueCatStoreKitMigration.v1.\(userID.uuidString.lowercased())"
    }

    private func userMessage(for error: Error) -> String {
        let code = ErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .receiptAlreadyInUseError:
            return "This App Store subscription is already linked to another Noxa account. Sign in to that account or contact support."
        case .productAlreadyPurchasedError:
            return "This subscription has already been purchased. Try Restore Purchases."
        case .networkError, .offlineConnectionError:
            return "Subscriptions could not be reached. Check your connection and try again."
        default:
            return "The subscription request could not be completed. Please try again."
        }
    }
}

extension SubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.apply(customerInfo)
        }
    }
}
