import Foundation

/// Presentation ownership for the Home shelves. The app coordinator supplies a
/// scoped, cache-first snapshot; this type prevents an older refresh from
/// replacing the shelves after an account, server, or library change.
struct HomeFeatureScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
    let libraryID: String?
}

@MainActor
final class HomeFeatureState: ObservableObject {
    @Published private(set) var snapshot = HomeShelfSnapshot(
        recentlyAddedAlbums: [],
        recentlyPlayedTracks: []
    )
    @Published private(set) var isRefreshingRecentlyAdded = false
    @Published private(set) var isRefreshingRecentlyPlayed = false
    @Published private(set) var recentlyAddedErrorMessage: String?
    @Published private(set) var recentlyPlayedErrorMessage: String?
    @Published private(set) var hasLoaded = false

    private var scope: HomeFeatureScope?
    private var generation = 0

    var isRefreshing: Bool { isRefreshingRecentlyAdded || isRefreshingRecentlyPlayed }

    /// Presents the supplied cache synchronously, then asks the coordinator for
    /// one atomically refreshed snapshot. Errors are section-specific so a
    /// useful shelf remains usable when the other query fails.
    func load(
        scope requestedScope: HomeFeatureScope,
        cached: HomeShelfSnapshot?,
        refresh: @escaping () async -> Result<HomeShelfSnapshot, HomeShelfRefreshFailure>
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        snapshot = cached ?? HomeShelfSnapshot(recentlyAddedAlbums: [], recentlyPlayedTracks: [])
        hasLoaded = cached != nil
        recentlyAddedErrorMessage = nil
        recentlyPlayedErrorMessage = nil
        await replace(scope: requestedScope, generation: requestGeneration, refresh: refresh)
    }

    func refresh(
        scope requestedScope: HomeFeatureScope,
        refresh: @escaping () async -> Result<HomeShelfSnapshot, HomeShelfRefreshFailure>
    ) async {
        guard scope == requestedScope else { return }
        generation += 1
        await replace(scope: requestedScope, generation: generation, refresh: refresh)
    }

    private func replace(
        scope requestedScope: HomeFeatureScope,
        generation requestGeneration: Int,
        refresh: @escaping () async -> Result<HomeShelfSnapshot, HomeShelfRefreshFailure>
    ) async {
        isRefreshingRecentlyAdded = true
        isRefreshingRecentlyPlayed = true
        recentlyAddedErrorMessage = nil
        recentlyPlayedErrorMessage = nil
        defer {
            if owns(requestGeneration, requestedScope) {
                isRefreshingRecentlyAdded = false
                isRefreshingRecentlyPlayed = false
                hasLoaded = true
            }
        }

        let result = await refresh()
        guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
        switch result {
        case let .success(fresh):
            snapshot = fresh
        case let .failure(failure):
            recentlyAddedErrorMessage = failure.recentlyAddedMessage
            recentlyPlayedErrorMessage = failure.recentlyPlayedMessage
        }
    }

    private func owns(_ requestGeneration: Int, _ requestedScope: HomeFeatureScope) -> Bool {
        generation == requestGeneration && scope == requestedScope
    }
}

/// Kept presentation-only: gateway and cache layers turn their typed errors into
/// these safe, user-facing messages and never pass URLs, tokens, or metadata.
struct HomeShelfRefreshFailure: Error, Equatable, Sendable {
    let recentlyAddedMessage: String?
    let recentlyPlayedMessage: String?
}
