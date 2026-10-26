import CryptoKit
import Foundation

/// Owns offline audio downloads (ADR 0009 first slice): a sequential queue
/// that fetches original-container audio, verifies byte count and digest,
/// moves the file atomically into the offline directory, and only then
/// commits a manifest record. Source resolution trusts the manifest, never
/// filesystem presence alone. Files live in Application Support (excluded
/// from backup, never OS-evicted like the artwork cache).
@MainActor
final class DownloadManager: ObservableObject {
    enum ActiveState: Equatable {
        case waiting
        case downloading
        case failed(String)
    }

    /// Committed manifest, newest first.
    @Published private(set) var records: [DownloadedTrack] = []
    /// In-flight/failed state per track id; absent means idle.
    @Published private(set) var activeStates: [String: ActiveState] = [:]

    /// Session context, supplied by the coordinator. Downloads are inert
    /// (and `records` empty) while either returns nil.
    var scopeProvider: (@MainActor () -> LibraryScope?)?
    var requestProvider: (@MainActor (Track) throws -> URLRequest)?
    /// Best-effort artwork warm-up after a commit so offline rows and Now
    /// Playing have covers. Failures are ignored.
    var artworkPrefetch: (@MainActor (Track) async -> Void)?

    private let store: (any LibraryStoring)?
    private let directory: URL
    private let urlSession: URLSession
    private var loadedScope: LibraryScope?
    private var pending: [(track: Track, container: DownloadContainer)] = []
    private var isWorking = false

    init(store: (any LibraryStoring)?, directory: URL? = nil, urlSession: URLSession = .shared) {
        self.store = store
        self.urlSession = urlSession
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directoryURL = self.directory
        try? directoryURL.setResourceValues(values)
    }

    // MARK: Queries

    func isDownloaded(_ trackID: String) -> Bool {
        records.contains { $0.track.id == trackID }
    }

    /// Verified local source for playback: manifest record + file present.
    func localURL(for trackID: String) -> URL? {
        guard let record = records.first(where: { $0.track.id == trackID }) else { return nil }
        let url = directory.appendingPathComponent(record.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var totalBytes: Int64 {
        records.reduce(into: Int64(0)) { $0 += $1.byteCount }
    }

    func state(of trackID: String) -> ActiveState? { activeStates[trackID] }

    // MARK: Manifest lifecycle

    /// Loads the manifest for the current session scope (no-op when already
    /// loaded for that scope).
    func refreshRecords() async {
        guard let scope = scopeProvider?() else {
            records = []
            loadedScope = nil
            return
        }
        guard scope != loadedScope else { return }
        records = (try? await store?.downloadedTracks(scope: scope)) ?? []
        loadedScope = scope
    }

    // MARK: Download queue

    func download(_ tracks: [Track], container: DownloadContainer) {
        let newEntries = tracks.filter { track in
            !isDownloaded(track.id)
                && activeStates[track.id] == nil
                && !pending.contains { $0.track.id == track.id }
        }
        guard !newEntries.isEmpty else { return }
        JellytoneHaptics.play(.light)
        for track in newEntries {
            pending.append((track, container))
            activeStates[track.id] = .waiting
        }
        startWorkerIfNeeded()
    }

    func remove(_ trackID: String) async {
        let hadPending = pending.contains { $0.track.id == trackID } || activeStates[trackID] != nil
        let hadRecord = records.contains { $0.track.id == trackID }
        activeStates[trackID] = nil
        pending.removeAll { $0.track.id == trackID }
        guard hadPending || hadRecord else { return }
        JellytoneHaptics.destructive()
        if let record = records.first(where: { $0.track.id == trackID }) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.fileName))
        }
        if let scope = scopeProvider?() {
            try? await store?.removeDownloadedTrack(itemID: trackID, scope: scope)
        }
        records.removeAll { $0.track.id == trackID }
    }

    /// Removes every download and the files directory content (sign-out).
    func removeAll() async {
        pending.removeAll()
        activeStates = [:]
        if let scope = scopeProvider?() {
            for record in records {
                try? await store?.removeDownloadedTrack(itemID: record.track.id, scope: scope)
            }
        }
        records = []
        loadedScope = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func startWorkerIfNeeded() {
        guard !isWorking else { return }
        isWorking = true
        Task { [weak self] in
            while let self, !self.pending.isEmpty {
                let next = self.pending.removeFirst()
                await self.performDownload(track: next.track, container: next.container)
            }
            self?.isWorking = false
        }
    }

    private func performDownload(track: Track, container: DownloadContainer) async {
        guard let scope = scopeProvider?(), let request = try? requestProvider?(track) else {
            activeStates[track.id] = .failed("Not connected")
            return
        }
        activeStates[track.id] = .downloading
        do {
            let (tempURL, response) = try await urlSession.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
                throw APIError.httpStatus(http.statusCode)
            }

            // Verify byte count against the response before committing.
            let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            let byteCount = (attributes[.size] as? Int64) ?? 0
            let expected = response.expectedContentLength
            guard byteCount > 0, expected <= 0 || byteCount == expected else {
                throw APIError.invalidResponse
            }
            let digest = try Self.sha256Hex(of: tempURL)

            let fileName = "\(track.id).\(Self.fileExtension(for: response))"
            let destination = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            // Manifest commit is last — a crash before this line leaves an
            // orphan file, never an unverified record.
            let record = DownloadedTrack(
                track: track,
                containerKind: container.kind,
                containerID: container.id,
                containerName: container.name,
                fileName: fileName,
                byteCount: byteCount,
                digest: digest,
                completedAtEpochSeconds: Int64(Date().timeIntervalSince1970)
            )
            try await store?.recordDownloadedTrack(record, scope: scope)
            records.removeAll { $0.track.id == track.id }
            records.insert(record, at: 0)
            activeStates[track.id] = nil
            Diagnostics.event("download_completed", ["bytes": byteCount])
            await artworkPrefetch?(track)
        } catch {
            activeStates[track.id] = .failed(error.localizedDescription)
            Diagnostics.event("download_failed", ["code": (error as NSError).code])
        }
    }

    // MARK: Verification helpers

    nonisolated private static func sha256Hex(of url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func fileExtension(for response: URLResponse) -> String {
        if let suggested = response.suggestedFilename {
            let ext = (suggested as NSString).pathExtension.lowercased()
            if !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return ext
            }
        }
        switch response.mimeType?.lowercased() {
        case "audio/mpeg": return "mp3"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mp4", "audio/x-m4a", "audio/aac": return "m4a"
        case "audio/ogg", "application/ogg": return "ogg"
        case "audio/wav", "audio/x-wav": return "wav"
        default: return "mp3"
        }
    }
}
