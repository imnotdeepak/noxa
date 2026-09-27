import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    // Keep these IDs in one place so they can be changed when the App Store Connect
    // subscription group is created. They are intentionally not used to grant access;
    // StoreKit's verified transactions are the authority.
    static let monthlyProductID = "com.lycheecorp.noxa.monthly"
    static let annualProductID = "com.lycheecorp.noxa.annual"
    static let productIDs = [monthlyProductID, annualProductID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasAccess = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var reviewedAccountIDs: Set<String>
    @Published var message: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let reviewedAccountIDsKey = "reviewedSubscriptionAccountIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reviewedAccountIDs = Set(defaults.stringArray(forKey: Self.reviewedAccountIDsKey) ?? [])
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func canEnterApp(for userID: UUID?) -> Bool {
        guard let userID else { return false }
        return hasAccess && reviewedAccountIDs.contains(userID.uuidString)
    }

    func continueWithCurrentSubscription(for userID: UUID?) {
        guard hasAccess, let userID else { return }
        reviewedAccountIDs.insert(userID.uuidString)
        defaults.set(reviewedAccountIDs.sorted(), forKey: Self.reviewedAccountIDsKey)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let loadedProducts = try await Product.products(for: Self.productIDs)
            products = loadedProducts.sorted { left, right in
                Self.productIDs.firstIndex(of: left.id)! < Self.productIDs.firstIndex(of: right.id)!
            }
            if loadedProducts.isEmpty {
                #if DEBUG
                message = "No subscription products are available yet. Add the matching IDs in App Store Connect or an Xcode StoreKit configuration file."
                #else
                message = "Subscriptions are temporarily unavailable. Please try again later."
                #endif
            } else {
                message = nil
            }
        } catch {
            products = []
            message = "Subscriptions are temporarily unavailable. Check your connection and try again."
        }

        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var isEntitled = false

        for await verificationResult in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            isEntitled = true
        }

        hasAccess = isEntitled
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        purchasingProductID = product.id
        defer {
            purchasingProductID = nil
            isLoading = false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try Self.checkVerified(verificationResult)
                await transaction.finish()
                await refreshEntitlements()
                message = hasAccess ? "Your Noxa subscription is active on this Apple Account." : nil
                return hasAccess

            case .userCancelled:
                message = nil
                return false

            case .pending:
                message = "The purchase is pending approval. Noxa will unlock when Apple confirms it."
                return false

            @unknown default:
                message = "The purchase could not be completed. Please try again."
                return false
            }
        } catch {
            message = "The purchase could not be completed. Please try again."
            return false
        }
    }

    func restorePurchases() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = hasAccess
                ? "Your Noxa subscription has been restored."
                : "No active Noxa subscription was found for this Apple Account."
        } catch {
            message = "Purchases could not be restored right now. Please try again."
        }
    }

    private func observeTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            guard !Task.isCancelled else { return }

            do {
                let transaction = try Self.checkVerified(verificationResult)
                await transaction.finish()
                await refreshEntitlements()
            } catch {
                // An unverified transaction never unlocks access.
                continue
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
