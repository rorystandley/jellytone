import Foundation
import OSLog

enum Diagnostics {
    private static let logger = Logger(subsystem: "org.example.jellyfinaudio", category: "state")
    private static let fileLock = NSLock()

    static func event(_ name: String, _ values: [String: CustomStringConvertible] = [:]) {
        let fields = values.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let message = fields.isEmpty ? "JA_DIAG \(name)" : "JA_DIAG \(name) \(fields)"
        logger.notice("\(message, privacy: .public)")
        print(message)
        persist("\(Int(Date().timeIntervalSince1970)) \(message)\n")
    }

    private static func persist(_ line: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = line.data(using: .utf8) else { return }
        let url = documents.appending(path: "diagnostics.log")
        let existingSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if existingSize > 64 * 1_024 {
            try? data.write(to: url, options: .atomic)
            return
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
