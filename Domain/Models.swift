import Foundation

struct UserSession: Codable, Equatable, Sendable {
    let serverURL: URL
    let serverID: String
    let serverName: String
    let serverVersion: String
    let userID: String
    let username: String
    let accessToken: String
    let deviceID: String
}

struct MusicLibrary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

struct Album: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let artist: String
    let productionYear: Int?
    let imageTag: String?
    /// Album-artist item ID from Jellyfin (`AlbumArtists` / related fields).
    /// Optional so older cache payloads decode without it.
    let artistID: String?

    init(
        id: String,
        name: String,
        artist: String,
        productionYear: Int?,
        imageTag: String?,
        artistID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.productionYear = productionYear
        self.imageTag = imageTag
        self.artistID = artistID
    }

    /// The album artist library item, when Jellyfin gave us that artist's ID.
    var artistDestination: Artist? {
        guard let artistID, !artist.isEmpty else { return nil }
        return Artist(id: artistID, name: artist, imageTag: nil)
    }
}

struct AlbumPage: Equatable, Sendable {
    let albums: [Album]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct Artist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let imageTag: String?
    /// Server SortName collation key, used by the Artists browse index so
    /// section jumps match the server's ordering rather than a local guess.
    /// Optional and absent from older cache payloads, which decode to `nil`.
    let sortName: String?

    init(id: String, name: String, imageTag: String?, sortName: String? = nil) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
        self.sortName = sortName
    }
}

struct MusicSearchPage: Equatable, Sendable {
    let artists: [Artist]
    let albums: [Album]
    let tracks: [Track]
    let playlists: [Playlist]
    let hasMore: Bool
    let nextStartIndex: Int

    init(
        artists: [Artist] = [],
        albums: [Album] = [],
        tracks: [Track] = [],
        playlists: [Playlist] = [],
        hasMore: Bool = false,
        nextStartIndex: Int = 0
    ) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
        self.playlists = playlists
        self.hasMore = hasMore
        self.nextStartIndex = nextStartIndex
    }

    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && tracks.isEmpty && playlists.isEmpty
    }
}

/// A page of the full Artists browse list (album artists, SortName order).
struct ArtistPage: Equatable, Sendable {
    let artists: [Artist]
    let hasMore: Bool
    let nextStartIndex: Int
}

// Favourite pages intentionally remain independently paginated.  A favourite
// track can occur more than once in a server response, so tracks use a
// response-position identity while artists and albums retain their item IDs.
struct FavouriteArtistPage: Equatable, Sendable {
    let artists: [Artist]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct FavouriteAlbumPage: Equatable, Sendable {
    let albums: [Album]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct FavouriteTrackOccurrence: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let track: Track
}

struct FavouriteTrackPage: Equatable, Sendable {
    let occurrences: [FavouriteTrackOccurrence]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct Genre: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let imageTag: String?
    let itemCount: Int?
    let albumCount: Int?
}

struct GenrePage: Equatable, Sendable {
    let genres: [Genre]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct GenreTrackOccurrence: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let track: Track
}

struct GenreTrackPage: Equatable, Sendable {
    let occurrences: [GenreTrackOccurrence]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct Playlist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let imageTag: String?
    let itemCount: Int?
}

struct PlaylistEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let track: Track
}

/// One time-stamped word within a lyric line — the data needed for true
/// karaoke highlighting. Present only when the server supplies per-word timing.
struct LyricWord: Codable, Hashable, Sendable {
    let text: String
    let startSeconds: Double
    let endSeconds: Double?
}

/// One lyric line. `startSeconds` is present only for time-synced lyrics;
/// `words` is non-empty only when the server supplies per-word timing.
struct LyricLine: Identifiable, Codable, Hashable, Sendable {
    let index: Int
    let text: String
    let startSeconds: Double?
    let words: [LyricWord]

    var id: Int { index }

    init(index: Int, text: String, startSeconds: Double?, words: [LyricWord] = []) {
        self.index = index
        self.text = text
        self.startSeconds = startSeconds
        self.words = words
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        text = try c.decode(String.self, forKey: .text)
        startSeconds = try c.decodeIfPresent(Double.self, forKey: .startSeconds)
        words = try c.decodeIfPresent([LyricWord].self, forKey: .words) ?? []
    }
}

struct TrackLyrics: Codable, Hashable, Sendable {
    let lines: [LyricLine]

    /// Synced when any line carries a timestamp — enables active-line highlight.
    var isSynced: Bool { lines.contains { $0.startSeconds != nil } }

    /// True when at least one line has per-word timing — the requirement for
    /// karaoke-style word highlighting. Currently unused by the UI (the servers
    /// tested supply only per-line timing); kept so word-timed lyrics render
    /// correctly if a library ever provides them.
    var hasWordTiming: Bool { lines.contains { !$0.words.isEmpty } }

    /// Index of the line active at `elapsed`, for synced lyrics only.
    func activeIndex(at elapsed: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var active: Int?
        for line in lines {
            guard let start = line.startSeconds else { continue }
            if start <= elapsed { active = line.index } else { break }
        }
        return active
    }
}

