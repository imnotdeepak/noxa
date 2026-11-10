import Foundation

/// What Noxa tells people before and after deleting their account. Deleting a
/// Noxa account never cancels an App Store subscription, so the copy says so
/// and points to Apple's subscription settings.
enum AccountDeletionNotice {
    static let title = "Delete your Noxa account?"
    static let manageSubscriptionTitle = "Manage Apple Subscription"
    static let manageSubscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    static func message(hasActiveSubscription: Bool) -> String {
        let deletion = "This permanently deletes your Noxa account and cloud data, and unlinks your subscription from it."
        if hasActiveSubscription {
            return deletion + " Your App Store subscription stays active and you will still be billed until you cancel it in Apple settings."
        }
        return deletion + " Deleting your account does not cancel an App Store subscription; cancel it in Apple settings."
    }

    /// Maps the delete-account function's error code to a message. Every
    /// failure here means nothing was deleted, so trying again is safe.
    static func failureMessage(errorCode: String?) -> String {
        switch errorCode {
        case "subscription_cleanup_failed", "subscription_cleanup_unavailable":
            return "Your account was not deleted because its subscription record could not be removed. Please try again in a moment."
        default:
            return "Your account could not be deleted right now. Please try again."
        }
    }
}
