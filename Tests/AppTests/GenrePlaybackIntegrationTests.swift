import Foundation
import XCTest
@testable import Jellytone

@MainActor
final class GenrePlaybackIntegrationTests: XCTestCase {
    func testSelectedDuplicateOccurrenceBuildsDistinctQueueAndStartsAtSelectedOccurrence() throws {
        let playback = try makePlayback()
        let occurrences = duplicateOccurrences()
        let entries = queueEntries(for: occurrences)
        let api = try makeAPI()

        playback.play(
            entries: entries,
            startingAt: entries[1].id,
            using: api,
            userID: "synthetic-user",
            scope: "synthetic-server:synthetic-user"
        )

        XCTAssertEqual(playback.queue.map(\.track.id), occurrences.map(\.track.id))
        XCTAssertEqual(playback.queue.map(\.id), entries.map(\.id))
        XCTAssertEqual(Set(playback.queue.map(\.id)).count, occurrences.count)
        XCTAssertEqual(playback.currentIndex, 1)
        XCTAssertEqual(playback.queue[playback.currentIndex].id, entries[1].id)
    }

    func testPlayAllStartsAtFirstPlayableGenreOccurrence() throws {
        let playback = try makePlayback()
        let occurrences = duplicateOccurrences()
        let entries = queueEntries(for: occurrences)

        playback.play(
            entries: entries,
            startingAt: entries[0].id,
            using: try makeAPI(),
            userID: "synthetic-user",
            scope: "synthetic-server:synthetic-user"
        )

        XCTAssertEqual(playback.currentIndex, 0)
        XCTAssertEqual(playback.queue.first?.id, entries.first?.id)
        XCTAssertEqual(playback.currentTrack, occurrences.first?.track)
    }

    func testGenreShuffleUsesAuthoritativeControllerAndKeepsCurrentOccurrenceStable() throws {
        let playback = try makePlayback()
        let occurrences = duplicateOccurrences()
        let entries = queueEntries(for: occurrences)

        playback.play(
            entries: entries,
            startingAt: entries[0].id,
            using: try makeAPI(),
            userID: "synthetic-user",
            scope: "synthetic-server:synthetic-user"
        )
        let selectedOccurrenceID = try XCTUnwrap(playback.queue.first?.id)

        playback.toggleShuffle()

        XCTAssertTrue(playback.isShuffled)
        XCTAssertEqual(playback.currentIndex, 0)
        XCTAssertEqual(playback.queue[playback.currentIndex].id, selectedOccurrenceID)
        XCTAssertEqual(Set(playback.queue.map(\.id)), Set(entries.map(\.id)))
        XCTAssertEqual(playback.queue.count, occurrences.count)
        XCTAssertEqual(playback.queue.filter { $0.track.id == "track-duplicate" }.count, 2)
    }

    private let defaultsSuiteName = "GenrePlaybackIntegrationTests"

    private func makePlayback() throws -> PlaybackController {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: self.defaultsSuiteName) }
        return PlaybackController(
            defaults: defaults,
            audioSession: GenreAudioSession(),
            remoteCommands: GenreRemoteCommands()
        )
    }

    private func makeAPI() throws -> JellyfinAPI {
        JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid/jellyfin")),
            deviceID: "synthetic-device",
            token: "synthetic-token"
        )
    }

    private func queueEntries(for occurrences: [GenreTrackOccurrence]) -> [QueueEntry] {
        occurrences.enumerated().map { index, occurrence in
            QueueEntry(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                track: occurrence.track
            )
        }
    }

    private func duplicateOccurrences() -> [GenreTrackOccurrence] {
        let duplicate = Track(
            id: "track-duplicate",
            name: "Repeated Song",
            artist: "Synthetic Artist",
            album: "Synthetic Album",
            index: nil,
            disc: nil,
            durationTicks: 100_000_000
        )
        return [
            GenreTrackOccurrence(id: "genre-occurrence-1", track: duplicate),
            GenreTrackOccurrence(id: "genre-occurrence-2", track: duplicate),
            GenreTrackOccurrence(id: "genre-occurrence-3", track: Track(
                id: "track-last",
                name: "Last Song",
                artist: "Synthetic Artist",
                album: "Synthetic Album",
                index: nil,
                disc: nil,
                durationTicks: 100_000_000
            )),
        ]
    }
}

@MainActor
private struct GenreAudioSession: AudioSessionManaging {
    func activateForPlayback() throws {}
    func deactivateAfterPlayback() throws {}
}

@MainActor
private final class GenreRemoteCommands: RemoteCommandRouting {
    func register(handler: @escaping @MainActor (PlaybackRemoteCommand) -> Void) {}
    func updateAvailability(canGoPrevious: Bool, canGoNext: Bool) {}
}
