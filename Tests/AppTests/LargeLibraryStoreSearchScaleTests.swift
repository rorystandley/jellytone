import Foundation
import GRDB
import XCTest
@testable import Jellytone

final class LargeLibraryStoreSearchScaleTests: XCTestCase {
    private static let seed: UInt64 = 0x5CA1_E2026
    private static let elapsedCeilings: [String: Double] = [
        "generation": 20_000,
        "gateway_mapping": 30_000,
        "initial_refresh": 30_000,
        "idempotent_refresh": 30_000,
        "representative_searches": 20_000,
    ]
    private static let processMemoryCeiling: UInt64 = 1_500_000_000

    override func tearDown() {
        LargeLibraryURLProtocol.handler = nil
        super.tearDown()
    }

    func testGeneratedLargeLibraryMapsRefreshesAndSearchesWithinBoundedResources() async throws {
        let recorder = LargeLibraryScaleEvidenceRecorder()
        let configuration = DeterministicLargeMusicLibraryGenerator.Configuration(
            seed: Self.seed,
            artistCount: 240,
            albumsPerArtist: 6,
            discsPerAlbum: 2,
            tracksPerDisc: 8
        )
        let fixture = await recorder.measure(
            operation: "generation",
            elapsedCeilingMilliseconds: try ceiling(for: "generation"),
            peakResidentCeilingBytes: Self.processMemoryCeiling
        ) {
            DeterministicLargeMusicLibraryGenerator.generate(configuration)
        }

        // Count and anomaly assertions are deterministic correctness gates and
        // intentionally do not depend on the machine's measured timings.
        XCTAssertEqual(fixture.metadata.artistCount, 240)
        XCTAssertEqual(fixture.metadata.albumCount, 1_440)
        XCTAssertEqual(fixture.metadata.trackCount, 23_040)
        XCTAssertEqual(
            fixture.metadata.sha256,
            "40ddd91d568c997d067e2d31eee348a22de455ee5d020807d1b0381f0b4f6871"
        )
        XCTAssertGreaterThan(fixture.metadata.compilationAlbumCount, 100)
        XCTAssertGreaterThan(fixture.metadata.duplicateArtistNameCount, 0)
        XCTAssertGreaterThan(fixture.metadata.duplicateAlbumNameCount, 0)
        XCTAssertGreaterThan(fixture.metadata.unicodeNameCount, 0)
        XCTAssertGreaterThan(fixture.metadata.missingAlbumArtworkCount, 0)
        XCTAssertGreaterThan(fixture.metadata.missingTrackMetadataCount, 0)

        let mappedAlbums = try await recorder.measure(
            operation: "gateway_mapping",
            elapsedCeilingMilliseconds: try ceiling(for: "gateway_mapping"),
            peakResidentCeilingBytes: Self.processMemoryCeiling
        ) {
            try await self.mapAllAlbumPages(fixture: fixture, pageSize: 127)
        }
        XCTAssertEqual(mappedAlbums, fixture.albums)
        XCTAssertEqual(Set(mappedAlbums.map(\.id)).count, fixture.metadata.albumCount)

        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let primaryScope = LibraryScope(serverID: "scale-server-a", accountID: "scale-account-a")
        let libraryID = "scale-library"
        try await recorder.measure(
            operation: "initial_refresh",
            elapsedCeilingMilliseconds: try ceiling(for: "initial_refresh"),
            peakResidentCeilingBytes: Self.processMemoryCeiling
        ) {
            try await store.replaceAlbums(mappedAlbums, scope: primaryScope, libraryID: libraryID)
            try await store.storeSearchMetadata(
                artists: fixture.artists,
                albums: [],
                scope: primaryScope,
                libraryID: libraryID
            )
        }
        try assertDatabaseCounts(
            databaseURL: databaseURL,
            expectedArtists: fixture.metadata.artistCount,
            expectedAlbums: fixture.metadata.albumCount
        )

        try await recorder.measure(
            operation: "idempotent_refresh",
            elapsedCeilingMilliseconds: try ceiling(for: "idempotent_refresh"),
            peakResidentCeilingBytes: Self.processMemoryCeiling
        ) {
            for _ in 0..<2 {
                for startIndex in stride(from: 0, to: fixture.artists.count, by: 127) {
                    try await store.storeSearchMetadata(
                        artists: Array(fixture.artists[startIndex..<min(startIndex + 127, fixture.artists.count)]),
                        albums: [],
                        scope: primaryScope,
                        libraryID: libraryID
                    )
                }
                for startIndex in stride(from: 0, to: mappedAlbums.count, by: 127) {
                    try await store.storeSearchMetadata(
                        artists: [],
                        albums: Array(mappedAlbums[startIndex..<min(startIndex + 127, mappedAlbums.count)]),
                        scope: primaryScope,
                        libraryID: libraryID
                    )
                }
            }
        }
        try assertDatabaseCounts(
            databaseURL: databaseURL,
            expectedArtists: fixture.metadata.artistCount,
            expectedAlbums: fixture.metadata.albumCount
        )

        let removedIDs = Set(mappedAlbums.suffix(17).map(\.id))
        var replacement = Array(mappedAlbums.dropLast(17))
        let originalFirst = try XCTUnwrap(replacement.first)
        replacement[0] = Album(
            id: originalFirst.id,
            name: "Scale Replacement Sentinel",
            artist: originalFirst.artist,
            productionYear: originalFirst.productionYear,
            imageTag: originalFirst.imageTag
        )
        try await store.replaceAlbums(replacement, scope: primaryScope, libraryID: libraryID)
        let replacedAlbums = try await store.cachedAlbums(scope: primaryScope, libraryID: libraryID)
        XCTAssertEqual(replacedAlbums.count, mappedAlbums.count - removedIDs.count)
        XCTAssertEqual(replacedAlbums.first { $0.id == originalFirst.id }?.name, "Scale Replacement Sentinel")
        XCTAssertTrue(removedIDs.isDisjoint(with: replacedAlbums.map(\.id)))

        // Restore the complete authoritative page before local-search checks.
        try await store.replaceAlbums(mappedAlbums, scope: primaryScope, libraryID: libraryID)

        let otherScope = LibraryScope(serverID: "scale-server-a", accountID: "scale-account-b")
        let isolatedArtist = Artist(
            id: fixture.artists[0].id,
            name: "Scale Isolation Sentinel Artist",
            imageTag: nil
        )
        let isolatedAlbum = Album(
            id: fixture.albums[0].id,
            name: "Scale Isolation Sentinel Album",
            artist: isolatedArtist.name,
            productionYear: nil,
            imageTag: nil
        )
        try await store.storeSearchMetadata(
            artists: [isolatedArtist],
            albums: [isolatedAlbum],
            scope: otherScope,
            libraryID: libraryID
        )
        let otherServerScope = LibraryScope(serverID: "scale-server-b", accountID: "scale-account-a")
        let serverIsolatedArtist = Artist(
            id: fixture.artists[0].id,
            name: "Scale Server Isolation Sentinel Artist",
            imageTag: nil
        )
        let serverIsolatedAlbum = Album(
            id: fixture.albums[0].id,
            name: "Scale Server Isolation Sentinel Album",
            artist: serverIsolatedArtist.name,
            productionYear: nil,
            imageTag: nil
        )
        try await store.storeSearchMetadata(
            artists: [serverIsolatedArtist],
            albums: [serverIsolatedAlbum],
            scope: otherServerScope,
            libraryID: libraryID
        )
        let primaryIsolation = try await store.searchMusic(
            query: "isolation sentinel",
            scope: primaryScope,
            libraryID: libraryID
        )
        let otherIsolation = try await store.searchMusic(
            query: "isolation sentinel",
            scope: otherScope,
            libraryID: libraryID
        )
        let serverIsolation = try await store.searchMusic(
            query: "server isolation sentinel",
            scope: otherServerScope,
            libraryID: libraryID
        )
        XCTAssertTrue(primaryIsolation.artists.isEmpty && primaryIsolation.albums.isEmpty)
        XCTAssertEqual(otherIsolation.artists, [isolatedArtist])
        XCTAssertEqual(otherIsolation.albums, [isolatedAlbum])
        XCTAssertEqual(serverIsolation.artists, [serverIsolatedArtist])
        XCTAssertEqual(serverIsolation.albums, [serverIsolatedAlbum])

        let duplicateArtistName = try XCTUnwrap(firstDuplicate(in: fixture.artists.map(\.name)))
        let duplicateAlbumName = try XCTUnwrap(firstDuplicate(in: fixture.albums.map(\.name)))
        let unicodeAlbum = try XCTUnwrap(
            fixture.albums.first { $0.name.unicodeScalars.contains(where: { $0.value > 0x7f }) }
        )
        let searches = try await recorder.measure(
            operation: "representative_searches",
            elapsedCeilingMilliseconds: try ceiling(for: "representative_searches"),
            peakResidentCeilingBytes: Self.processMemoryCeiling
        ) {
            let artist = try await store.searchMusic(
                query: duplicateArtistName,
                scope: primaryScope,
                libraryID: libraryID
            )
            let album = try await store.searchMusic(
                query: duplicateAlbumName,
                scope: primaryScope,
                libraryID: libraryID
            )
            let unicode = try await store.searchMusic(
                query: unicodeAlbum.name,
                scope: primaryScope,
                libraryID: libraryID
            )
            let repeated = try await (0..<3).asyncMap {
                _ in try await store.searchMusic(
                    query: "synthetic",
                    scope: primaryScope,
                    libraryID: libraryID
                )
            }
            return (artist, album, unicode, repeated)
        }
        XCTAssertEqual(
            Set(searches.0.artists.filter { $0.name == duplicateArtistName }.map(\.id)),
            Set(fixture.artists.filter { $0.name == duplicateArtistName }.map(\.id))
        )
        XCTAssertEqual(
            Set(searches.1.albums.filter { $0.name == duplicateAlbumName }.map(\.id)),
            Set(fixture.albums.filter { $0.name == duplicateAlbumName }.map(\.id))
        )
        XCTAssertTrue(searches.2.albums.contains(where: { $0.id == unicodeAlbum.id }))
        XCTAssertEqual(searches.3[0], searches.3[1])
        XCTAssertEqual(searches.3[1], searches.3[2])
        XCTAssertEqual(Set(searches.3[0].artists.map(\.id)).count, searches.3[0].artists.count)
        XCTAssertEqual(Set(searches.3[0].albums.map(\.id)).count, searches.3[0].albums.count)

        assertLargeMergePreservesIdentityAndServerPagination(cached: searches.3[0])

        try recorder.attach(
            generatorVersion: fixture.metadata.formatVersion,
            seed: fixture.metadata.seed,
            contentSHA256: fixture.metadata.sha256,
            artistCount: fixture.metadata.artistCount,
            albumCount: fixture.metadata.albumCount,
            trackCount: fixture.metadata.trackCount,
            to: self
        )

        // Resource ceilings are deliberately generous and asserted only after
        // all deterministic data, identity, ordering, and count assertions.
        recorder.assertMeasurementsWithinCeilings()
    }

