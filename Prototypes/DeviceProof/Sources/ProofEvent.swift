import Foundation

struct ProofEvent: Codable, Equatable, Sendable {
    let schemaVersion: Int
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
    private var sequence = 0
    private let encoder = JSONEncoder()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("device-proof-events.jsonl")
        try? FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func append(category: String, action: String, result: String, facts: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        let event = ProofEvent(
            schemaVersion: 1,
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
        try? FileManager.default.removeItem(at: fileURL)
    }
}
