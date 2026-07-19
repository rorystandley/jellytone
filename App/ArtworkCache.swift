import UIKit

/// Two-tier artwork cache: NSCache for hot images, plus files in the system
/// Caches directory (safe for the OS to evict, excluded from backups by
/// default). Keys are scoped by server so multi-server artwork never mixes.
/// Purgeable from Settings and cleared on sign-out.
actor ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Artwork", isDirectory: true)
        memory.countLimit = 400
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func key(serverID: String, itemID: String) -> String {
        "\(serverID)_\(itemID)"
    }

    func image(forKey key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    func store(_ data: Data, forKey key: String) {
        guard let image = UIImage(data: data) else { return }
        memory.setObject(image, forKey: key as NSString)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Total bytes on disk, for the Settings "Image Cache" row.
    func diskBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else { return 0 }
        return files.reduce(into: Int64(0)) { total, file in
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        // Jellyfin identifiers are filesystem-safe hex; hash anything else
        // defensively so a hostile name can never escape the directory.
        let safe = key.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
        let name = safe ? key : String(format: "%016llx", fnv1a(key))
        return directory.appendingPathComponent(name)
    }

    private func fnv1a(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
