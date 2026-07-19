import CryptoKit
import Foundation
import XCTest
@testable import Jellytone

final class DeterministicLargeMusicLibraryFixtureTests: XCTestCase {
    private let fixedSeed: UInt64 = 0x5EED_F17E_2026_0001

    func testDefaultConfigurationGeneratesMeaningfulLibraryAndAnomalyCoverage() throws {
        let fixture = DeterministicLargeMusicLibraryGenerator.generate(.init(seed: fixedSeed))

        XCTAssertEqual(fixture.metadata.formatVersion, 1)
        XCTAssertEqual(fixture.metadata.seed, fixedSeed)
        XCTAssertEqual(fixture.metadata.artistCount, 200)
        XCTAssertEqual(fixture.metadata.albumCount, 800)
        XCTAssertEqual(fixture.metadata.trackCount, 12_800)
        XCTAssertEqual(fixture.metadata.multiDiscAlbumCount, 800)
        XCTAssertGreaterThan(fixture.metadata.compilationAlbumCount, 50)
        XCTAssertGreaterThan(fixture.metadata.duplicateArtistNameCount, 5)
        XCTAssertGreaterThan(fixture.metadata.duplicateAlbumNameCount, 20)
        XCTAssertGreaterThan(fixture.metadata.missingArtistArtworkCount, 20)
        XCTAssertGreaterThan(fixture.metadata.missingAlbumArtworkCount, 100)
        XCTAssertGreaterThan(fixture.metadata.missingAlbumMetadataCount, 80)
        XCTAssertGreaterThan(fixture.metadata.missingTrackMetadataCount, 900)
        XCTAssertGreaterThan(fixture.metadata.unicodeNameCount, 300)
        XCTAssertEqual(fixture.albumDetails.count, fixture.albums.count)
        XCTAssertEqual(fixture.compilationAlbumIDs.count, fixture.metadata.compilationAlbumCount)

        let compilationID = try XCTUnwrap(fixture.compilationAlbumIDs.first)
        let compilation = try XCTUnwrap(fixture.albums.first(where: { $0.id == compilationID }))
        XCTAssertEqual(compilation.artist, "Various Artists")
        XCTAssertGreaterThan(Set(fixture.tracks(albumID: compilationID).map(\.artist)).count, 1)
        XCTAssertTrue(fixture.tracks.contains(where: { $0.disc == 2 }))
        XCTAssertTrue(fixture.tracks.contains(where: {
            $0.index == nil || $0.disc == nil || $0.durationTicks == nil
        }))
    }

    func testSameVersionedConfigurationIsByteIdenticalWithSameSHA256() {
        let configuration = compactConfiguration(seed: fixedSeed)
        let first = DeterministicLargeMusicLibraryGenerator.generate(configuration)
        let second = DeterministicLargeMusicLibraryGenerator.generate(configuration)

        XCTAssertEqual(first.configuration, configuration)
        XCTAssertEqual(first.canonicalBytes, second.canonicalBytes)
        XCTAssertEqual(first.metadata, second.metadata)
        XCTAssertEqual(first.metadata.sha256, sha256(first.canonicalBytes))
        XCTAssertEqual(first.metadata.sha256.count, 64)
        XCTAssertEqual(first.canonicalBytes.last, 0x0A)
        XCTAssertEqual(
            first.metadata.sha256,
            "4e110be83722d944458a053b9924dfceb6aaecc26d05ce502d26f404a1d1e7c6"
        )
    }

    func testChangedSeedAndChangedConfigurationChangeCanonicalHash() {
        let baseline = DeterministicLargeMusicLibraryGenerator.generate(compactConfiguration(seed: fixedSeed))
        let changedSeed = DeterministicLargeMusicLibraryGenerator.generate(
            compactConfiguration(seed: fixedSeed &+ 1)
        )
        let changedConfiguration = DeterministicLargeMusicLibraryGenerator.generate(
            .init(
                seed: fixedSeed,
                artistCount: 24,
                albumsPerArtist: 3,
                discsPerAlbum: 2,
                tracksPerDisc: 5
            )
        )

        XCTAssertNotEqual(baseline.metadata.sha256, changedSeed.metadata.sha256)
        XCTAssertNotEqual(baseline.canonicalBytes, changedSeed.canonicalBytes)
        XCTAssertNotEqual(baseline.metadata.sha256, changedConfiguration.metadata.sha256)
        XCTAssertNotEqual(baseline.canonicalBytes, changedConfiguration.canonicalBytes)
    }

