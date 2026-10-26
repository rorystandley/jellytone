import Foundation

/// Where a download was initiated from — used to group the Downloads screen.
struct DownloadContainer: Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case album, playlist, track
    }

    let kind: Kind
    let id: String
    let name: String
}

/// Verified manifest record for one downloaded track (ADR 0009): committed
/// only after byte-count and digest verification plus an atomic move. Stores
/// the relative file name only — never an authenticated URL.
struct DownloadedTrack: Codable, Hashable, Sendable, Identifiable {
    let track: Track
    let containerKind: DownloadContainer.Kind
    let containerID: String
    let containerName: String
    let fileName: String
    let byteCount: Int64
    let digest: String
    let completedAtEpochSeconds: Int64

    var id: String { track.id }
}
