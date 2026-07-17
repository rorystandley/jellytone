import Foundation

/// Application-owned, versioned cache payload for the selected music library's
/// Home shelves. Scope identity belongs to the LibraryStore key, never to this
/// persisted value.
struct HomeShelfSnapshot: Codable, Hashable, Sendable {
    static let currentVersion = 1
    static let empty = HomeShelfSnapshot(recentlyAddedAlbums: [], recentlyPlayedTracks: [])

    let version: Int
    let recentlyAddedAlbums: [Album]
    let recentlyPlayedTracks: [Track]

    init(
        version: Int = currentVersion,
        recentlyAddedAlbums: [Album],
        recentlyPlayedTracks: [Track]
    ) {
        self.version = version
        self.recentlyAddedAlbums = recentlyAddedAlbums
        self.recentlyPlayedTracks = recentlyPlayedTracks
    }
}
