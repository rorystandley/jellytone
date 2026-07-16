import Foundation

struct ProofEvent: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let runIdentifier: String
    let sequence: Int
    let monotonicMilliseconds: UInt64
    let category: String
    let action: String
    let result: String
    let facts: [String: String]
}

enum ProofRedactor {
    private static let forbiddenKeys = ["url", "host", "address", "token", "authorization", "username", "path", "device", "team", "certificate"]

    static func sanitizedFacts(_ facts: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: facts.map { key, value in
            let lowered = key.lowercased()
            if forbiddenKeys.contains(where: lowered.contains) {
                return (key, "<redacted>")
            }
            return (key, scrub(value))
        })
    }

    static func scrub(_ value: String) -> String {
        var result = value
        let patterns = [
            #"https?://[^\s]+"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#,
            #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27,}\b"#,
            #"(?i)(bearer|token|api_key)[=: ]+[^\s]+"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "<redacted>")
        }
        return result
    }
}

final class ProofEventStore: @unchecked Sendable {
    static let shared = ProofEventStore()
    private let lock = NSLock()
    private var sequence: Int
    private var runIdentifier: String
    private let encoder = JSONEncoder()
    let fileURL: URL

    init(fileURL: URL? = nil, runIdentifier: String? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("device-proof-events.jsonl")
        self.sequence = 0
        self.runIdentifier = runIdentifier ?? UUID().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if runIdentifier == nil,
           let data = try? Data(contentsOf: self.fileURL),
           let lastLine = String(decoding: data, as: UTF8.self).split(separator: "\n").last,
           let lastEvent = try? JSONDecoder().decode(ProofEvent.self, from: Data(lastLine.utf8)) {
            self.sequence = lastEvent.sequence
            self.runIdentifier = lastEvent.runIdentifier
        }
    }

    func activeRunIdentifier() -> String {
        lock.lock()
        defer { lock.unlock() }
        return runIdentifier
    }

    func append(
        category: String,
        action: String,
        result: String,
        facts: [String: String] = [:],
        expectedRunIdentifier: String? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard expectedRunIdentifier == nil || expectedRunIdentifier == runIdentifier else { return }
        sequence += 1
        let event = ProofEvent(
            schemaVersion: 1,
            runIdentifier: runIdentifier,
            sequence: sequence,
            monotonicMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000,
            category: category,
            action: action,
            result: result,
            facts: ProofRedactor.sanitizedFacts(facts)
        )
        guard let encoded = try? encoder.encode(event) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: encoded + Data([0x0A]))
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        sequence = 0
        runIdentifier = UUID().uuidString.lowercased()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
