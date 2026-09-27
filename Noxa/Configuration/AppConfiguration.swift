import Foundation

enum AppConfiguration {
    static let revenueCatPublicSDKKey = configuredValue(for: "RevenueCatPublicSDKKey")
    static let postHogProjectToken = configuredValue(for: "PostHogProjectToken")
    static let postHogAPIHost = configuredValue(for: "PostHogAPIHost") ?? "https://us.i.posthog.com"

    private static func configuredValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("YOUR_"),
              !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}
