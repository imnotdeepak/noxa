//
//  CloudSyncService.swift
//  Noxa
//

import Combine
import Foundation
import Supabase

/// The local status of the asynchronous cloud mirror. Local enforcement never
/// depends on this status being `.synced`.
enum CloudSyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case synced
    case pending
    case failed
}

/// Durable retry and ownership metadata. Product data is cached separately for
/// each account so changing accounts cannot upload the previous user's data.
struct CloudSyncState: Codable, Equatable, Sendable {
    var userID: UUID? = nil
    var pending = false
    var lastAttemptAt: Date?
    var lastSuccessfulSyncAt: Date?
    var lastError: String?
}

/// Locally cached cloud-supported data for one Supabase account. Screen Time
/// tokens and active enforcement state are deliberately excluded.
struct CloudAccountCache: Codable, Equatable, Sendable {
    var websiteDomains: [String] = []
    var focusHistory: [ActiveSessionRecord] = []
    var lastSyncedWebsiteDomains: [String]?
}

struct CloudSyncMergeResult: Equatable, Sendable {
    let websiteDomains: [String]
    let focusHistory: [ActiveSessionRecord]
}

protocol CloudSyncStoring {
    func loadCloudSyncState() throws -> CloudSyncState?
    func saveCloudSyncState(_ state: CloudSyncState) throws
    func loadCloudAccountCache(userID: UUID) throws -> CloudAccountCache?
    func saveCloudAccountCache(_ cache: CloudAccountCache, userID: UUID) throws
}

extension AppGroupStore: CloudSyncStoring {}

struct CloudProfileRow: Codable, Equatable, Sendable {
    let id: UUID
    let email: String?
    let platform: String
}

struct CloudWebsiteBlocklistRow: Codable, Equatable, Sendable {
    let userID: UUID
    let domain: String

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case domain
    }
}

