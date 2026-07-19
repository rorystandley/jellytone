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
    let madeForYouPlaylists: [Playlist]

    init(
        version: Int = currentVersion,
        recentlyAddedAlbums: [Album],
        recentlyPlayedTracks: [Track],
        madeForYouPlaylists: [Playlist] = []
    ) {
        self.version = version
        self.recentlyAddedAlbums = recentlyAddedAlbums
        self.recentlyPlayedTracks = recentlyPlayedTracks
        self.madeForYouPlaylists = madeForYouPlaylists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        recentlyAddedAlbums = try container.decode([Album].self, forKey: .recentlyAddedAlbums)
        recentlyPlayedTracks = try container.decode([Track].self, forKey: .recentlyPlayedTracks)
        // Shelf added after the first shipped payloads — older cached
        // snapshots without the key stay valid rather than being discarded.
        madeForYouPlaylists = try container.decodeIfPresent([Playlist].self, forKey: .madeForYouPlaylists) ?? []
    }
}