    func testOrderingAndSerializationUseExplicitIndicesAndCanonicalKeys() throws {
        let fixture = DeterministicLargeMusicLibraryGenerator.generate(compactConfiguration(seed: fixedSeed))

        XCTAssertEqual(fixture.artists.map(\.id), fixture.artists.map(\.id).sorted())
        XCTAssertEqual(fixture.albums.map(\.id), fixture.albums.map(\.id).sorted())
        XCTAssertEqual(fixture.tracks.map(\.id), fixture.tracks.map(\.id).sorted())
        XCTAssertTrue(String(decoding: fixture.canonicalBytes, as: UTF8.self).hasPrefix(#"{"albumDetails":"#))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.canonicalBytes) as? [String: Any]
        )
        let configuration = try XCTUnwrap(object["configuration"] as? [String: Any])
        XCTAssertEqual(configuration["version"] as? Int, 1)
        XCTAssertEqual(configuration["seed"] as? NSNumber, NSNumber(value: fixedSeed))
    }

    func testWireHelpersPreserveRawPaginationCountsAndStableJellyfinShapes() throws {
        let fixture = DeterministicLargeMusicLibraryGenerator.generate(compactConfiguration(seed: fixedSeed))
        let firstPage = fixture.jellyfinAlbumsPage(startIndex: 5, limit: 7)
        let repeatedPage = fixture.jellyfinAlbumsPage(startIndex: 5, limit: 7)
        XCTAssertEqual(firstPage, repeatedPage)
        XCTAssertEqual(firstPage.last, 0x0A)

        let albumResponse = try response(firstPage)
        let albumItems = try XCTUnwrap(albumResponse["Items"] as? [[String: Any]])
        XCTAssertEqual(albumResponse["TotalRecordCount"] as? Int, fixture.albums.count)
        XCTAssertEqual(albumItems.count, 7)
        XCTAssertEqual(albumItems.first?["Id"] as? String, fixture.albums[5].id)
        XCTAssertEqual(albumItems.first?["Type"] as? String, "MusicAlbum")

        let searchData = fixture.jellyfinSearchPage(query: "synthetic", startIndex: 3, limit: 11)
        let searchResponse = try response(searchData)
        let searchItems = try XCTUnwrap(searchResponse["Items"] as? [[String: Any]])
        XCTAssertEqual(searchItems.count, 11)
        XCTAssertGreaterThan(searchResponse["TotalRecordCount"] as? Int ?? 0, searchItems.count)
        XCTAssertTrue(searchItems.allSatisfy { ($0["Type"] as? String) == "MusicArtist"
            || ($0["Type"] as? String) == "MusicAlbum" })

        let albumID = fixture.albums[1].id
        let trackResponse = try response(fixture.jellyfinTracksResponse(albumID: albumID))
        let trackItems = try XCTUnwrap(trackResponse["Items"] as? [[String: Any]])
        XCTAssertEqual(trackResponse["TotalRecordCount"] as? Int, 8)
        XCTAssertEqual(trackItems.count, 8)
        XCTAssertTrue(trackItems.allSatisfy { ($0["AlbumId"] as? String) == albumID })
        XCTAssertTrue(trackItems.allSatisfy { ($0["Type"] as? String) == "Audio" })

        let detailData = try XCTUnwrap(fixture.jellyfinAlbumDetailResponse(albumID: albumID))
        let detail = try XCTUnwrap(JSONSerialization.jsonObject(with: detailData) as? [String: Any])
        XCTAssertEqual(detail["Id"] as? String, albumID)
        XCTAssertEqual(detail["Type"] as? String, "MusicAlbum")
        XCTAssertNil(fixture.jellyfinAlbumDetailResponse(albumID: "missing"))
    }

    private func compactConfiguration(seed: UInt64) -> DeterministicLargeMusicLibraryGenerator.Configuration {
        .init(
            seed: seed,
            artistCount: 24,
            albumsPerArtist: 3,
            discsPerAlbum: 2,
            tracksPerDisc: 4
        )
    }

    private func response(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            let encoded = String(byte, radix: 16, uppercase: false)
            return encoded.count == 1 ? "0" + encoded : encoded
        }.joined()
    }
}
