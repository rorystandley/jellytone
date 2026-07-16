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

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let index: Int?
    let disc: Int?
    let durationTicks: Int64?

    var duration: TimeInterval {
        guard let durationTicks else { return 0 }
        return Double(durationTicks) / 10_000_000
    }

    var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
