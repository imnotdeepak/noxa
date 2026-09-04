//
//  FamilyControlsAuthorizationService.swift
//  Noxa
//

import Combine
import FamilyControls
import Foundation

enum ScreenTimeAuthorizationState: String, Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case approved
    case approvedWithDataAccess
}

/// Small main-app wrapper around Apple's authorization lifecycle.
///
/// It intentionally exposes Noxa-owned states instead of leaking Apple's
/// enum through the rest of the UI and state model.
@MainActor
final class FamilyControlsAuthorizationService: ObservableObject {
    @Published private(set) var state: ScreenTimeAuthorizationState = .unknown
    @Published private(set) var errorMessage: String?

    private let center = AuthorizationCenter.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        center.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.update(from: status)
            }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        update(from: center.authorizationStatus)
    }

    func requestAuthorization() async {
        errorMessage = nil

        do {
            try await center.requestAuthorization(for: .individual)
            refresh()
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }

    private func update(from status: AuthorizationStatus) {
        switch status {
        case .approved:
            state = .approved
        case .approvedWithDataAccess:
            state = .approvedWithDataAccess
        case .denied:
            state = .denied
        case .notDetermined:
            state = .notDetermined
        @unknown default:
            state = .unknown
        }
    }
}
