import Testing
@testable import Noxa

struct RestrictionStoreMigrationTests {
    @Test @MainActor func activeFocusNeverBecomesAnIndefiniteManualShield() {
        let plan = RestrictionStoreMigration.plan(
            hasActiveFocus: true,
            validationMonitorIsRunning: false
        )
        #expect(!plan.copyLegacyToManual)
        #expect(plan.copyLegacyToFocusFallback)
        #expect(plan.clearLegacy)
    }

    @Test @MainActor func runningValidationMonitorKeepsItsTemporaryShield() {
        let plan = RestrictionStoreMigration.plan(
            hasActiveFocus: false,
            validationMonitorIsRunning: true
        )
        #expect(!plan.copyLegacyToManual)
        #expect(!plan.copyLegacyToFocusFallback)
        #expect(!plan.clearLegacy)
    }

    @Test @MainActor func unownedLegacyShieldRemainsRemovableAsManualShield() {
        let plan = RestrictionStoreMigration.plan(
            hasActiveFocus: false,
            validationMonitorIsRunning: false
        )
        #expect(plan.copyLegacyToManual)
        #expect(!plan.copyLegacyToFocusFallback)
        #expect(plan.clearLegacy)
    }
}
