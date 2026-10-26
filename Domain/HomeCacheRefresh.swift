import Foundation

/// Cache-first Home refresh with scope supplied by the caller's current session.
/// The caller owns scope changes; this utility deliberately never writes a
/// response under a different scope.
@MainActor
enum HomeCacheRefresh {
    static func execute(
        scope: LibraryScope,
        libraryID: String?,
        store: (any LibraryStoring)?,
        present: (HomeShelfSnapshot) -> Void,
        server: () async throws -> HomeShelfSnapshot
    ) async -> Result<HomeShelfSnapshot, Error> {
        if let store,
           let cached = try? await store.cachedHomeShelfSnapshot(scope: scope, libraryID: libraryID) {
            present(cached)
        }

        do {
            let refreshed = try await server()
            try? await store?.replaceHomeShelfSnapshot(
                refreshed,
                scope: scope,
                libraryID: libraryID
            )
            present(refreshed)
            return .success(refreshed)
        } catch {
            return .failure(error)
        }
    }
}

/// Serializes ownership of Home refreshes. It prevents an older completion from
/// persisting or presenting after a newer request (including a scope switch).
@MainActor
final class HomeCacheRefreshCoordinator {
    private var requestID = 0

    func refresh(
        scope: LibraryScope,
        libraryID: String?,
        store: (any LibraryStoring)?,
        present: (HomeShelfSnapshot) -> Void,
        server: () async throws -> HomeShelfSnapshot
    ) async -> Result<HomeShelfSnapshot, Error> {
        requestID += 1
        let id = requestID
        if let store,
           let cached = try? await store.cachedHomeShelfSnapshot(scope: scope, libraryID: libraryID),
           owns(id) {
            present(cached)
        }

        do {
            let refreshed = try await server()
            guard owns(id) else { return .failure(CancellationError()) }
            try? await store?.replaceHomeShelfSnapshot(
                refreshed,
                scope: scope,
                libraryID: libraryID
            )
            guard owns(id) else { return .failure(CancellationError()) }
            present(refreshed)
            return .success(refreshed)
        } catch {
            return .failure(error)
        }
    }

    private func owns(_ id: Int) -> Bool { requestID == id }
}
