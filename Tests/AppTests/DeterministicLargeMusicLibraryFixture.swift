import CryptoKit
import Foundation
@testable import Jellytone

enum DeterministicLargeMusicLibraryGenerator {
    struct Configuration: Codable, Equatable, Sendable {
        static let currentVersion = 1

        let version: Int
        let seed: UInt64
        let artistCount: Int
        let albumsPerArtist: Int
        let discsPerAlbum: Int
        let tracksPerDisc: Int

        init(
            seed: UInt64,
            version: Int = currentVersion,
            artistCount: Int = 200,
            albumsPerArtist: Int = 4,
            discsPerAlbum: Int = 2,
            tracksPerDisc: Int = 8
        ) {
            precondition(version == Self.currentVersion, "Unsupported fixture format version")
            precondition(artistCount > 0 && albumsPerArtist > 0)
            precondition(discsPerAlbum > 0 && tracksPerDisc > 0)
            self.version = version
            self.seed = seed
            self.artistCount = artistCount
            self.albumsPerArtist = albumsPerArtist
            self.discsPerAlbum = discsPerAlbum
            self.tracksPerDisc = tracksPerDisc
        }
    }

    struct AlbumDetail: Codable, Equatable, Sendable {
        let id: String
        let artistID: String
        let discCount: Int
        let isCompilation: Bool
    }

    struct Metadata: Equatable, Sendable {
        let formatVersion: Int
        let seed: UInt64
        let sha256: String
        let artistCount: Int
        let albumCount: Int
        let trackCount: Int
        let compilationAlbumCount: Int
        let multiDiscAlbumCount: Int
        let missingArtistArtworkCount: Int
        let missingAlbumArtworkCount: Int
        let missingAlbumMetadataCount: Int
        let missingTrackMetadataCount: Int
        let duplicateArtistNameCount: Int
        let duplicateAlbumNameCount: Int
        let unicodeNameCount: Int
    }

    struct Fixture: Sendable {
        let configuration: Configuration
        let metadata: Metadata
        let artists: [Artist]
        let albums: [Album]
        let tracks: [Track]
        let albumDetails: [AlbumDetail]
        let compilationAlbumIDs: [String]
        let canonicalBytes: Data

        func tracks(albumID: String) -> [Track] {
            tracks.filter { $0.albumID == albumID }
        }

        func jellyfinAlbumsPage(startIndex: Int, limit: Int) -> Data {
            precondition(startIndex >= 0 && limit > 0)
            let page = Array(albums.dropFirst(startIndex).prefix(limit))
            return DeterministicLargeMusicLibraryGenerator.canonicalData(
                WireResponse(
                    Items: page.map { album in
                        WireItem(
                            Id: album.id,
                            Name: album.name,
                            Type: "MusicAlbum",
                            AlbumArtist: album.artist,
                            Artists: [album.artist],
                            Album: nil,
                            AlbumId: nil,
                            ProductionYear: album.productionYear,
                            ImageTags: album.imageTag.map(WireImageTags.init(Primary:)),
                            IndexNumber: nil,
                            ParentIndexNumber: nil,
                            RunTimeTicks: nil
                        )
                    },
                    TotalRecordCount: albums.count
                )
            )
        }

        func jellyfinSearchPage(query: String, startIndex: Int, limit: Int) -> Data {
            precondition(startIndex >= 0 && limit > 0)
            let normalizedQuery = Self.normalized(query)
            let artistItems = artists.filter { Self.normalized($0.name).contains(normalizedQuery) }.map {
                WireItem(
                    Id: $0.id,
                    Name: $0.name,
                    Type: "MusicArtist",
                    AlbumArtist: nil,
                    Artists: nil,
                    Album: nil,
                    AlbumId: nil,
                    ProductionYear: nil,
                    ImageTags: $0.imageTag.map(WireImageTags.init(Primary:)),
                    IndexNumber: nil,
                    ParentIndexNumber: nil,
                    RunTimeTicks: nil
                )
            }
            let albumItems = albums.filter {
                Self.normalized($0.name).contains(normalizedQuery)
                    || Self.normalized($0.artist).contains(normalizedQuery)
            }.map {
                WireItem(
                    Id: $0.id,
                    Name: $0.name,
                    Type: "MusicAlbum",
                    AlbumArtist: $0.artist,
                    Artists: [$0.artist],
                    Album: nil,
                    AlbumId: nil,
                    ProductionYear: $0.productionYear,
                    ImageTags: $0.imageTag.map(WireImageTags.init(Primary:)),
                    IndexNumber: nil,
                    ParentIndexNumber: nil,
                    RunTimeTicks: nil
                )
            }
            let matches = artistItems + albumItems
            return DeterministicLargeMusicLibraryGenerator.canonicalData(
                WireResponse(
                    Items: Array(matches.dropFirst(startIndex).prefix(limit)),
                    TotalRecordCount: matches.count
                )
            )
        }

