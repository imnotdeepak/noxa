import Foundation
import Testing
@testable import Noxa

@MainActor struct ReleasePolicyTests {
    @Test func cachedCompatibilityFloorWorksWithoutNetwork() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ReleasePolicy.\(UUID())"))
        defaults.set(15, forKey: "noxa.minimumIOSBuild")

        #expect(ReleasePolicyService(defaults: defaults, currentBuild: 14).requiresUpdate)
        #expect(!ReleasePolicyService(defaults: defaults, currentBuild: 15).requiresUpdate)
        #expect(!ReleasePolicyService(defaults: defaults, currentBuild: 16).requiresUpdate)
    }
}
