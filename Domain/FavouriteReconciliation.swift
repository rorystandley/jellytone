import Foundation

enum FavouriteMutationOutcome: Sendable, Equatable {
    case succeeded, authenticationExpired, transient, permanent, cancelled
}

protocol FavouriteWriteGateway: Sendable {
    func setFavourite(userID: String, itemID: String, desired: Bool) async -> FavouriteMutationOutcome
}

actor FavouriteReconciler {
    private let store: any LibraryStoring
    init(store: any LibraryStoring) { self.store = store }
    func reconcile(scope: LibraryScope, gateway: any FavouriteWriteGateway, now: Int64 = 0) async {
        guard let rows = try? await store.pendingFavourites(scope: scope) else { return }
        for row in rows where row.state == .pending && row.nextRetryAt <= now {
            let outcome = await gateway.setFavourite(userID: scope.accountID, itemID: row.itemID, desired: row.desired)
            switch outcome {
            case .succeeded: try? await store.completeFavourite(row)
            case .authenticationExpired: var next = row; next.state = .pausedAuth; try? await store.updateFavourite(next)
            case .permanent: var next = row; next.state = .terminal; try? await store.updateFavourite(next)
            case .cancelled: break
            case .transient:
                var next = row; next.attempts += 1; next.nextRetryAt = now + Int64(min(3600, 1 << min(next.attempts, 10))); try? await store.updateFavourite(next)
            }
        }
    }
}
