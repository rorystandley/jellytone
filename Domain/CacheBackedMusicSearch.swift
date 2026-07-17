import Foundation

@MainActor
enum CacheBackedMusicSearch {
    static func execute(
        query: String,
        startIndex: Int,
        scope: LibraryScope,
        libraryID: String?,
        store: (any LibraryStoring)?,
        server: () async throws -> MusicSearchPage
    ) async throws -> MusicSearchPage {
        let cached: MusicSearchPage
        if startIndex == 0, let store {
            cached = (try? await store.searchMusic(query: query, scope: scope, libraryID: libraryID))
                ?? emptyPage
        } else {
            cached = emptyPage
        }

        do {
            let refreshed = try await server()
            try? await store?.storeSearchMetadata(
                artists: refreshed.artists,
                albums: refreshed.albums,
                scope: scope,
                libraryID: libraryID
            )
            return MusicSearchResultMerger.merge(cached: cached, server: refreshed)
        } catch {
            if isOffline(error) { return cached }
            throw error
        }
    }

    private static let emptyPage = MusicSearchPage(
        artists: [], albums: [], hasMore: false, nextStartIndex: 0
    )

    private static func isOffline(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .timedOut, .dnsLookupFailed,
        ].contains(code)
    }
}
