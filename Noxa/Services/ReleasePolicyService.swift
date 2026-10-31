import Combine
import Foundation

struct ReleasePolicyPayload: Decodable, Equatable {
    let minimumIOSBuild: Int

    func requiresUpdate(currentBuild: Int) -> Bool {
        minimumIOSBuild > currentBuild
    }
}

/// A remotely raised compatibility floor. A failed check keeps the last
/// verified value, so active local Screen Time commitments never depend on
/// this network request.
@MainActor
final class ReleasePolicyService: ObservableObject {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6808292710")!
    private static let cacheKey = "noxa.minimumIOSBuild"

    @Published private(set) var minimumIOSBuild: Int

    private let defaults: UserDefaults
    private let session: URLSession
    private let endpoint: URL
    private let currentBuild: Int
    private var lastCheckedAt: Date?

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        endpoint: URL = SupabaseProvider.projectURL.appending(path: "functions/v1/release-policy"),
        currentBuild: Int = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    ) {
        self.defaults = defaults
        self.session = session
        self.endpoint = endpoint
        self.currentBuild = currentBuild
        self.minimumIOSBuild = max(0, defaults.integer(forKey: Self.cacheKey))
    }

    var requiresUpdate: Bool {
        ReleasePolicyPayload(minimumIOSBuild: minimumIOSBuild)
            .requiresUpdate(currentBuild: currentBuild)
    }

    func refresh(force: Bool = false) async {
        if !force, let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < 15 * 60 { return }
        lastCheckedAt = Date()

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(SupabaseProvider.publishableKey, forHTTPHeaderField: "apikey")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return }
            let policy = try JSONDecoder().decode(ReleasePolicyPayload.self, from: data)
            guard (0...1_000_000).contains(policy.minimumIOSBuild) else { return }
            minimumIOSBuild = policy.minimumIOSBuild
            defaults.set(policy.minimumIOSBuild, forKey: Self.cacheKey)
        } catch {
            // Offline use remains possible unless a previously checked build
            // floor already requires an update.
        }
    }
}
