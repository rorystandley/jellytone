import CryptoKit
import XCTest
@testable import Jellytone

@MainActor
final class DownloadManagerTests: XCTestCase {
    func testDownloadVerifiesCommitsPersistsAndRemoves() async throws {
        let workspace = temporaryDirectory()
        let downloadsDirectory = workspace.appendingPathComponent("offline", isDirectory: true)
        let store = try SQLiteLibraryStore(databaseURL: workspace.appendingPathComponent("library.sqlite"))
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")

        // Source audio served over file:// so the full pipeline runs without
        // a network dependency.
        let sourceBytes = Data((0..<4096).map { UInt8($0 % 251) })
        let sourceURL = workspace.appendingPathComponent("song.mp3")
        try sourceBytes.write(to: sourceURL)
        let expectedDigest = SHA256.hash(data: sourceBytes).map { String(format: "%02x", $0) }.joined()

        let manager = DownloadManager(store: store, directory: downloadsDirectory)
        manager.scopeProvider = { scope }
        manager.requestProvider = { _ in URLRequest(url: sourceURL) }

        let track = Track(id: "track-a", name: "Synthetic Track", artist: "Synthetic Artist",
                          album: "Synthetic Album", index: 1, disc: 1, durationTicks: 1_200_000_000)
        manager.download([track], container: DownloadContainer(kind: .album, id: "album-a", name: "Synthetic Album"))

        try await waitUntil("download completes") { manager.records.count == 1 }
        let record = try XCTUnwrap(manager.records.first)
        XCTAssertEqual(record.byteCount, Int64(sourceBytes.count))
        XCTAssertEqual(record.digest, expectedDigest)
        XCTAssertEqual(record.fileName, "track-a.mp3")
        XCTAssertEqual(record.containerName, "Synthetic Album")
        XCTAssertNil(manager.state(of: track.id))

        let localURL = try XCTUnwrap(manager.localURL(for: track.id))
        XCTAssertEqual(try Data(contentsOf: localURL), sourceBytes)

        // A relaunch resolves the same verified source from the manifest.
        let relaunched = DownloadManager(store: store, directory: downloadsDirectory)
        relaunched.scopeProvider = { scope }
        await relaunched.refreshRecords()
        XCTAssertEqual(relaunched.records, [record])
        XCTAssertNotNil(relaunched.localURL(for: track.id))

        // Another account never sees the record.
        let otherAccount = DownloadManager(store: store, directory: downloadsDirectory)
        otherAccount.scopeProvider = { LibraryScope(serverID: "server-a", accountID: "account-b") }
        await otherAccount.refreshRecords()
        XCTAssertTrue(otherAccount.records.isEmpty)

        // Removal deletes the file and the manifest row together.
        await manager.remove(track.id)
        XCTAssertNil(manager.localURL(for: track.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
        let remaining = try await store.downloadedTracks(scope: scope)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testFailedFetchCommitsNoRecordOrFile() async throws {
        let workspace = temporaryDirectory()
        let downloadsDirectory = workspace.appendingPathComponent("offline", isDirectory: true)
        let store = try SQLiteLibraryStore(databaseURL: workspace.appendingPathComponent("library.sqlite"))
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")

        let manager = DownloadManager(store: store, directory: downloadsDirectory)
        manager.scopeProvider = { scope }
        manager.requestProvider = { _ in
            URLRequest(url: workspace.appendingPathComponent("does-not-exist.mp3"))
        }

        let track = Track(id: "track-missing", name: "Missing", artist: "Synthetic Artist",
                          album: "Synthetic Album", index: 1, disc: 1, durationTicks: nil)
        manager.download([track], container: DownloadContainer(kind: .track, id: track.id, name: track.name))

        try await waitUntil("failure is recorded") {
            if case .failed = manager.state(of: track.id) { return true }
            return false
        }
        XCTAssertTrue(manager.records.isEmpty)
        XCTAssertNil(manager.localURL(for: track.id))
        let persisted = try await store.downloadedTracks(scope: scope)
        XCTAssertTrue(persisted.isEmpty)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 10,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("Timed out waiting until \(what)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
