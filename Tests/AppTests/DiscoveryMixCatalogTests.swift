import XCTest
@testable import Jellytone

final class DiscoveryMixCatalogTests: XCTestCase {
    func testFavouriteArtistsLeadTheShelfAndRecentlyPlayedFillsDistinctSeeds() {
        let favourites = [
            Artist(id: "artist-a", name: "Aurora", imageTag: "tag-a"),
            Artist(id: "artist-b", name: "Björk", imageTag: nil),
        ]
        let recent = [
            Track(
                id: "track-a1", name: "Opening Light", artist: "Aurora", album: "Lines",
                albumID: "album-a", index: 1, disc: 1, durationTicks: 1_000,
                artistID: "artist-a", imageTag: "from-track"
            ),
            Track(
                id: "track-c1", name: "Because You Listened Seed", artist: "Other", album: "Other Album",
                albumID: "album-c", index: 1, disc: 1, durationTicks: 1_000,
                artistID: "artist-c"
            ),
            Track(
                id: "track-orphan", name: "No Artist ID", artist: "Unknown", album: "Loose",
                index: nil, disc: nil, durationTicks: nil
            ),
        ]

        let mixes = DiscoveryMixCatalog.make(
            favouriteArtists: favourites,
            recentlyPlayedTracks: recent
        )

        XCTAssertEqual(mixes.map(\.id), [
            "mix-artist-artist-a",
            "mix-artist-artist-b",
            "mix-artist-artist-c",
            "mix-track-track-orphan",
        ])
        XCTAssertEqual(mixes[0].seedKind, .artist)
        XCTAssertEqual(mixes[0].seedItemID, "artist-a")
        XCTAssertEqual(mixes[0].subtitle, "Made for You")
        XCTAssertEqual(mixes[2].subtitle, "Because You Listened")
        XCTAssertEqual(mixes[3].seedKind, .track)
        XCTAssertEqual(mixes[3].seedItemID, "track-orphan")
    }

    func testShelfStopsAtLimitEvenWhenMoreSeedsExist() {
        let artists = (0..<10).map { Artist(id: "artist-\($0)", name: "Artist \($0)", imageTag: nil) }
        let mixes = DiscoveryMixCatalog.make(favouriteArtists: artists, recentlyPlayedTracks: [])
        XCTAssertEqual(mixes.count, DiscoveryMixCatalog.shelfLimit)
        XCTAssertEqual(mixes.last?.seedItemID, "artist-7")
    }

    func testUpcomingDropsTheAlreadyPlayingSeedSoMixExpansionDoesNotRestart() {
        let seed = Track(
            id: "seed", name: "Seed", artist: "Artist", album: "Album",
            index: 1, disc: 1, durationTicks: 1_000
        )
        let mix = [
            seed,
            Track(id: "next", name: "Next", artist: "Artist", album: "Album",
                  index: 2, disc: 1, durationTicks: 1_000),
            Track(id: "seed", name: "Seed duplicate row", artist: "Artist", album: "Album",
                  index: 3, disc: 1, durationTicks: 1_000),
        ]
        XCTAssertEqual(DiscoveryMixQueue.upcoming(from: mix, playing: seed).map(\.id), ["next"])
    }
}
