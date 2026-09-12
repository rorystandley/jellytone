import Foundation
import MediaPlayer
import UIKit
import XCTest
@testable import Jellytone

final class MinimumWorkingAppTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testTrackDurationUsesJellyfinTicks() {
        let track = Track(id: "track", name: "Synthetic", artist: "Artist", album: "Album",
                          index: 1, disc: 1, durationTicks: 1_250_000_000)
        XCTAssertEqual(track.duration, 125)
        XCTAssertEqual(track.durationLabel, "2:05")
    }

    func testTrackExposesAlbumAndArtistDestinationsOnlyWhenItemIDsExist() {
        let linked = Track(
            id: "track", name: "Song", artist: "Artist", album: "Album",
            albumID: "album-1", index: 1, disc: 1, durationTicks: nil,
            artistID: "artist-1", imageTag: "art"
        )
        XCTAssertEqual(linked.albumDestination, Album(id: "album-1", name: "Album", artist: "Artist",
                                                     productionYear: nil, imageTag: "art"))
        XCTAssertEqual(linked.artistDestination, Artist(id: "artist-1", name: "Artist", imageTag: nil))

        let namesOnly = Track(id: "track", name: "Song", artist: "Artist", album: "Album",
                              index: nil, disc: nil, durationTicks: nil)
        XCTAssertNil(namesOnly.albumDestination)
        XCTAssertNil(namesOnly.artistDestination)

        let emptyNames = Track(
            id: "track", name: "Song", artist: "", album: "",
            albumID: "album-1", index: nil, disc: nil, durationTicks: nil, artistID: "artist-1"
        )
        XCTAssertNil(emptyNames.albumDestination)
        XCTAssertNil(emptyNames.artistDestination)
    }

    func testAppearancePreferenceMapsToTheExpectedColorScheme() {
        XCTAssertNil(AppearancePreference.system.colorScheme)
        XCTAssertEqual(AppearancePreference.light.colorScheme, .light)
        XCTAssertEqual(AppearancePreference.dark.colorScheme, .dark)
        XCTAssertEqual(AppearancePreference.allCases.map(\.title), ["System", "Light", "Dark"])
    }

    func testArtworkRequestPreservesReverseProxyBasePathAndUsesHeaderToken() throws {
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
            deviceID: "synthetic-device",
            token: "synthetic-token"
        )
        let request = try api.artworkRequest(itemID: "album")
        XCTAssertEqual(request.url?.path, "/jellyfin/Items/album/Images/Primary")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-token")
        XCTAssertFalse(request.url?.absoluteString.contains("synthetic-token") == true)
    }

    func testStreamURLPreservesBasePathAndCarriesTokenOnlyForAVPlayer() throws {
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/base")),
            deviceID: "synthetic-device",
            token: "synthetic-token"
        )
        let components = try XCTUnwrap(URLComponents(url: api.streamURL(itemID: "track"), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/base/Audio/track/stream")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api_key" })?.value, "synthetic-token")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "static" })?.value, "true")
    }

    func testAuthenticationMapsTokenAndUserWithoutLoggingCredentials() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/jellyfin/Users/AuthenticateByName")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.contains("synthetic-device") == true)
            let body = try Self.bodyData(from: request)
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: body) as? NSDictionary,
                ["Username": "listener", "Pw": "temporary-password"]
            )
            return Self.response(
                for: request,
                json: #"{"AccessToken":"synthetic-token","User":{"Id":"user-id","Name":"Listener"}}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
                              deviceID: "synthetic-device", urlSession: makeSession())
        let result = try await api.authenticate(username: "listener", password: "temporary-password")
        XCTAssertEqual(result.token, "synthetic-token")
        XCTAssertEqual(result.userID, "user-id")
        XCTAssertEqual(result.username, "Listener")
    }

    func testMusicViewsFilterOutNonMusicLibraries() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                json: #"{"Items":[{"Id":"music","Name":"Music","CollectionType":"music"},{"Id":"movies","Name":"Movies","CollectionType":"movies"}]}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "synthetic-device", token: "token", urlSession: makeSession())
        let libraries = try await api.musicLibraries(userID: "user")
        XCTAssertEqual(libraries, [MusicLibrary(id: "music", name: "Music")])
    }

    func testGlobalAlbumFallbackUsesCurrentItemsEndpoint() async throws {
        MockURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/jellyfin/Items")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "userId" })?.value, "user")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "IncludeItemTypes" })?.value, "MusicAlbum")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "Limit" })?.value, "100")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "EnableTotalRecordCount" })?.value, "false")
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "ParentId" }))
            return Self.response(
                for: request,
                json: #"{"Items":[{"Id":"album","Name":"Synthetic Album","AlbumArtist":"Synthetic Artist"}]}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
                              deviceID: "synthetic-device", token: "token", urlSession: makeSession())
        let page = try await api.albums(userID: "user", libraryID: nil)
        XCTAssertEqual(page.albums.first?.name, "Synthetic Album")
        XCTAssertEqual(page.albums.first?.artist, "Synthetic Artist")
        XCTAssertFalse(page.hasMore)
    }

    func testMusicSearchConstructsScopedMusicOnlyPagedRequestAndMapsResults() async throws {
        MockURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            XCTAssertEqual(components.path, "/jellyfin/Items")
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(query["userId"], "user")
            XCTAssertEqual(query["ParentId"], "music-library")
            XCTAssertEqual(query["SearchTerm"], "Björk & Friends")
            XCTAssertEqual(query["IncludeItemTypes"], "MusicArtist,MusicAlbum,Audio")
            XCTAssertEqual(query["Recursive"], "true")
            XCTAssertEqual(query["StartIndex"], "40")
            XCTAssertEqual(query["Limit"], "40")
            XCTAssertEqual(query["EnableTotalRecordCount"], "true")
            return Self.response(
                for: request,
                json: #"{"Items":[{"Id":"artist","Name":"Björk","Type":"MusicArtist","ImageTags":{"Primary":"artist-tag"}},{"Id":"album","Name":"Debut","Type":"MusicAlbum","AlbumArtist":"Björk","ProductionYear":1993,"ImageTags":{"Primary":"album-tag"}},{"Id":"track","Name":"Venus as a Boy","Type":"Audio","Artists":["Björk"],"Album":"Debut","AlbumId":"album","RunTimeTicks":2100000000},{"Id":"video","Name":"Private Music Video","Type":"Video"}],"TotalRecordCount":50}"#
            )
        }
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
            deviceID: "synthetic-device",
            token: "token",
            urlSession: makeSession()
        )

        // startIndex > 0 skips the companion playlist request (first-page only).
        let page = try await api.searchMusic(
            userID: "user",
            libraryID: "music-library",
            query: "Björk & Friends",
            startIndex: 40
        )

        XCTAssertEqual(page.artists, [Artist(id: "artist", name: "Björk", imageTag: "artist-tag")])
        XCTAssertEqual(
            page.albums,
            [Album(id: "album", name: "Debut", artist: "Björk", productionYear: 1993, imageTag: "album-tag")]
        )
        XCTAssertEqual(page.tracks.map(\.id), ["track"])
        XCTAssertEqual(page.tracks.first?.name, "Venus as a Boy")
        XCTAssertTrue(page.playlists.isEmpty)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextStartIndex, 44)
    }

    func testArtistAlbumsUseArtistIdentityAndMapOnlyMusicAlbums() async throws {
        MockURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(components.path, "/base/Items")
            XCTAssertEqual(query["ArtistIds"], "artist-id")
            XCTAssertEqual(query["ParentId"], "music-library")
            XCTAssertEqual(query["IncludeItemTypes"], "MusicAlbum")
            XCTAssertEqual(query["StartIndex"], "50")
            return Self.response(
                for: request,
                json: #"{"Items":[{"Id":"album","Name":"Post","Type":"MusicAlbum","Artists":["Björk"]},{"Id":"audio","Name":"Track","Type":"Audio"}],"TotalRecordCount":52}"#
            )
        }
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/base")),
            deviceID: "device",
            token: "token",
            urlSession: makeSession()
        )

        let page = try await api.albums(
            userID: "user",
            artistID: "artist-id",
            libraryID: "music-library",
            startIndex: 50
        )

        XCTAssertEqual(page.albums.map(\.id), ["album"])
        XCTAssertEqual(page.albums.first?.artist, "Björk")
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.nextStartIndex, 52)
    }

    @MainActor
    func testCancelledSearchDoesNotPublishResultsOrAnError() async {
        let controller = MusicSearchController()
        let task = Task {
            await controller.search(query: "cancel me", debounceNanoseconds: 0) { _, _, _ in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    // URLSession commonly surfaces cancellation as URLError.cancelled.
                    throw URLError(.cancelled)
                }
                return Self.searchPage(named: "Never")
            }
        }

        await Task.yield()
        task.cancel()
        await task.value

        XCTAssertTrue(controller.isEmpty)
        XCTAssertNil(controller.errorMessage)
        XCTAssertFalse(controller.isLoading)
    }

    @MainActor
    func testStaleSearchCannotReplaceNewerResults() async {
        let controller = MusicSearchController()
        let loader = ControlledSearchLoader()
        let oldSearch = Task {
            await controller.search(query: "old", debounceNanoseconds: 0) { query, _, _ in
                await loader.load(query: query)
            }
        }
        await loader.waitUntilOldStarted()

        await controller.search(query: "new", debounceNanoseconds: 0) { query, _, _ in
            await loader.load(query: query)
        }
        await loader.releaseOld()
        await oldSearch.value

        XCTAssertEqual(controller.query, "new")
        XCTAssertEqual(controller.albums.map(\.name), ["New"])
        XCTAssertEqual(controller.artists.map(\.name), ["New Artist"])
    }

    func testPlaybackInfoSelectsSupportedDirectSource() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/jellyfin/Items/track/PlaybackInfo")
            return Self.response(
                for: request,
                json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"session"}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let plan = try await api.playbackPlan(itemID: "track", userID: "user")
        XCTAssertEqual(plan.method, .directPlay)
        XCTAssertEqual(plan.url.path, "/jellyfin/Audio/track/stream")
        let query = try XCTUnwrap(URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "mediaSourceId" })?.value, "source")
        XCTAssertEqual(query.first(where: { $0.name == "playSessionId" })?.value, "session")
    }

    func testPlaybackInfoFallsBackToProvenAACTranscode() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                json: #"{"MediaSources":[{"Id":"source","Container":"wma","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"wmav2"}]}],"PlaySessionId":"session"}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let plan = try await api.playbackPlan(itemID: "track", userID: "user")
        XCTAssertEqual(plan.method, .transcode)
        XCTAssertEqual(plan.url.path, "/Audio/track/universal")
        let query = try XCTUnwrap(URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "audioCodec" })?.value, "aac")
        XCTAssertEqual(query.first(where: { $0.name == "enableDirectPlay" })?.value, "false")
    }

    func testPlaybackStartReportUsesJellyfinTicks() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/Sessions/Playing")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["PlayMethod"] as? String, "DirectPlay")
            XCTAssertEqual(json["PositionTicks"] as? Int64, 125_000_000)
            XCTAssertEqual(json["IsPaused"] as? Bool, false)
            return Self.response(for: request, status: 204, json: "")
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let plan = PlaybackPlan(url: try XCTUnwrap(URL(string: "https://example.com/audio")),
                                mediaSourceID: "source", playSessionID: "session", method: .directPlay)
        await api.reportStarted(itemID: "track", plan: plan, position: 12.5, paused: false)
    }

    func testPlaybackReportingFailureReturnsBoundedObservableOutcome() async throws {
        MockURLProtocol.handler = { request in
            Self.response(for: request, status: 503, json: "")
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://private.example.invalid")),
                              deviceID: "device", token: "private-token", urlSession: makeSession())
        let plan = PlaybackPlan(url: try XCTUnwrap(URL(string: "https://private.example.invalid/audio?api_key=private")),
                                mediaSourceID: "private-source", playSessionID: "private-session",
                                method: .directPlay)

        let outcome = await api.reportProgress(
            itemID: "private-item",
            plan: plan,
            position: 12.5,
            paused: true
        )

        XCTAssertEqual(outcome.failure?.kind, .server)
        XCTAssertNotEqual(outcome, .accepted(status: 503))
    }

    func testPlaybackSnapshotRoundTripsQueueAndPosition() throws {
        let track = Track(id: "track", name: "Track", artist: "Artist", album: "Album",
                          albumID: "album", index: 1, disc: 1, durationTicks: 600_000_000)
        let snapshot = PlaybackSnapshot(
            scope: "server:user",
            queue: [QueueEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, track: track)],
            currentIndex: 0,
            position: 42.5
        )
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testLegacyPlaybackSnapshotDefaultsNewQueueControls() throws {
        let data = Data(#"{"scope":"server:user","queue":[],"currentIndex":0,"position":12.5}"#.utf8)
        let snapshot = try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        XCTAssertEqual(snapshot.originalQueue, [])
        XCTAssertFalse(snapshot.isShuffled)
        XCTAssertEqual(snapshot.repeatMode, .off)
    }

    func testQueueShuffleKeepsCurrentTrackAndAllEntries() {
        let tracks = (1...4).map { (number: Int) in
            Track(id: "\(number)", name: "Track \(number)", artist: "Artist", album: "Album",
                  index: number, disc: 1, durationTicks: 10_000_000)
        }
        let entries = tracks.map { QueueEntry(track: $0) }
        var generator = SeededGenerator(state: 42)
        let shuffled = QueueOrder.shuffled(entries, currentIndex: 2, using: &generator)
        XCTAssertEqual(Array(shuffled.prefix(3)), Array(entries.prefix(3)))
        XCTAssertEqual(Set(shuffled), Set(entries))
        XCTAssertEqual(shuffled.count, entries.count)
    }

    func testLegacySnapshotMigratesDuplicateTracksToDistinctStableEntries() throws {
        let track = Track(id: "duplicate", name: "Same", artist: "Artist", album: "Album",
                          index: 1, disc: 1, durationTicks: 10_000_000)
        let legacyQueue = try String(data: JSONEncoder().encode([track, track]), encoding: .utf8).map {
            #"{"scope":"server:user","queue":\#($0),"currentIndex":0,"position":0,"originalQueue":\#($0),"isShuffled":true,"repeatMode":"all"}"#
        }
        let migrated = try JSONDecoder().decode(PlaybackSnapshot.self, from: Data(XCTUnwrap(legacyQueue).utf8))

        XCTAssertEqual(migrated.queue.map(\.track), [track, track])
        XCTAssertEqual(Set(migrated.queue.map(\.id)).count, 2)
        XCTAssertEqual(migrated.queue.map(\.id), migrated.originalQueue.map(\.id))
        XCTAssertTrue(migrated.isShuffled)
        XCTAssertEqual(migrated.repeatMode, .all)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any])
    }

    func testRepeatModeCyclesThroughEveryState() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }

    @MainActor
    func testQueueJumpReorderRemoveAndClearUseEntryIdentityAndPersistAtomically() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let playback = PlaybackController(
            defaults: defaults,
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let duplicate = Track(id: "duplicate", name: "Duplicate", artist: "Artist", album: "Album",
                              index: 2, disc: 1, durationTicks: 10_000_000)
        let tracks = [
            Track(id: "current", name: "Current", artist: "Artist", album: "Album",
                  index: 1, disc: 1, durationTicks: 10_000_000),
            duplicate,
            duplicate,
            Track(id: "last", name: "Last", artist: "Artist", album: "Album",
                  index: 4, disc: 1, durationTicks: 10_000_000),
        ]
        playback.configureForLifecycleTesting(queue: tracks, currentIndex: 0, elapsed: 0, isPlaying: false)
        let firstDuplicateID = playback.upcomingEntries[0].id
        let secondDuplicateID = playback.upcomingEntries[1].id
        XCTAssertNotEqual(firstDuplicateID, secondDuplicateID)

        playback.moveUpcoming(entryID: secondDuplicateID, by: -1)
        XCTAssertEqual(Array(playback.upcomingEntries.map(\.id).prefix(2)), [secondDuplicateID, firstDuplicateID])
        playback.removeUpcoming(entryIDs: [firstDuplicateID])
        XCTAssertEqual(playback.queue.filter { $0.track == duplicate }.map(\.id), [secondDuplicateID])

        let lastID = try XCTUnwrap(playback.upcomingEntries.last?.id)
        playback.jump(to: lastID)
        XCTAssertEqual(playback.queue[playback.currentIndex].id, lastID)
        XCTAssertEqual(playback.currentTrack, tracks[3])

        playback.configureForLifecycleTesting(queue: tracks, currentIndex: 0, elapsed: 0, isPlaying: false)
        playback.clearUpNext()
        XCTAssertTrue(playback.upcomingEntries.isEmpty)
        XCTAssertEqual(playback.queue.map(\.track), [tracks[0]])

        playback.configureForLifecycleTesting(queue: tracks, currentIndex: 0, elapsed: 0, isPlaying: true)
        let mixRest = [
            Track(id: "mix-a", name: "Mix A", artist: "Artist", album: "Album",
                  index: 1, disc: 1, durationTicks: 10_000_000),
            Track(id: "mix-b", name: "Mix B", artist: "Artist", album: "Album",
                  index: 2, disc: 1, durationTicks: 10_000_000),
        ]
        playback.replaceUpcoming(with: mixRest)
        XCTAssertEqual(playback.currentTrack, tracks[0])
        XCTAssertEqual(playback.queue.map(\.track.id), ["current", "mix-a", "mix-b"])
        XCTAssertTrue(playback.canGoNext)
        XCTAssertTrue(playback.isPlaying)

        let data = try XCTUnwrap(defaults.data(forKey: "active-playback-snapshot-v1"))
        let snapshot = try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        XCTAssertEqual(snapshot.queue, playback.queue)
        XCTAssertEqual(snapshot.currentIndex, playback.currentIndex)
    }

    @MainActor
    func testEditingShuffledQueueCommitsVisibleOrderAndRepeatBoundaryRemainsAvailable() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let commands = RecordingRemoteCommandRouter()
        let playback = PlaybackController(
            defaults: defaults,
            audioSession: RecordingAudioSession(),
            remoteCommands: commands,
            notificationCenter: NotificationCenter()
        )
        playback.configureForLifecycleTesting(queue: Self.queueTracks(), currentIndex: 0, elapsed: 0, isPlaying: false)
        playback.toggleShuffle()
        XCTAssertTrue(playback.isShuffled)
        let visible = playback.queue

        playback.moveUpcoming(entryID: playback.upcomingEntries[0].id, by: 1)
        XCTAssertFalse(playback.isShuffled)
        XCTAssertNotEqual(playback.queue, visible)

        playback.cycleRepeatMode()
        XCTAssertEqual(playback.repeatMode, .all)
        playback.jump(to: playback.queue[2].id)
        playback.clearUpNext()
        XCTAssertEqual(playback.queue.count, 1)
        XCTAssertEqual(playback.currentIndex, 0)
        XCTAssertFalse(playback.canGoNext)
        XCTAssertEqual(commands.lastAvailability, .init(canGoPrevious: false, canGoNext: true))
        playback.next()
        XCTAssertEqual(playback.currentIndex, 0)
    }

    @MainActor
    func testSnapshotRestorationPreservesEntryIdentityAndCurrentOccurrence() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path.contains("PlaybackInfo") == true {
                return Self.response(
                    for: request,
                    json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"restored-session"}"#
                )
            }
            return Self.response(for: request, status: 204, json: "")
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let tracks = Self.queueTracks()
        let entries = tracks.map { QueueEntry(track: $0) }
        defaults.set(
            try JSONEncoder().encode(PlaybackSnapshot(
                scope: "server:user",
                queue: entries,
                currentIndex: 2,
                position: 0,
                originalQueue: entries,
                isShuffled: false,
                repeatMode: .one
            )),
            forKey: "active-playback-snapshot-v1"
        )
        let playback = PlaybackController(
            defaults: defaults,
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())

        playback.restore(using: api, userID: "user", scope: "server:user")
        for _ in 0..<200 where playback.isPreparing { try await Task.sleep(for: .milliseconds(5)) }

        XCTAssertFalse(playback.isPreparing)
        XCTAssertEqual(playback.queue.map(\.id), entries.map(\.id))
        XCTAssertEqual(playback.currentIndex, 2)
        XCTAssertEqual(playback.currentTrack, tracks[2])
        XCTAssertEqual(playback.repeatMode, .one)
    }

    @MainActor
    func testRapidQueueJumpsCloseStartedSessionBeforeStartingFinalTrackExactlyOnce() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("PlaybackInfo") {
                let itemID = path.split(separator: "/").dropLast().last.map(String.init) ?? "unknown"
                return Self.response(
                    for: request,
                    json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"session-\#(itemID)"}"#
                )
            }
            if path.contains("/Sessions/Playing") {
                let body = try Self.bodyData(from: request)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let itemID = try XCTUnwrap(json["ItemId"] as? String)
                let event = path.hasSuffix("Stopped") ? "stop:\(itemID)" : "start:\(itemID)"
                recorder.append(event)
                if event == "start:queue-1" { Thread.sleep(forTimeInterval: 0.08) }
                return Self.response(for: request, status: 204, json: "")
            }
            return Self.response(for: request, status: 404, json: "")
        }
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let tracks = Self.queueTracks()
        playback.play(tracks[0], queue: tracks, using: api, userID: "user", scope: "server:user")
        for _ in 0..<200 where !recorder.contains("start:queue-1") {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(recorder.contains("start:queue-1"))

        playback.jump(to: playback.queue[1].id)
        playback.jump(to: playback.queue[2].id)
        for _ in 0..<400 where playback.isPreparing || playback.currentTrack?.id != "queue-3" {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(playback.currentTrack?.id, "queue-3")
        XCTAssertEqual(recorder.events, ["start:queue-1", "stop:queue-1", "start:queue-3"])
    }

    @MainActor
    func testFinalTrackNaturalCompletionClosesJellyfinSessionExactlyOnce() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("PlaybackInfo") {
                return Self.response(
                    for: request,
                    json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"natural-session"}"#
                )
            }
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            if path.hasSuffix("Stopped") {
                recorder.append("stop:\(json["PositionTicks"] as? Int64 ?? -1)")
            } else if path.hasSuffix("Progress") {
                recorder.append("progress")
            } else {
                recorder.append("start")
            }
            return Self.response(for: request, status: 204, json: "")
        }
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let track = Track(id: "final", name: "Final", artist: "Artist", album: "Album",
                          index: 1, disc: 1, durationTicks: 600_000_000)

        playback.play(track, queue: [track], using: api, userID: "user", scope: "server:user")
        for _ in 0..<200 where playback.isPreparing { try await Task.sleep(for: .milliseconds(5)) }
        playback.simulateNaturalCompletionForTesting()
        await playback.waitForPendingReportingForTesting()
        playback.simulateNaturalCompletionForTesting()
        await playback.waitForPendingReportingForTesting()

        XCTAssertEqual(recorder.events, ["start", "stop:600000000"])
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.elapsed, 60)
        XCTAssertNil(playback.lastReportingFailure)
    }

    @MainActor
    func testRepeatOneNaturalCompletionRestartsCurrentTrackInsteadOfAdvancingQueue() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("PlaybackInfo") {
                let itemID = path.split(separator: "/").dropLast().last.map(String.init) ?? "unknown"
                return Self.response(
                    for: request,
                    json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"repeat-\#(itemID)"}"#
                )
            }
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let itemID = try XCTUnwrap(json["ItemId"] as? String)
            recorder.append(path.hasSuffix("Stopped") ? "stop:\(itemID)" : "start:\(itemID)")
            return Self.response(for: request, status: 204, json: "")
        }
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let tracks = Self.queueTracks()

        playback.play(tracks[0], queue: tracks, using: api, userID: "user", scope: "server:user")
        for _ in 0..<200 where playback.isPreparing { try await Task.sleep(for: .milliseconds(5)) }
        playback.cycleRepeatMode()
        playback.cycleRepeatMode()
        XCTAssertEqual(playback.repeatMode, .one)

        playback.simulateNaturalCompletionForTesting()
        for _ in 0..<200 where playback.isPreparing { try await Task.sleep(for: .milliseconds(5)) }
        await playback.waitForPendingReportingForTesting()

        XCTAssertEqual(playback.currentTrack, tracks[0])
        XCTAssertEqual(playback.currentIndex, 0)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(recorder.events, ["start:queue-1", "stop:queue-1", "start:queue-1"])
    }

    @MainActor
    func testTerminalPlayerFailureClosesSessionAndExposesGenericError() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("PlaybackInfo") == true {
                return Self.response(
                    for: request,
                    json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"failure-session"}"#
                )
            }
            recorder.append(request.url?.path.hasSuffix("Stopped") == true ? "stop" : "start")
            return Self.response(for: request, status: 204, json: "")
        }
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "secret-token", urlSession: makeSession())
        let track = Track(id: "private-item", name: "Private Library Title", artist: "Private User",
                          album: "Private Album", index: 1, disc: 1, durationTicks: 600_000_000)

        playback.play(track, queue: [track], using: api, userID: "private-user", scope: "private:scope")
        for _ in 0..<200 where playback.isPreparing { try await Task.sleep(for: .milliseconds(5)) }
        playback.simulatePlaybackFailureForTesting(code: -12_000)
        await playback.waitForPendingReportingForTesting()

        XCTAssertEqual(recorder.events, ["start", "stop"])
        XCTAssertEqual(playback.errorMessage, "Playback stopped because the audio stream failed. Try again.")
        XCTAssertFalse(playback.errorMessage?.contains("Private") == true)
    }

    @MainActor
    func testNowPlayingArtworkCanBeRequestedOffMainActor() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let artwork = UncheckedSendable(value: NowPlayingArtworkFactory.make(from: image))

        let generatedImage = await Task.detached {
            artwork.value.image(at: CGSize(width: 1, height: 1)) != nil
        }.value

        XCTAssertTrue(generatedImage)
    }

    @MainActor
    func testPlaybackActivatesBackgroundAudioSessionBeforePreparingStream() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path == "/Sessions/Playing/Stopped" {
                return Self.response(for: request, status: 204, json: "")
            }
            if request.url?.path == "/Sessions/Playing" {
                return Self.response(for: request, status: 204, json: "")
            }
            XCTAssertEqual(request.url?.path, "/Items/track/PlaybackInfo")
            return Self.response(
                for: request,
                json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"session"}"#
            )
        }
        let session = RecordingAudioSession()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let playback = PlaybackController(defaults: defaults, audioSession: session)
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com")),
            deviceID: "device",
            token: "token",
            urlSession: makeSession()
        )
        let track = Track(
            id: "track",
            name: "Track",
            artist: "Artist",
            album: "Album",
            index: 1,
            disc: 1,
            durationTicks: 600_000_000
        )

        playback.play(track, queue: [track], using: api, userID: "user", scope: "server:user")
        await playback.waitForPendingReportingForTesting()

        XCTAssertEqual(session.activationCount, 1)
        XCTAssertFalse(playback.isPreparing)
        await playback.stopAndWait()
        XCTAssertEqual(session.deactivationCount, 1)
    }

    @MainActor
    func testInterruptionPausesPersistsAndResumesOnlyWhenSystemAllows() throws {
        let session = RecordingAudioSession()
        let commands = RecordingRemoteCommandRouter()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let playback = PlaybackController(
            defaults: defaults,
            audioSession: session,
            remoteCommands: commands,
            notificationCenter: NotificationCenter()
        )
        let tracks = Self.lifecycleTracks()
        playback.configureForLifecycleTesting(
            queue: tracks,
            currentIndex: 0,
            elapsed: 23,
            isPlaying: true
        )

        playback.handleInterruptionBegan()

        XCTAssertFalse(playback.isPlaying)
        let data = try XCTUnwrap(defaults.data(forKey: "active-playback-snapshot-v1"))
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSnapshot.self, from: data).position, 23)

        playback.handleInterruptionEnded(shouldResume: false)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(session.activationCount, 0)

        playback.handleInterruptionBegan()
        playback.handleInterruptionEnded(shouldResume: true)
        XCTAssertFalse(playback.isPlaying, "A player paused before interruption must not auto-resume")
        XCTAssertEqual(session.activationCount, 0)

        playback.configureForLifecycleTesting(
            queue: tracks,
            currentIndex: 0,
            elapsed: 23,
            isPlaying: true
        )
        playback.handleInterruptionBegan()
        playback.handleInterruptionEnded(shouldResume: true)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(session.activationCount, 1)
    }

    @MainActor
    func testInterruptionAndHeadphoneLossCannotStartAPlayerStillPreparing() throws {
        let session = RecordingAudioSession()
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: session,
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        let tracks = Self.lifecycleTracks()
        playback.configureForLifecycleTesting(
            queue: tracks,
            currentIndex: 0,
            elapsed: 0,
            isPlaying: false,
            isPreparing: true,
            playbackRequested: true,
            playerAvailable: false
        )

        XCTAssertTrue(playback.shouldStartPreparedPlayer)
        playback.handleInterruptionBegan()
        XCTAssertFalse(playback.shouldStartPreparedPlayer)
        playback.handleInterruptionEnded(shouldResume: false)
        XCTAssertFalse(playback.shouldStartPreparedPlayer)

        playback.configureForLifecycleTesting(
            queue: tracks,
            currentIndex: 0,
            elapsed: 0,
            isPlaying: false,
            isPreparing: true,
            playbackRequested: true,
            playerAvailable: false
        )
        playback.handleInterruptionBegan()
        playback.handleInterruptionEnded(shouldResume: true)
        XCTAssertTrue(playback.shouldStartPreparedPlayer)
        XCTAssertEqual(session.activationCount, 1, "Pending playback must reactivate its interrupted audio session")

        playback.handleRouteChange(reason: .oldDeviceUnavailable)
        XCTAssertFalse(playback.shouldStartPreparedPlayer)
        XCTAssertFalse(playback.isPlaying)
    }

    @MainActor
    func testOldDeviceUnavailablePausesButOtherRouteChangesPreserveState() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let playback = PlaybackController(
            defaults: defaults,
            audioSession: RecordingAudioSession(),
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        playback.configureForLifecycleTesting(
            queue: Self.lifecycleTracks(),
            currentIndex: 0,
            elapsed: 12,
            isPlaying: true
        )

        playback.handleRouteChange(reason: .newDeviceAvailable)
        XCTAssertTrue(playback.isPlaying)

        playback.handleRouteChange(reason: .oldDeviceUnavailable)
        XCTAssertFalse(playback.isPlaying)
        let data = try XCTUnwrap(defaults.data(forKey: "active-playback-snapshot-v1"))
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSnapshot.self, from: data).position, 12)
    }

    @MainActor
    func testMediaServicesResetReactivatesSessionAndFailsPaused() throws {
        let session = RecordingAudioSession()
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: session,
            remoteCommands: RecordingRemoteCommandRouter(),
            notificationCenter: NotificationCenter()
        )
        playback.configureForLifecycleTesting(
            queue: Self.lifecycleTracks(),
            currentIndex: 0,
            elapsed: 7,
            isPlaying: true
        )

        playback.handleMediaServicesReset()
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(session.activationCount, 1)

        session.activationError = NSError(domain: "AudioSessionTest", code: 42)
        playback.handleMediaServicesReset()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertNotNil(playback.errorMessage)
        XCTAssertEqual(session.activationCount, 2)
    }

    @MainActor
    func testRemoteCommandsRouteThroughAuthoritativePlaybackController() throws {
        let commands = RecordingRemoteCommandRouter()
        let playback = PlaybackController(
            defaults: try XCTUnwrap(UserDefaults(suiteName: #function)),
            audioSession: RecordingAudioSession(),
            remoteCommands: commands,
            notificationCenter: NotificationCenter()
        )
        playback.configureForLifecycleTesting(
            queue: Self.lifecycleTracks(),
            currentIndex: 0,
            elapsed: 0,
            isPlaying: false
        )

        commands.send(.play)
        XCTAssertTrue(playback.isPlaying)
        commands.send(.pause)
        XCTAssertFalse(playback.isPlaying)
        commands.send(.seek(18))
        XCTAssertEqual(playback.elapsed, 18)
        commands.send(.next)
        XCTAssertEqual(playback.currentIndex, 1)
        commands.send(.seek(0))
        commands.send(.previous)
        XCTAssertEqual(playback.currentIndex, 0)
        XCTAssertEqual(commands.lastAvailability, .init(canGoPrevious: false, canGoNext: true))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
        response(for: request, status: 200, json: json)
    }

    private static func response(for request: URLRequest, status: Int, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (response, Data(json.utf8))
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { break }
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func searchPage(named name: String) -> MusicSearchPage {
        MusicSearchPage(
            artists: [Artist(id: "\(name)-artist", name: "\(name) Artist", imageTag: nil)],
            albums: [Album(id: "\(name)-album", name: name, artist: "\(name) Artist",
                           productionYear: nil, imageTag: nil)],
            hasMore: false,
            nextStartIndex: 2
        )
    }

    private static func lifecycleTracks() -> [Track] {
        [
            Track(id: "one", name: "One", artist: "Artist", album: "Album",
                  index: 1, disc: 1, durationTicks: 600_000_000),
            Track(id: "two", name: "Two", artist: "Artist", album: "Album",
                  index: 2, disc: 1, durationTicks: 600_000_000),
        ]
    }

    private static func queueTracks() -> [Track] {
        (1...4).map { (number: Int) in
            Track(id: "queue-\(number)", name: "Queue \(number)", artist: "Artist", album: "Album",
                  index: number, disc: 1, durationTicks: 600_000_000)
        }
    }
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.withLock { storage }
    }

    func append(_ event: String) {
        lock.withLock { storage.append(event) }
    }

    func contains(_ event: String) -> Bool {
        lock.withLock { storage.contains(event) }
    }
}

private actor ControlledSearchLoader {
    private var oldStarted = false
    private var oldStartedWaiter: CheckedContinuation<Void, Never>?
    private var oldReleaseWaiter: CheckedContinuation<Void, Never>?

    func load(query: String) async -> MusicSearchPage {
        if query == "old" {
            oldStarted = true
            oldStartedWaiter?.resume()
            oldStartedWaiter = nil
            await withCheckedContinuation { oldReleaseWaiter = $0 }
            return MusicSearchPage(
                artists: [Artist(id: "old-artist", name: "Old Artist", imageTag: nil)],
                albums: [Album(id: "old-album", name: "Old", artist: "Old Artist",
                               productionYear: nil, imageTag: nil)],
                hasMore: false,
                nextStartIndex: 2
            )
        }
        return MusicSearchPage(
            artists: [Artist(id: "new-artist", name: "New Artist", imageTag: nil)],
            albums: [Album(id: "new-album", name: "New", artist: "New Artist",
                           productionYear: nil, imageTag: nil)],
            hasMore: false,
            nextStartIndex: 2
        )
    }

    func waitUntilOldStarted() async {
        if oldStarted { return }
        await withCheckedContinuation { oldStartedWaiter = $0 }
    }

    func releaseOld() {
        oldReleaseWaiter?.resume()
        oldReleaseWaiter = nil
    }
}

@MainActor
private final class RecordingAudioSession: AudioSessionManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    var activationError: Error?

    func activateForPlayback() throws {
        activationCount += 1
        if let activationError { throw activationError }
    }
    func deactivateAfterPlayback() throws { deactivationCount += 1 }
}

@MainActor
private final class RecordingRemoteCommandRouter: RemoteCommandRouting {
    struct Availability: Equatable {
        let canGoPrevious: Bool
        let canGoNext: Bool
    }

    private var handler: (@MainActor (PlaybackRemoteCommand) -> Void)?
    private(set) var lastAvailability: Availability?

    func register(handler: @escaping @MainActor (PlaybackRemoteCommand) -> Void) {
        self.handler = handler
    }

    func updateAvailability(canGoPrevious: Bool, canGoNext: Bool) {
        lastAvailability = Availability(canGoPrevious: canGoPrevious, canGoNext: canGoNext)
    }

    func send(_ command: PlaybackRemoteCommand) {
        handler?(command)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
