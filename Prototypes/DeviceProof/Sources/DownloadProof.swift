@preconcurrency import AVFoundation
import CryptoKit
import Foundation

struct ProofMediaManifest: Codable, Sendable {
    let schemaVersion: Int
    let fixtures: [ProofMediaEntry]

    func entry(id: String) -> ProofMediaEntry? {
        fixtures.first { $0.id == id }
    }

    static func bundled() throws -> ProofMediaManifest {
        guard let url = Bundle.main.url(forResource: "proof-media-manifest", withExtension: "json") else {
            throw DownloadProofError.missingManifest
        }
        return try JSONDecoder().decode(ProofMediaManifest.self, from: Data(contentsOf: url))
    }
}

struct ProofMediaEntry: Codable, Equatable, Sendable {
    let bytes: Int
    let file: String
    let id: String
    let sha256: String
}

struct DownloadProofState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case scheduled
        case installed
        case probed
        case acknowledged

        var rank: Int {
            switch self {
            case .scheduled: 0
            case .installed: 1
            case .probed: 2
            case .acknowledged: 3
            }
        }
    }

    let sessionIdentifier: String
    let runIdentifier: String
    var tasks: [DownloadProofTask]
    var acknowledgementCount: Int
}

struct DownloadProofTask: Codable, Equatable, Sendable {
    let taskIdentifier: Int
    let media: ProofMediaEntry
    var phase: DownloadProofState.Phase
}

enum DownloadProofError: Error, Equatable {
    case missingManifest
    case missingMediaEntry
    case unexpectedStatus
    case unexpectedContentType
    case byteCountMismatch
    case digestMismatch
    case finalFileUnreadable
    case finalFileNotPlayable
    case noAudioTrack
}

enum DownloadProofPolicy {
    /// Cancellation/resume requires an operator-triggered device run because an
    /// automatic launch must not claim process suspension or OS resume behavior.
    static let cancellationResumeStatus = "operator_device_procedure_required"
}

enum DownloadPayloadValidator {
    static func validate(
        data: Data,
        statusCode: Int,
        contentType: String?,
        expected: ProofMediaEntry
    ) throws {
        guard 200..<300 ~= statusCode else { throw DownloadProofError.unexpectedStatus }
        let normalizedType = contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let acceptedTypes = ["audio/", "application/ogg", "application/octet-stream", "video/mp4"]
        guard let normalizedType, acceptedTypes.contains(where: normalizedType.hasPrefix) else {
            throw DownloadProofError.unexpectedContentType
        }
        guard data.count == expected.bytes else { throw DownloadProofError.byteCountMismatch }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected.sha256 else { throw DownloadProofError.digestMismatch }
    }
}

final class DownloadProofStateStore: @unchecked Sendable {
    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("device-proof-download-state.json")
    }

    func save(_ state: DownloadProofState) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnlocked(state)
    }

    private func saveUnlocked(_ state: DownloadProofState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        let staging = fileURL.deletingLastPathComponent().appendingPathComponent(".download-state-staging")
        try? FileManager.default.removeItem(at: staging)
        try data.write(to: staging, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: fileURL)
        }
    }

    func load() throws -> DownloadProofState {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loadUnlocked() throws -> DownloadProofState {
        try JSONDecoder().decode(DownloadProofState.self, from: Data(contentsOf: fileURL))
    }

    func task(_ taskIdentifier: Int) throws -> DownloadProofTask {
        let state = try load()
        guard let task = state.tasks.first(where: { $0.taskIdentifier == taskIdentifier }) else {
            throw DownloadProofError.missingMediaEntry
        }
        return task
    }

    func updatePhase(_ phase: DownloadProofState.Phase, taskIdentifier: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        var state = try loadUnlocked()
        guard let index = state.tasks.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) else {
            throw DownloadProofError.missingMediaEntry
        }
        if phase.rank > state.tasks[index].phase.rank { state.tasks[index].phase = phase }
        try saveUnlocked(state)
    }

    /// Returns true exactly once. Duplicate delegate callbacks are persisted as
    /// a count but cannot produce another successful acknowledgement.
    func recordAcknowledgement() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var state = try loadUnlocked()
        state.acknowledgementCount += 1
        let first = state.acknowledgementCount == 1
        if first {
            for index in state.tasks.indices where DownloadProofState.Phase.acknowledged.rank > state.tasks[index].phase.rank {
                state.tasks[index].phase = .acknowledged
            }
        }
        try saveUnlocked(state)
        return first
    }
}

enum DownloadFileInstaller {
    static func stagingURL(destination: URL, expected: ProofMediaEntry) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(".download-\(expected.id)-staging")
    }

    static func installValidated(
        temporaryURL: URL,
        response: HTTPURLResponse,
        expected: ProofMediaEntry,
        destination: URL
    ) throws {
        let data = try Data(contentsOf: temporaryURL)
        try DownloadPayloadValidator.validate(
            data: data,
            statusCode: response.statusCode,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            expected: expected
        )

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = stagingURL(destination: destination, expected: expected)
        try? FileManager.default.removeItem(at: staging)
        try data.write(to: staging, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }

        let reopened = try Data(contentsOf: destination)
        try DownloadPayloadValidator.validate(
            data: reopened,
            statusCode: response.statusCode,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            expected: expected
        )
    }

    static func probeFinalAudio(at url: URL) async throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw DownloadProofError.finalFileUnreadable
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw DownloadProofError.finalFileNotPlayable }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw DownloadProofError.noAudioTrack }
    }
}