        func jellyfinTracksResponse(albumID: String) -> Data {
            let matchingTracks = tracks(albumID: albumID)
            return DeterministicLargeMusicLibraryGenerator.canonicalData(
                WireResponse(
                    Items: matchingTracks.map {
                        WireItem(
                            Id: $0.id,
                            Name: $0.name,
                            Type: "Audio",
                            AlbumArtist: albums.first(where: { $0.id == albumID })?.artist,
                            Artists: [$0.artist],
                            Album: $0.album,
                            AlbumId: $0.albumID,
                            ProductionYear: nil,
                            ImageTags: nil,
                            IndexNumber: $0.index,
                            ParentIndexNumber: $0.disc,
                            RunTimeTicks: $0.durationTicks
                        )
                    },
                    TotalRecordCount: matchingTracks.count
                )
            )
        }

        func jellyfinAlbumDetailResponse(albumID: String) -> Data? {
            guard let album = albums.first(where: { $0.id == albumID }) else { return nil }
            return DeterministicLargeMusicLibraryGenerator.canonicalData(
                WireItem(
                    Id: album.id,
                    Name: album.name,
                    Type: "MusicAlbum",
                    AlbumArtist: album.artist,
                    Artists: [album.artist],
                    Album: nil,
                    AlbumId: nil,
                    ProductionYear: album.productionYear,
                    ImageTags: album.imageTag.map(WireImageTags.init(Primary:)),
                    IndexNumber: nil,
                    ParentIndexNumber: nil,
                    RunTimeTicks: nil
                )
            )
        }

        private static func normalized(_ value: String) -> String {
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        }
    }

    private struct WireResponse: Encodable {
        let Items: [WireItem]
        let TotalRecordCount: Int
    }

    private struct WireImageTags: Encodable {
        let Primary: String
    }

    private struct WireItem: Encodable {
        let Id: String
        let Name: String
        let `Type`: String
        let AlbumArtist: String?
        let Artists: [String]?
        let Album: String?
        let AlbumId: String?
        let ProductionYear: Int?
        let ImageTags: WireImageTags?
        let IndexNumber: Int?
        let ParentIndexNumber: Int?
        let RunTimeTicks: Int64?
    }

