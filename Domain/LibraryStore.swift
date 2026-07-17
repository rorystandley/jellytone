import Foundation

struct LibraryScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
}

protocol LibraryStoring: Sendable {
    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album]
    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws
    /// Returns the complete, versioned Home snapshot for this server/account/library
    /// scope. A missing or malformed record is treated as an unavailable cache.
    func cachedHomeShelfSnapshot(
        scope: LibraryScope,
        libraryID: String?
    ) async throws -> HomeShelfSnapshot?
    /// Replaces every Home shelf together so consumers never observe a mixed
    /// recently-added/recently-played generation.
    func replaceHomeShelfSnapshot(
        _ snapshot: HomeShelfSnapshot,
        scope: LibraryScope,
        libraryID: String?
    ) async throws
    func storeSearchMetadata(
        artists: [Artist],
        albums: [Album],
        scope: LibraryScope,
        libraryID: String?
    ) async throws
    func searchMusic(query: String, scope: LibraryScope, libraryID: String?) async throws -> MusicSearchPage
}