    private func mapAllAlbumPages(
        fixture: DeterministicLargeMusicLibraryGenerator.Fixture,
        pageSize: Int
    ) async throws -> [Album] {
        LargeLibraryURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let startIndex = Int(query["StartIndex"] ?? "0") ?? 0
            let limit = Int(query["Limit"] ?? "0") ?? 0
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, fixture.jellyfinAlbumsPage(startIndex: startIndex, limit: limit))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LargeLibraryURLProtocol.self]
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://large-fixture.invalid/jellyfin")),
            deviceID: "scale-device",
            token: "synthetic-token",
            urlSession: URLSession(configuration: configuration)
        )

        var albums: [Album] = []
        var startIndex = 0
        repeat {
            let page = try await api.albums(
                userID: "scale-account",
                libraryID: "scale-library",
                startIndex: startIndex,
                limit: pageSize
            )
            albums.append(contentsOf: page.albums)
            XCTAssertEqual(page.nextStartIndex, min(startIndex + pageSize, fixture.albums.count))
            startIndex = page.nextStartIndex
            if !page.hasMore { break }
        } while startIndex < fixture.albums.count
        return albums
    }

    private func assertLargeMergePreservesIdentityAndServerPagination(cached: MusicSearchPage) {
        let cachedArtists = Array(cached.artists.prefix(180))
        let cachedAlbums = Array(cached.albums.prefix(240))
        let serverArtists = cachedArtists.prefix(90).map {
            Artist(id: $0.id, name: "Server \($0.name)", imageTag: $0.imageTag)
        } + [Artist(id: "server-only-artist", name: "Server Only", imageTag: nil)]
        let serverAlbums = cachedAlbums.prefix(120).map {
            Album(
                id: $0.id,
                name: "Server \($0.name)",
                artist: $0.artist,
                productionYear: $0.productionYear,
                imageTag: $0.imageTag
            )
        } + [Album(
            id: "server-only-album",
            name: "Server Only",
            artist: "Server Only",
            productionYear: nil,
            imageTag: nil
        )]
        let server = MusicSearchPage(
            artists: serverArtists + serverArtists.prefix(5),
            albums: serverAlbums + serverAlbums.prefix(5),
            hasMore: true,
            nextStartIndex: 375
        )
        let local = MusicSearchPage(
            artists: cachedArtists + cachedArtists.prefix(5),
            albums: cachedAlbums + cachedAlbums.prefix(5),
            hasMore: false,
            nextStartIndex: cachedArtists.count + cachedAlbums.count
        )

        let first = MusicSearchResultMerger.merge(cached: local, server: server)
        let second = MusicSearchResultMerger.merge(cached: local, server: server)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.nextStartIndex, 375)
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(Set(first.artists.map(\.id)).count, first.artists.count)
        XCTAssertEqual(Set(first.albums.map(\.id)).count, first.albums.count)
        XCTAssertEqual(first.artists.first?.name, serverArtists.first?.name)
        XCTAssertEqual(first.albums.first?.name, serverAlbums.first?.name)
        XCTAssertEqual(first.artists.last?.id, "server-only-artist")
        XCTAssertEqual(first.albums.last?.id, "server-only-album")
    }

    private func assertDatabaseCounts(
        databaseURL: URL,
        expectedArtists: Int,
        expectedAlbums: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let databaseQueue = try DatabaseQueue(path: databaseURL.path)
        let counts = try databaseQueue.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cached_artists") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(DISTINCT item_id) FROM cached_artists") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cached_albums") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(DISTINCT item_id) FROM cached_albums") ?? -1
            )
        }
        XCTAssertEqual(counts.0, expectedArtists, file: file, line: line)
        XCTAssertEqual(counts.1, expectedArtists, file: file, line: line)
        XCTAssertEqual(counts.2, expectedAlbums, file: file, line: line)
        XCTAssertEqual(counts.3, expectedAlbums, file: file, line: line)
    }

    private func firstDuplicate(in values: [String]) -> String? {
        var seen = Set<String>()
        return values.first { !seen.insert($0).inserted }
    }

    private func ceiling(for operation: String) throws -> Double {
        try XCTUnwrap(Self.elapsedCeilings[operation])
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LargeLibraryStoreSearchScaleTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("metadata.sqlite")
    }
}

private final class LargeLibraryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Sequence {
    func asyncMap<Value>(_ transform: (Element) async throws -> Value) async rethrows -> [Value] {
        var values: [Value] = []
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