struct PlaylistPage: Equatable, Sendable {
    let playlists: [Playlist]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct PlaylistEntryPage: Equatable, Sendable {
    let entries: [PlaylistEntry]
    let hasMore: Bool
    let nextStartIndex: Int
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let albumID: String?
    let index: Int?
    let disc: Int?
    let durationTicks: Int64?
    let artistID: String?
    let imageTag: String?

    init(
        id: String,
        name: String,
        artist: String,
        album: String,
        albumID: String? = nil,
        index: Int?,
        disc: Int?,
        durationTicks: Int64?,
        artistID: String? = nil,
        imageTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.albumID = albumID
        self.index = index
        self.disc = disc
        self.durationTicks = durationTicks
        self.artistID = artistID
        self.imageTag = imageTag
    }

    /// Item whose Primary image represents this track — its own when it has
    /// one, otherwise its album's (most tracks carry no image of their own).
    var artworkItemID: String? {
        imageTag != nil ? id : albumID
    }

    /// The album this track belongs to, when Jellyfin gave us that album's item ID.
    var albumDestination: Album? {
        guard let albumID, !album.isEmpty else { return nil }
        return Album(
            id: albumID,
            name: album,
            artist: artist,
            productionYear: nil,
            imageTag: imageTag,
            artistID: artistID
        )
    }

    /// The performing (or album) artist this track belongs to, when Jellyfin
    /// gave us that artist's item ID.
    var artistDestination: Artist? {
        guard let artistID, !artist.isEmpty else { return nil }
        return Artist(id: artistID, name: artist, imageTag: nil)
    }

    var duration: TimeInterval {
        guard let durationTicks else { return 0 }
        return Double(durationTicks) / 10_000_000
    }

    var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A browse occurrence is intentionally separate from Track identity. Jellyfin
/// can return the same item more than once, and each displayed occurrence must
/// remain selectable at its own queue position.
struct TrackCatalogOccurrence: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let track: Track
    let ordinal: Int
}

struct TrackCatalogPage: Equatable, Sendable {
    let occurrences: [TrackCatalogOccurrence]
    let hasMore: Bool
    let nextStartIndex: Int
}

enum TrackCatalogOrdering {
    static let version = "title-normalized-artist-album-id-v1"

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    static func precedes(_ lhs: TrackCatalogOccurrence, _ rhs: TrackCatalogOccurrence) -> Bool {
        let l = lhs.track, r = rhs.track
        let ln = normalized(l.name), rn = normalized(r.name)
        if ln != rn { return ln < rn }
        let la = normalized(l.artist), ra = normalized(r.artist)
        if la != ra { return la < ra }
        let lal = normalized(l.album), ral = normalized(r.album)
        if lal != ral { return lal < ral }
        if l.id != r.id { return l.id < r.id }
        return lhs.ordinal < rhs.ordinal
    }
}

enum PlaybackMethod: String, Codable, Sendable {
    case directPlay = "DirectPlay"
    case transcode = "Transcode"
}

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

struct QueueEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let track: Track

    init(id: UUID = UUID(), track: Track) {
        self.id = id
        self.track = track
    }
}

enum QueueOrder {
    static func shuffled<R: RandomNumberGenerator>(
        _ entries: [QueueEntry],
        currentIndex: Int,
        using generator: inout R
    ) -> [QueueEntry] {
        guard entries.indices.contains(currentIndex) else { return entries }
        var upcoming = Array(entries.dropFirst(currentIndex + 1))
        upcoming.shuffle(using: &generator)
        return Array(entries.prefix(currentIndex + 1)) + upcoming
    }
}

struct PlaybackPlan: Sendable {
    let url: URL
    let mediaSourceID: String
    let playSessionID: String
    let method: PlaybackMethod
}

struct PlaybackSnapshot: Codable, Equatable, Sendable {
    let scope: String
    let queue: [QueueEntry]
    let currentIndex: Int
    let position: TimeInterval
    let originalQueue: [QueueEntry]
    let isShuffled: Bool
    let repeatMode: RepeatMode

    init(
        scope: String,
        queue: [QueueEntry],
        currentIndex: Int,
        position: TimeInterval,
        originalQueue: [QueueEntry]? = nil,
        isShuffled: Bool = false,
        repeatMode: RepeatMode = .off
    ) {
        self.scope = scope
        self.queue = queue
        self.currentIndex = currentIndex
        self.position = position
        self.originalQueue = originalQueue ?? queue
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
    }

    private enum CodingKeys: String, CodingKey {
        case scope, queueEntries, currentIndex, position, originalQueueEntries, isShuffled, repeatMode
        case queue, originalQueue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scope = try values.decode(String.self, forKey: .scope)
        currentIndex = try values.decode(Int.self, forKey: .currentIndex)
        position = try values.decode(TimeInterval.self, forKey: .position)
        isShuffled = try values.decodeIfPresent(Bool.self, forKey: .isShuffled) ?? false
        repeatMode = try values.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .off
        if let entries = try values.decodeIfPresent([QueueEntry].self, forKey: .queueEntries) {
            queue = entries
            originalQueue = try values.decodeIfPresent([QueueEntry].self, forKey: .originalQueueEntries) ?? entries
        } else {
            let legacyQueue = try values.decode([Track].self, forKey: .queue)
            let legacyOriginal = try values.decodeIfPresent([Track].self, forKey: .originalQueue) ?? legacyQueue
            let migratedOriginal = legacyOriginal.map { QueueEntry(track: $0) }
            var unused = Array(migratedOriginal.indices)
            queue = legacyQueue.map { track in
                if let unusedIndex = unused.firstIndex(where: { migratedOriginal[$0].track == track }) {
                    return migratedOriginal[unused.remove(at: unusedIndex)]
                }
                return QueueEntry(track: track)
            }
            originalQueue = migratedOriginal
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(scope, forKey: .scope)
        try values.encode(queue, forKey: .queueEntries)
        try values.encode(currentIndex, forKey: .currentIndex)
        try values.encode(position, forKey: .position)
        try values.encode(originalQueue, forKey: .originalQueueEntries)
        try values.encode(isShuffled, forKey: .isShuffled)
        try values.encode(repeatMode, forKey: .repeatMode)
    }
}
