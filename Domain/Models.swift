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

struct PlaybackPlan: Sendable {
    let url: URL
    let mediaSourceID: String
    let playSessionID: String
    let method: PlaybackMethod
}

struct PlaybackSnapshot: Codable, Equatable, Sendable {
    let scope: String
    let queue: [Track]
    let currentIndex: Int
    let position: TimeInterval
}
