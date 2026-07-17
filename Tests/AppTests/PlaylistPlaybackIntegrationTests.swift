import Foundation
import XCTest
@testable import JellyfinAudio

@MainActor
final class PlaylistPlaybackIntegrationTests: XCTestCase {
    func testOccurrenceAwarePlaybackStartsAtSelectedDuplicate() throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let playback = PlaybackController(
            defaults: defaults,
            audioSession: PlaylistAudioSession(),
            remoteCommands: PlaylistRemoteCommands()
        )
        let duplicate = Track(
            id: "track-duplicate",
            name: "Repeated",
            artist: "Synthetic Artist",
            album: "Synthetic Album",
            index: nil,
            disc: nil,
            durationTicks: 100_000_000
        )
        let entries = [
            QueueEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, track: duplicate),
            QueueEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, track: duplicate),
            QueueEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, track: duplicate),
        ]
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid/jellyfin")),
            deviceID: "synthetic-device",
            token: "synthetic-token"
        )

        playback.play(
            entries: entries,
            startingAt: entries[1].id,
            using: api,
            userID: "synthetic-user",
            scope: "synthetic-server:synthetic-user"
        )

        XCTAssertEqual(playback.queue.map(\.id), entries.map(\.id))
        XCTAssertEqual(playback.currentIndex, 1)
        XCTAssertEqual(playback.queue[playback.currentIndex].id, entries[1].id)
    }

    private let defaultsSuiteName = "PlaylistPlaybackIntegrationTests"

    private func isolatedDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}

@MainActor
private struct PlaylistAudioSession: AudioSessionManaging {
    func activateForPlayback() throws {}
    func deactivateAfterPlayback() throws {}
}

@MainActor
private final class PlaylistRemoteCommands: RemoteCommandRouting {
    func register(handler: @escaping @MainActor (PlaybackRemoteCommand) -> Void) {}
    func updateAvailability(canGoPrevious: Bool, canGoNext: Bool) {}
}