    static func generate(_ configuration: Configuration) -> Fixture {
        var random = SplitMix64(state: configuration.seed)
        var artists = [Artist]()
        var albums = [Album]()
        var tracks = [Track]()
        var albumDetails = [AlbumDetail]()
        artists.reserveCapacity(configuration.artistCount)
        albums.reserveCapacity(configuration.artistCount * configuration.albumsPerArtist)
        tracks.reserveCapacity(
            configuration.artistCount * configuration.albumsPerArtist
                * configuration.discsPerAlbum * configuration.tracksPerDisc
        )

        for artistIndex in 0..<configuration.artistCount {
            let name: String
            if artistIndex.isMultiple(of: 19) {
                name = "Synthetic Namesake \(artistIndex % 3)"
            } else if artistIndex.isMultiple(of: 17) {
                name = "Björk 東京 Καλλιτέχνης \(artistIndex)"
            } else {
                name = "Synthetic Artist \(padded(artistIndex)) \(random.word())"
            }
            artists.append(
                Artist(
                    id: "artist-\(padded(artistIndex))",
                    name: name,
                    imageTag: artistIndex.isMultiple(of: 7) ? nil : "artist-art-\(random.word())"
                )
            )
        }

        var globalTrackIndex = 0
        for artistIndex in artists.indices {
            for localAlbumIndex in 0..<configuration.albumsPerArtist {
                let albumIndex = artistIndex * configuration.albumsPerArtist + localAlbumIndex
                let isCompilation = albumIndex.isMultiple(of: 11)
                let name: String
                if albumIndex.isMultiple(of: 13) {
                    name = "Synthetic Shared Album \(albumIndex % 4)"
                } else if albumIndex.isMultiple(of: 23) {
                    name = "Échos 日本語 \(albumIndex)"
                } else {
                    name = "Synthetic Album \(padded(albumIndex)) \(random.word())"
                }
                let id = "album-\(padded(albumIndex))"
                let albumArtist = isCompilation ? "Various Artists" : artists[artistIndex].name
                albums.append(
                    Album(
                        id: id,
                        name: name,
                        artist: albumArtist,
                        productionYear: albumIndex.isMultiple(of: 9) ? nil : 1950 + Int(random.next() % 77),
                        imageTag: albumIndex.isMultiple(of: 6) ? nil : "album-art-\(random.word())"
                    )
                )
                albumDetails.append(
                    AlbumDetail(
                        id: id,
                        artistID: artists[artistIndex].id,
                        discCount: configuration.discsPerAlbum,
                        isCompilation: isCompilation
                    )
                )

                for disc in 1...configuration.discsPerAlbum {
                    for index in 1...configuration.tracksPerDisc {
                        let trackArtist = isCompilation
                            ? artists[(artistIndex + disc + index) % artists.count].name
                            : albumArtist
                        let trackName: String
                        if globalTrackIndex.isMultiple(of: 17) {
                            trackName = "Synthetic Reprise"
                        } else if globalTrackIndex.isMultiple(of: 41) {
                            trackName = "Canción 星 \(globalTrackIndex)"
                        } else {
                            trackName = "Synthetic Track \(padded(globalTrackIndex)) \(random.word())"
                        }
                        tracks.append(
                            Track(
                                id: "track-\(padded(globalTrackIndex, width: 7))",
                                name: trackName,
                                artist: trackArtist,
                                album: name,
                                albumID: id,
                                index: globalTrackIndex.isMultiple(of: 29) ? nil : index,
                                disc: globalTrackIndex.isMultiple(of: 31) ? nil : disc,
                                durationTicks: globalTrackIndex.isMultiple(of: 37)
                                    ? nil
                                    : Int64(900 + random.next() % 720) * 10_000_000
                            )
                        )
                        globalTrackIndex += 1
                    }
                }
            }
        }

        let payload = CanonicalPayload(
            format: "jellytone-large-music-library/v\(configuration.version)",
            configuration: configuration,
            artists: artists,
            albums: albums,
            tracks: tracks,
            albumDetails: albumDetails
        )
        let canonicalBytes = canonicalData(payload)
        let hash = SHA256.hash(data: canonicalBytes).map { byte in
            let encoded = String(byte, radix: 16, uppercase: false)
            return encoded.count == 1 ? "0" + encoded : encoded
        }.joined()
        let compilationAlbumIDs = albumDetails.filter(\.isCompilation).map(\.id)
        let metadata = Metadata(
            formatVersion: configuration.version,
            seed: configuration.seed,
            sha256: hash,
            artistCount: artists.count,
            albumCount: albums.count,
            trackCount: tracks.count,
            compilationAlbumCount: compilationAlbumIDs.count,
            multiDiscAlbumCount: configuration.discsPerAlbum > 1 ? albums.count : 0,
            missingArtistArtworkCount: artists.count(where: { $0.imageTag == nil }),
            missingAlbumArtworkCount: albums.count(where: { $0.imageTag == nil }),
            missingAlbumMetadataCount: albums.count(where: { $0.productionYear == nil }),
            missingTrackMetadataCount: tracks.count(where: {
                $0.index == nil || $0.disc == nil || $0.durationTicks == nil
            }),
            duplicateArtistNameCount: duplicateEntryCount(artists.map(\.name)),
            duplicateAlbumNameCount: duplicateEntryCount(albums.map(\.name)),
            unicodeNameCount: unicodeCount(artists.map(\.name) + albums.map(\.name) + tracks.map(\.name))
        )
        return Fixture(
            configuration: configuration,
            metadata: metadata,
            artists: artists,
            albums: albums,
            tracks: tracks,
            albumDetails: albumDetails,
            compilationAlbumIDs: compilationAlbumIDs,
            canonicalBytes: canonicalBytes
        )
    }

    private struct CanonicalPayload: Encodable {
        let format: String
        let configuration: Configuration
        let artists: [Artist]
        let albums: [Album]
        let tracks: [Track]
        let albumDetails: [AlbumDetail]
    }

    private struct SplitMix64 {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func word() -> String {
            String(next(), radix: 16, uppercase: false)
        }
    }

    private static func canonicalData<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try! encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private static func padded(_ value: Int, width: Int = 5) -> String {
        let digits = String(value, radix: 10)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func duplicateEntryCount(_ names: [String]) -> Int {
        let sorted = names.sorted(by: unicodeScalarPrecedes)
        var count = 0
        var start = 0
        while start < sorted.count {
            var end = start + 1
            while end < sorted.count && sorted[end] == sorted[start] { end += 1 }
            if end - start > 1 { count += end - start }
            start = end
        }
        return count
    }

    private static func unicodeCount(_ names: [String]) -> Int {
        names.count { $0.unicodeScalars.contains(where: { $0.value > 0x7f }) }
    }

    private static func unicodeScalarPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars, by: { $0.value < $1.value })
    }
}
