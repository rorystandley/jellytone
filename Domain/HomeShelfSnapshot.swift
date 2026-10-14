import Foundation

/// A Listen Now–style discovery mix seeded from a library item (artist, album,
/// or track). Artwork and title are cached with Home; Instant Mix tracks are
/// fetched on play so the shelf stays light.
struct DiscoveryMix: Identifiable, Codable, Hashable, Sendable {
    enum SeedKind: String, Codable, Sendable {
        case artist
        case album
        case track
    }

    let id: String
    let seedItemID: String
    let seedKind: SeedKind
    let title: String
    let subtitle: String
    /// Item ID used for artwork fetch (often the seed, sometimes an album).
    let artworkItemID: String
    let imageTag: String?
}

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
    let favouriteArtists: [Artist]
    /// Most-played albums in this library (PlayCount), Listen Now "Top Albums".
    let frequentlyPlayedAlbums: [Album]
    /// Random library albums for Rediscover.
    let rediscoverAlbums: [Album]
    /// Instant Mix seeds built from favourites / recent listening.
    let discoveryMixes: [DiscoveryMix]
    /// Compact genre chips for Listen Now browsing.
    let homeGenres: [Genre]

    init(
        version: Int = currentVersion,
        recentlyAddedAlbums: [Album],
        recentlyPlayedTracks: [Track],
        madeForYouPlaylists: [Playlist] = [],
        favouriteArtists: [Artist] = [],
        frequentlyPlayedAlbums: [Album] = [],
        rediscoverAlbums: [Album] = [],
        discoveryMixes: [DiscoveryMix] = [],
        homeGenres: [Genre] = []
    ) {
        self.version = version
        self.recentlyAddedAlbums = recentlyAddedAlbums
        self.recentlyPlayedTracks = recentlyPlayedTracks
        self.madeForYouPlaylists = madeForYouPlaylists
        self.favouriteArtists = favouriteArtists
        self.frequentlyPlayedAlbums = frequentlyPlayedAlbums
        self.rediscoverAlbums = rediscoverAlbums
        self.discoveryMixes = discoveryMixes
        self.homeGenres = homeGenres
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        recentlyAddedAlbums = try container.decode([Album].self, forKey: .recentlyAddedAlbums)
        recentlyPlayedTracks = try container.decode([Track].self, forKey: .recentlyPlayedTracks)
        // Shelves added after the first shipped payloads — older cached
        // snapshots without the keys stay valid rather than being discarded.
        madeForYouPlaylists = try container.decodeIfPresent([Playlist].self, forKey: .madeForYouPlaylists) ?? []
        favouriteArtists = try container.decodeIfPresent([Artist].self, forKey: .favouriteArtists) ?? []
        frequentlyPlayedAlbums = try container.decodeIfPresent([Album].self, forKey: .frequentlyPlayedAlbums) ?? []
        rediscoverAlbums = try container.decodeIfPresent([Album].self, forKey: .rediscoverAlbums) ?? []
        discoveryMixes = try container.decodeIfPresent([DiscoveryMix].self, forKey: .discoveryMixes) ?? []
        homeGenres = try container.decodeIfPresent([Genre].self, forKey: .homeGenres) ?? []
    }

    /// Partial shelf update helper so Home refresh can merge successful
    /// requests without restating every field at each call site.
    func updating(
        recentlyAddedAlbums: [Album]? = nil,
        recentlyPlayedTracks: [Track]? = nil,
        madeForYouPlaylists: [Playlist]? = nil,
        favouriteArtists: [Artist]? = nil,
        frequentlyPlayedAlbums: [Album]? = nil,
        rediscoverAlbums: [Album]? = nil,
        discoveryMixes: [DiscoveryMix]? = nil,
        homeGenres: [Genre]? = nil
    ) -> HomeShelfSnapshot {
        HomeShelfSnapshot(
            version: version,
            recentlyAddedAlbums: recentlyAddedAlbums ?? self.recentlyAddedAlbums,
            recentlyPlayedTracks: recentlyPlayedTracks ?? self.recentlyPlayedTracks,
            madeForYouPlaylists: madeForYouPlaylists ?? self.madeForYouPlaylists,
            favouriteArtists: favouriteArtists ?? self.favouriteArtists,
            frequentlyPlayedAlbums: frequentlyPlayedAlbums ?? self.frequentlyPlayedAlbums,
            rediscoverAlbums: rediscoverAlbums ?? self.rediscoverAlbums,
            discoveryMixes: discoveryMixes ?? self.discoveryMixes,
            homeGenres: homeGenres ?? self.homeGenres
        )
    }
}
