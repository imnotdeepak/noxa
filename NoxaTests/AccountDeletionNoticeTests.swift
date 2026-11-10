import Foundation
import Testing
@testable import Noxa

struct AccountDeletionNoticeTests {
    @Test func activeSubscriptionWarnsThatBillingContinues() {
        let message = AccountDeletionNotice.message(hasActiveSubscription: true)
        #expect(message.contains("still be billed"))
        #expect(message.contains("cancel it in Apple settings"))
    }

    @Test func neverClaimsToCancelTheAppStoreSubscription() {
        for active in [true, false] {
            let message = AccountDeletionNotice.message(hasActiveSubscription: active).lowercased()
            #expect(!message.contains("subscription will be cancelled"))
            #expect(!message.contains("cancels your subscription"))
            #expect(message.contains("apple settings"))
        }
    }

    @Test func manageLinkOpensAppleSubscriptions() {
        #expect(AccountDeletionNotice.manageSubscriptionURL.absoluteString == "https://apps.apple.com/account/subscriptions")
    }

    @Test func subscriptionCleanupFailureSaysNothingWasDeleted() {
        let message = AccountDeletionNotice.failureMessage(errorCode: "subscription_cleanup_failed")
        #expect(message.contains("was not deleted"))
        #expect(AccountDeletionNotice.failureMessage(errorCode: nil).contains("could not be deleted"))
    }
}
