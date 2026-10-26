import UIKit

/// Process-wide hot index so views can paint a memory hit without awaiting
/// the artwork actor. Separate from each cache instance's own index so a
/// test double over a temp directory still proves disk round-trips.
private let artworkHotIndex = ArtworkMemoryIndex()

/// Two-tier artwork cache: an in-memory index for instant paint, plus files in
/// the system Caches directory (safe for the OS to evict, excluded from backups
/// by default). Keys are scoped by server so multi-server artwork never mixes.
/// Purgeable from Settings and cleared on sign-out.
///
/// Display is cache-first: a warm launch reads disk (and memory) immediately.
/// The first network fetch for a key in a process overwrites the stored bytes
/// so a server-side art change lands without waiting for a manual purge.
actor ArtworkCache {
    static let shared = ArtworkCache()

    nonisolated private let memory = ArtworkMemoryIndex()
    private let directory: URL
    /// Keys whose server bytes have been refreshed this process. A miss here
    /// means the next reader should fetch and write-through.
    private var revalidated: Set<String> = []

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Artwork", isDirectory: true)
        memory.countLimit = 400
        artworkHotIndex.countLimit = 400
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func key(serverID: String, itemID: String) -> String {
        "\(serverID)_\(itemID)"
    }

    /// Instant memory-only lookup. Safe to call from a view body / onAppear
    /// without awaiting the actor.
    nonisolated static func memoryImage(forKey key: String) -> UIImage? {
        artworkHotIndex.image(forKey: key)
    }

    func image(forKey key: String) -> UIImage? {
        if let hit = memory.image(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let image = UIImage(data: data) else { return nil }
        remember(image, forKey: key)
        return image
    }

    /// Decode into memory from disk for the given keys so the next view paint
    /// can hit `memoryImage` without a disk round-trip. Missing files are skipped.
    func warm(keys: [String]) {
        for key in keys where memory.image(forKey: key) == nil {
            _ = image(forKey: key)
        }
    }

    func store(_ data: Data, forKey key: String) {
        guard let image = UIImage(data: data) else { return }
        remember(image, forKey: key)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Returns true once per process per key so only the first reader fetches
    /// from the server. Call `allowRevalidation` if that fetch fails so a later
    /// appear can retry.
    func takeRevalidation(forKey key: String) -> Bool {
        revalidated.insert(key).inserted
    }

    func allowRevalidation(forKey key: String) {
        revalidated.remove(key)
    }

    /// Total bytes on disk, for the Settings cache row.
    func diskBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else { return 0 }
        return files.reduce(into: Int64(0)) { total, file in
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    func clear() {
        memory.removeAll()
        artworkHotIndex.removeAll()
        revalidated.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func remember(_ image: UIImage, forKey key: String) {
        memory.store(image, forKey: key)
        artworkHotIndex.store(image, forKey: key)
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

/// `NSCache` is thread-safe and not Sendable; isolate it behind this wrapper
/// so views can read a hot hit without hopping to the artwork actor.
private final class ArtworkMemoryIndex: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
