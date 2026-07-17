@MainActor
enum CacheFirstAlbumRefresh {
    static func execute(
        scope: LibraryScope,
        libraryID: String?,
        store: (any LibraryStoring)?,
        present: ([Album]) -> Void,
        server: () async throws -> AlbumPage
    ) async throws -> AlbumPage {
        if let store,
           let cached = try? await store.cachedAlbums(scope: scope, libraryID: libraryID) {
            present(cached)
        }

        let refreshed = try await server()
        present(refreshed.albums)
        try? await store?.replaceAlbums(refreshed.albums, scope: scope, libraryID: libraryID)
        return refreshed
    }
}
