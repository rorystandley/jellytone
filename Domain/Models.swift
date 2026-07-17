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
}

struct MusicSearchPage: Equatable, Sendable {
    let artists: [Artist]
    let albums: [Album]
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

    init(
        id: String,
        name: String,
        artist: String,
        album: String,
        albumID: String? = nil,
        index: Int?,
        disc: Int?,
        durationTicks: Int64?
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.albumID = albumID
        self.index = index
        self.disc = disc
        self.durationTicks = durationTicks
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