struct CloudFocusSessionRow: Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let platform: String
    let startTime: String
    let plannedDurationSeconds: Int
    let actualDurationSeconds: Int
    let outcome: SessionOutcome
    let completedSuccessfully: Bool
    let appsBlockedCount: Int?
    let websitesBlockedCount: Int?
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case platform
        case startTime = "start_time"
        case plannedDurationSeconds = "planned_duration_seconds"
        case actualDurationSeconds = "actual_duration_seconds"
        case outcome
        case completedSuccessfully = "completed_successfully"
        case appsBlockedCount = "apps_blocked_count"
        case websitesBlockedCount = "websites_blocked_count"
        case createdAt = "created_at"
    }

    init(userID: UUID, record: ActiveSessionRecord) {
        self.id = record.id
        self.userID = userID
        self.platform = "ios"
        self.startTime = Self.timestamp(record.startedAt)
        self.plannedDurationSeconds = max(0, record.plannedDurationSeconds)
        self.actualDurationSeconds = max(
            0,
            record.actualDurationSeconds ??
                ([.completed, .recoveredStale].contains(record.outcome)
                    ? record.plannedDurationSeconds
                    : 0)
        )
        self.outcome = record.outcome
        self.completedSuccessfully = [.completed, .recoveredStale].contains(record.outcome)
        self.appsBlockedCount = nil
        self.websitesBlockedCount = nil
        self.createdAt = Self.timestamp(record.startedAt)
    }

    func localRecord() -> ActiveSessionRecord? {
        guard let startedAt = Self.date(from: startTime) else { return nil }
        return ActiveSessionRecord(
            id: id,
            startedAt: startedAt,
            plannedEndAt: startedAt.addingTimeInterval(TimeInterval(plannedDurationSeconds)),
            plannedDurationSeconds: plannedDurationSeconds,
            outcome: outcome,
            actualDurationSeconds: actualDurationSeconds
        )
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct WebsiteBlocklistSyncParameters: Encodable {
    let domains: [String]
}

private struct CloudSyncRequest: Sendable {
    let history: [ActiveSessionRecord]
    let websiteDomains: [String]
}

/// Synchronizes ordinary product data without uploading Apple-managed Screen
/// Time tokens. Website reconciliation is a three-way merge, while focus
/// sessions use their stable local UUIDs.
@MainActor
final class CloudSyncService: ObservableObject {
    @Published private(set) var status: CloudSyncStatus
    @Published private(set) var lastSuccessfulSyncAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var boundUserID: UUID?

    private let client: SupabaseClient
    private let store: any CloudSyncStoring
    private var isSyncing = false
    private var queuedRequest: CloudSyncRequest?
    /// Incremented whenever the authenticated account or local cloud state is
    /// invalidated. In-flight requests capture this value and must not publish
    /// or persist results after it changes.
    private var syncGeneration = 0

    init(client: SupabaseClient? = nil, store: (any CloudSyncStoring)? = nil) {
        self.client = client ?? SupabaseProvider.client
        self.store = store ?? AppGroupStore.shared

        let state = (try? self.store.loadCloudSyncState()) ?? nil
        self.boundUserID = state?.userID
        self.lastSuccessfulSyncAt = state?.lastSuccessfulSyncAt
        self.errorMessage = state?.lastError
        if state?.pending == true {
            self.status = .pending
        } else if state?.lastSuccessfulSyncAt != nil {
            self.status = .synced
        } else {
            self.status = .idle
        }
    }

    var hasPendingWork: Bool {
        status == .pending || status == .failed
    }

    /// Associates the in-memory services with the authenticated account before
    /// any network request. Existing local data is migrated to the first user;
    /// later account switches load that account's isolated cache.
    func prepareLocalData(
        for userID: UUID,
        history: [ActiveSessionRecord],
        websiteDomains: [String]
    ) -> CloudSyncMergeResult {
        var state = (try? store.loadCloudSyncState()) ?? CloudSyncState()

        if state.userID == nil {
            state.userID = userID
            boundUserID = userID
            persist(state)
            if let existingCache = try? store.loadCloudAccountCache(userID: userID) {
                return CloudSyncMergeResult(
                    websiteDomains: existingCache.websiteDomains,
                    focusHistory: existingCache.focusHistory
                )
            }
            let result = CloudSyncMergeResult(
                websiteDomains: Self.normalizedDomains(websiteDomains),
                focusHistory: Self.normalizedHistory(history)
            )
            saveCache(
                CloudAccountCache(
                    websiteDomains: result.websiteDomains,
                    focusHistory: result.focusHistory,
                    lastSyncedWebsiteDomains: nil
                ),
                userID: userID
            )
            return result
        }

        guard state.userID != userID else {
            var cache = loadCache(userID: userID)
            cache.websiteDomains = Self.normalizedDomains(websiteDomains)
            cache.focusHistory = Self.normalizedHistory(history)
            saveCache(cache, userID: userID)
            return CloudSyncMergeResult(
                websiteDomains: cache.websiteDomains,
                focusHistory: cache.focusHistory
            )
        }

        if let previousUserID = state.userID {
            var previousCache = loadCache(userID: previousUserID)
            previousCache.websiteDomains = Self.normalizedDomains(websiteDomains)
            previousCache.focusHistory = Self.normalizedHistory(history)
            saveCache(previousCache, userID: previousUserID)
        }

        let nextCache = loadCache(userID: userID)
        state.userID = userID
        state.pending = true
        state.lastAttemptAt = nil
        state.lastSuccessfulSyncAt = nil
        state.lastError = nil
        boundUserID = userID
        status = .pending
        lastSuccessfulSyncAt = nil
        errorMessage = nil
        persist(state)
        return CloudSyncMergeResult(
            websiteDomains: nextCache.websiteDomains,
            focusHistory: nextCache.focusHistory
        )
    }

    /// Coalesces overlapping requests and performs a second pass with the most
    /// recent payload before reporting the cloud mirror as current.
    func sync(
        history: [ActiveSessionRecord],
        websiteDomains: [String]
    ) async -> CloudSyncMergeResult? {
        let request = CloudSyncRequest(history: history, websiteDomains: websiteDomains)
        if isSyncing {
            queuedRequest = request
            return nil
        }

        isSyncing = true
        defer { isSyncing = false }
        var currentRequest = request
        var latestResult: CloudSyncMergeResult?

        while true {
            queuedRequest = nil
            let requestGeneration = syncGeneration
            if let result = await performSync(currentRequest) {
                latestResult = result
            } else if requestGeneration != syncGeneration {
                // A result from an earlier pass belongs to an account/state
                // that was invalidated while this pass was suspended. Do not
                // return that stale result to a caller that might hydrate it.
                latestResult = nil
            }
            guard let nextRequest = queuedRequest else {
                return latestResult
            }
            currentRequest = nextRequest
            status = .syncing
        }
    }

    func clearState() {
        invalidatePendingWork()
        persist(CloudSyncState())
        boundUserID = nil
        status = .idle
        lastSuccessfulSyncAt = nil
        errorMessage = nil
    }

    /// Invalidates an in-flight sync without deleting account caches. This is
    /// used on sign-out/account changes; account deletion calls `clearState()`
    /// afterwards to remove the durable metadata and caches.
    func invalidatePendingWork() {
        syncGeneration &+= 1
        queuedRequest = nil
        errorMessage = nil
    }

    static func mergedDomains(
        base: [String]?,
        local: [String],
        remote: [String]
    ) -> [String] {
        let localSet = Set(normalizedDomains(local))
        let remoteSet = Set(normalizedDomains(remote))
        guard let base else {
            return Array(localSet.union(remoteSet)).sorted()
        }

        let baseSet = Set(normalizedDomains(base))
        let localDeletions = baseSet.subtracting(localSet)
        let remoteDeletions = baseSet.subtracting(remoteSet)
        let additions = localSet.subtracting(baseSet).union(remoteSet.subtracting(baseSet))
        return Array(
            baseSet
                .subtracting(localDeletions)
                .subtracting(remoteDeletions)
                .union(additions)
        ).sorted()
    }

    static func mergedHistory(
        local: [ActiveSessionRecord],
        remote: [ActiveSessionRecord]
    ) -> [ActiveSessionRecord] {
        var recordsByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for record in local {
            recordsByID[record.id] = record
        }
        return Array(
            recordsByID.values
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(100)
        )
    }

    private func performSync(_ request: CloudSyncRequest) async -> CloudSyncMergeResult? {
        var preparedResult: CloudSyncMergeResult?
        var state = (try? store.loadCloudSyncState()) ?? CloudSyncState()
        let generation = syncGeneration
        var activeUserID: UUID?

        do {
            let session = try await client.auth.session
            let userID = session.user.id
            activeUserID = userID
            guard isCurrent(generation, userID: userID) else { return nil }
            let prepared = prepareLocalData(
                for: userID,
                history: request.history,
                websiteDomains: request.websiteDomains
            )
            preparedResult = prepared
            guard isCurrent(generation, userID: userID) else { return nil }
            state = (try? store.loadCloudSyncState()) ?? state
            state.pending = true
            state.lastAttemptAt = Date()
            state.lastError = nil
            status = .syncing
            errorMessage = nil
            persist(state)

            try await client
                .from("profiles")
                .upsert(
                    CloudProfileRow(id: userID, email: session.user.email, platform: "ios"),
                    onConflict: "id"
                )
                .execute()
            guard isCurrent(generation, userID: userID) else { return nil }

            let remoteWebsiteRows: [CloudWebsiteBlocklistRow] = try await client
                .from("website_blocklist")
                .select("user_id, domain")
                .eq("user_id", value: userID)
                .execute()
                .value
            guard isCurrent(generation, userID: userID) else { return nil }
            let remoteFocusRows: [CloudFocusSessionRow] = try await client
                .from("focus_sessions")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value
            guard isCurrent(generation, userID: userID) else { return nil }

            var cache = loadCache(userID: userID)
            let mergedDomains = Self.mergedDomains(
                base: cache.lastSyncedWebsiteDomains,
                local: prepared.websiteDomains,
                remote: remoteWebsiteRows.map(\.domain)
            )
            let mergedHistory = Self.mergedHistory(
                local: prepared.focusHistory,
                remote: remoteFocusRows.compactMap { $0.localRecord() }
            )

            try await client
                .rpc(
                    "replace_website_blocklist",
                    params: WebsiteBlocklistSyncParameters(domains: mergedDomains)
                )
                .execute()
            guard isCurrent(generation, userID: userID) else { return nil }

            let focusRows = mergedHistory.map {
                CloudFocusSessionRow(userID: userID, record: $0)
            }
            if !focusRows.isEmpty {
                try await client
                    .from("focus_sessions")
                    .upsert(focusRows, onConflict: "id")
                    .execute()
            }
            guard isCurrent(generation, userID: userID) else { return nil }

            cache.websiteDomains = mergedDomains
            cache.focusHistory = mergedHistory
            cache.lastSyncedWebsiteDomains = mergedDomains
            saveCache(cache, userID: userID)

            let successfulAt = Date()
            state.userID = userID
            state.pending = false
            state.lastSuccessfulSyncAt = successfulAt
            state.lastError = nil
            persist(state)
            boundUserID = userID
            lastSuccessfulSyncAt = successfulAt
            errorMessage = nil
            status = .synced
            guard isCurrent(generation, userID: userID) else { return nil }
            return CloudSyncMergeResult(
                websiteDomains: mergedDomains,
                focusHistory: mergedHistory
            )
        } catch {
            guard isCurrent(generation, userID: activeUserID) else { return nil }
            state.pending = true
            state.lastError = error.localizedDescription
            persist(state)
            errorMessage = Self.userFacingMessage(for: error)
            status = .failed
            return preparedResult
        }
    }

    private func isCurrent(_ generation: Int, userID: UUID? = nil) -> Bool {
        guard !Task.isCancelled, generation == syncGeneration else { return false }
        guard let userID else { return true }
        return client.auth.currentSession?.user.id == userID
    }

    private func loadCache(userID: UUID) -> CloudAccountCache {
        (try? store.loadCloudAccountCache(userID: userID)) ?? CloudAccountCache()
    }

    private func saveCache(_ cache: CloudAccountCache, userID: UUID) {
        try? store.saveCloudAccountCache(cache, userID: userID)
    }

    private func persist(_ state: CloudSyncState) {
        try? store.saveCloudSyncState(state)
    }

    private static func normalizedDomains(_ domains: [String]) -> [String] {
        Array(Set(domains.map { $0.lowercased() })).sorted()
    }

    private static func normalizedHistory(_ history: [ActiveSessionRecord]) -> [ActiveSessionRecord] {
        mergedHistory(local: history, remote: [])
    }

    private static func userFacingMessage(for error: Error) -> String {
        let description = error.localizedDescription
        let lowercased = description.lowercased()
        if lowercased.contains("offline")
            || lowercased.contains("network")
            || lowercased.contains("timed out")
            || lowercased.contains("internet") {
            return "Cloud sync will retry when you’re back online."
        }
        return "Cloud sync needs attention. Check that the Supabase schema is installed, then retry."
    }
}
