import Foundation

/// Ephemeral LRU cache of recently-streamed audio, so replaying a track in
/// quick succession reads from disk instead of the server. Distinct from
/// downloads: files here are OS-evictable (system Caches directory), unverified,
/// and never presented as "downloaded" or relied on for offline playback — a
/// miss simply falls back to streaming. Only original-container (direct-play)
/// audio is cached, since that is the byte-stable resource AVPlayer can reuse.
@MainActor
final class RecentAudioCache {
    private struct Entry {
        let fileName: String
        let bytes: Int64
        var sequence: Int
    }

    private let directory: URL
    private let urlSession: URLSession
    private let byteBudget: Int64
    private var index: [String: Entry] = [:]
    private var sequenceCounter = 0
    private var inFlight: Set<String> = []

    /// Default budget ~500 MB — enough to hold a listening session's rotation
    /// without competing with downloads for space.
    init(directory: URL? = nil, byteBudget: Int64 = 500 * 1_024 * 1_024, urlSession: URLSession = .shared) {
        self.byteBudget = byteBudget
        self.urlSession = urlSession
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RecentAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        rebuildIndexFromDisk()
    }

    /// Cached file for a track, or nil on a miss. A hit refreshes the track's
    /// LRU recency.
    func localURL(for trackID: String) -> URL? {
        guard let entry = index[trackID] else { return nil }
        let url = directory.appendingPathComponent(entry.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            index[trackID] = nil
            return nil
        }
        sequenceCounter += 1
        index[trackID]?.sequence = sequenceCounter
        return url
    }

    /// Fetches and stores a track's original audio for replay. No-op when it is
    /// already cached or in flight; failures are silent (the cache is optional).
    func remember(trackID: String, request: URLRequest) async {
        guard index[trackID] == nil, !inFlight.contains(trackID) else { return }
        inFlight.insert(trackID)
        defer { inFlight.remove(trackID) }
        do {
            let (tempURL, response) = try await urlSession.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) { return }
            guard index[trackID] == nil else { return }  // lost a race

            let byteCount = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? nil ?? 0
            guard byteCount > 0 else { return }
            let fileName = "\(sanitized(trackID)).\(Self.fileExtension(for: response))"
            let destination = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            sequenceCounter += 1
            index[trackID] = Entry(fileName: fileName, bytes: byteCount, sequence: sequenceCounter)
            evictIfNeeded()
        } catch {
            // Replay caching is best-effort; streaming remains the fallback.
        }
    }

    func clear() {
        index = [:]
        inFlight = []
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var totalBytes: Int64 { index.values.reduce(0) { $0 + $1.bytes } }

    // MARK: LRU

    private func evictIfNeeded() {
        while totalBytes > byteBudget, index.count > 1 {
            guard let oldest = index.min(by: { $0.value.sequence < $1.value.sequence }) else { return }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldest.value.fileName))
            index[oldest.key] = nil
        }
    }

    private func rebuildIndexFromDisk() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return }
        // Seed recency from modification date so prior-session files evict oldest-first.
        let dated = files.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }
        for (url, _) in dated {
            let trackID = url.deletingPathExtension().lastPathComponent
            let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            sequenceCounter += 1
            index[trackID] = Entry(fileName: url.lastPathComponent, bytes: bytes, sequence: sequenceCounter)
        }
        evictIfNeeded()
    }

    private func sanitized(_ trackID: String) -> String {
        let safe = trackID.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        if safe { return trackID }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in trackID.utf8 { hash ^= UInt64(byte); hash &*= 0x100000001b3 }
        return String(format: "%016llx", hash)
    }

    // Local copy of the container→extension mapping (see DownloadManager); the
    // ephemeral cache keeps its own so it has no dependency on the downloads path.
    nonisolated private static func fileExtension(for response: URLResponse) -> String {
        if let suggested = response.suggestedFilename {
            let ext = (suggested as NSString).pathExtension.lowercased()
            if !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) { return ext }
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
