import Foundation

struct TrackCatalogScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
    let libraryID: String?
}

@MainActor
final class TrackCatalogState: ObservableObject {
    @Published private(set) var occurrences: [TrackCatalogOccurrence] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var nextStartIndex = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?
    private var generation = 0
    private var scope: TrackCatalogScope?

    func clear(for scope: TrackCatalogScope) {
        generation += 1
        self.scope = scope
        occurrences = []
        hasLoaded = false
        hasMore = false
        nextStartIndex = 0
        errorMessage = nil
        paginationError = nil
    }

    func replaceCached(_ page: TrackCatalogPage, scope: TrackCatalogScope) {
        generation += 1; self.scope = scope
        occurrences = page.occurrences.sorted(by: TrackCatalogOrdering.precedes)
        hasMore = page.hasMore; nextStartIndex = page.nextStartIndex; hasLoaded = true
    }

    func refresh(scope requested: TrackCatalogScope, load: @escaping (Int) async throws -> TrackCatalogPage) async {
        generation += 1
        let requestGeneration = generation; scope = requested; isLoading = true; errorMessage = nil
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let page = try await load(0); try Task.checkCancellation()
            guard generation == requestGeneration, self.scope == requested else { return }
            occurrences = Self.merge([], page.occurrences); hasMore = page.hasMore; nextStartIndex = page.nextStartIndex; hasLoaded = true
        } catch is CancellationError { return }
        catch { if generation == requestGeneration, self.scope == requested { errorMessage = error.localizedDescription; hasLoaded = true } }
    }

    func loadMore(scope requested: TrackCatalogScope, load: @escaping (Int) async throws -> TrackCatalogPage) async {
        guard hasMore, !isLoadingMore, self.scope == requested else { return }
        isLoadingMore = true; paginationError = nil
        defer { isLoadingMore = false }
        do {
            let page = try await load(nextStartIndex); try Task.checkCancellation()
            guard self.scope == requested else { return }
            occurrences = Self.merge(occurrences, page.occurrences); hasMore = page.hasMore; nextStartIndex = page.nextStartIndex
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { paginationError = error.localizedDescription } }
    }

    private static func merge(_ existing: [TrackCatalogOccurrence], _ incoming: [TrackCatalogOccurrence]) -> [TrackCatalogOccurrence] {
        var seen = Set(existing.map(\.id)); var result = existing
        for value in incoming where seen.insert(value.id).inserted { result.append(value) }
        return result.sorted(by: TrackCatalogOrdering.precedes)
    }
}
