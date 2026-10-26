import Foundation

@MainActor
enum CacheBackedMusicSearch {
    /// Cache-first music search. When `startIndex == 0`, any local hits are
    /// painted immediately via `present` (before the network round-trip) so
    /// typing feels instant; the final return value always merges server
    /// refresh on top of that cache (or returns cache alone when offline).
    static func execute(
        query: String,
        startIndex: Int,
        scope: LibraryScope,
        libraryID: String?,
        store: (any LibraryStoring)?,
        present: ((MusicSearchPage) -> Void)? = nil,
        server: () async throws -> MusicSearchPage
    ) async throws -> MusicSearchPage {
        let cached: MusicSearchPage
        if startIndex == 0, let store {
            cached = (try? await store.searchMusic(query: query, scope: scope, libraryID: libraryID))
                ?? emptyPage
        } else {
            cached = emptyPage
        }

        if startIndex == 0, !cached.isEmpty {
            present?(cached)
        }

        do {
            let refreshed = try await server()
            try? await store?.storeSearchMetadata(
                artists: refreshed.artists,
                albums: refreshed.albums,
                playlists: refreshed.playlists,
                scope: scope,
                libraryID: libraryID
            )
            return MusicSearchResultMerger.merge(cached: cached, server: refreshed)
        } catch {
            if isOffline(error) { return cached }
            throw error
        }
    }

    private static let emptyPage = MusicSearchPage()

    private static func isOffline(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .timedOut, .dnsLookupFailed,
        ].contains(code)
    }
}
