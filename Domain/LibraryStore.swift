import Foundation

struct LibraryScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
}

protocol LibraryStoring: Sendable {
    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album]
    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws
    func storeSearchMetadata(
        artists: [Artist],
        albums: [Album],
        scope: LibraryScope,
        libraryID: String?
    ) async throws
    func searchMusic(query: String, scope: LibraryScope, libraryID: String?) async throws -> MusicSearchPage
}
