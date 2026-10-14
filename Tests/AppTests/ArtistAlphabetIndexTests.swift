import XCTest
@testable import Jellytone

final class ArtistAlphabetIndexTests: XCTestCase {
    func testRailAlwaysOffersTheFullAlphabetWithTrailingNumberBucket() {
        XCTAssertEqual(ArtistAlphabetIndex.letters.count, 27)
        XCTAssertEqual(ArtistAlphabetIndex.letters.first, "A")
        XCTAssertEqual(ArtistAlphabetIndex.letters[25], "Z")
        XCTAssertEqual(ArtistAlphabetIndex.letters.last, ArtistAlphabetIndex.numberSection)
    }

    func testSectionLetterFoldsDiacriticsCaseAndBucketsNonLatinNames() {
        XCTAssertEqual(ArtistAlphabetIndex.sectionLetter(for: artist("a", name: "Björk")), "B")
        XCTAssertEqual(ArtistAlphabetIndex.sectionLetter(for: artist("b", name: "Élise")), "E")
        XCTAssertEqual(ArtistAlphabetIndex.sectionLetter(for: artist("c", name: "aurora")), "A")
        XCTAssertEqual(ArtistAlphabetIndex.sectionLetter(for: artist("d", name: "2Pac")), "#")
        XCTAssertEqual(ArtistAlphabetIndex.sectionLetter(for: artist("e", name: "!!!")), "#")
        XCTAssertEqual(ArtistAlphabetIndex.sectionLetter(for: artist("f", name: "坂本龍一")), "#")
    }

    func testSectionLetterPrefersServerSortNameAndIgnoresBlankSortNames() {
        XCTAssertEqual(
            ArtistAlphabetIndex.sectionLetter(for: artist("a", name: "The Beatles", sortName: "Beatles")),
            "B"
        )
        XCTAssertEqual(
            ArtistAlphabetIndex.sectionLetter(for: artist("b", name: "Mogwai", sortName: "   ")),
            "M"
        )
    }

    func testTargetJumpsToExactSectionOrNearestFollowingSection() {
        let artists = [
            artist("numeric", name: "2Pac"),
            artist("abba", name: "ABBA"),
            artist("beatles", name: "The Beatles", sortName: "Beatles"),
            artist("mogwai", name: "Mogwai"),
        ]

        XCTAssertEqual(ArtistAlphabetIndex.target(for: "A", in: artists)?.id, "abba")
        XCTAssertEqual(ArtistAlphabetIndex.target(for: "B", in: artists)?.id, "beatles")
        XCTAssertEqual(ArtistAlphabetIndex.target(for: "C", in: artists)?.id, "mogwai",
                       "An empty letter lands on the nearest following section")
        XCTAssertEqual(ArtistAlphabetIndex.target(for: "Z", in: artists)?.id, "mogwai",
                       "Letters past the last section land on the end of the list")
        XCTAssertEqual(ArtistAlphabetIndex.target(for: "#", in: artists)?.id, "numeric",
                       "The number bucket matches exactly even though it collates to the top")
    }

    func testTargetHandlesEmptyAndAllNumericLists() {
        XCTAssertNil(ArtistAlphabetIndex.target(for: "A", in: []))
        let numericOnly = [artist("numeric", name: "999")]
        XCTAssertEqual(ArtistAlphabetIndex.target(for: "#", in: numericOnly)?.id, "numeric")
        XCTAssertEqual(ArtistAlphabetIndex.target(for: "K", in: numericOnly)?.id, "numeric",
                       "A list with no letter sections still lands somewhere deterministic")
    }

    private func artist(_ id: String, name: String, sortName: String? = nil) -> Artist {
        Artist(id: id, name: name, imageTag: nil, sortName: sortName)
    }
}
