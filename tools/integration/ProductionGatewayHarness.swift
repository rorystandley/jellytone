import Foundation

// The production gateway's diagnostic call sites remain compiled and executed,
// but the host harness does not write into the macOS user's Documents folder.
// Request/response truth is independently asserted by the controlled capture.
enum Diagnostics {
    static func event(_ name: String, _ values: [String: CustomStringConvertible] = [:]) {
        _ = name
        _ = values
    }
}

enum HarnessFailure: Error {
    case invalidArguments
    case versionMismatch
    case fixtureMissing
    case genreListEmpty
    case genreMarkerMissing
    case genreAlbumMissing
    case genreTrackMissing
    case homeRecentlyAddedMissing
    case homeRecentlyPlayedMissing
    case trackCatalogMissing
    case wrongPlaybackMethod
    case deliveryFailed
    case reportingFailed
}

@main
struct ProductionGatewayHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 6 else { throw HarnessFailure.invalidArguments }
        let endpoint = CommandLine.arguments[1]
        let expectedVersion = CommandLine.arguments[2]
        let passwordPath = CommandLine.arguments[3]
        let outputPath = CommandLine.arguments[4]
        let fixtureMarker = CommandLine.arguments[5]
        guard let baseURL = URL(string: endpoint) else { throw HarnessFailure.invalidArguments }

        var password = try String(contentsOfFile: passwordPath, encoding: .utf8)
        let anonymous = JellyfinAPI(baseURL: baseURL, deviceID: "phase2-live-integration")
        let info = try await anonymous.publicInfo()
        guard info.version == expectedVersion else { throw HarnessFailure.versionMismatch }
        let authentication = try await anonymous.authenticate(username: "root", password: password)
        password = ""
        let api = JellyfinAPI(
            baseURL: baseURL,
            deviceID: "phase2-live-integration",
            token: authentication.token
        )

        let libraries = try await api.musicLibraries(userID: authentication.userID)
        var selectedTrack: Track?
        var selectedLibrary: MusicLibrary?
        for _ in 0..<30 where selectedTrack == nil {
            for library in libraries {
                let albums = try await api.albums(userID: authentication.userID, libraryID: library.id)
                for album in albums.albums {
                    let tracks = try await api.tracks(userID: authentication.userID, albumID: album.id)
                    if let match = tracks.first(where: { $0.name == fixtureMarker }) {
                        selectedTrack = match
                        selectedLibrary = library
                        break
                    }
                }
                if selectedTrack != nil { break }
            }
            if selectedTrack == nil { try await Task.sleep(for: .seconds(1)) }
        }
        guard let selectedTrack, let selectedLibrary else { throw HarnessFailure.fixtureMissing }

        let catalogPage = try await api.trackCatalogPage(
            userID: authentication.userID,
            libraryID: selectedLibrary.id,
            startIndex: 0,
            limit: 100
        )
        guard catalogPage.occurrences.contains(where: { $0.track.id == selectedTrack.id }) else {
            throw HarnessFailure.trackCatalogMissing
        }

        let recentlyAdded = try await api.recentlyAddedAlbums(
            userID: authentication.userID,
            libraryID: selectedLibrary.id
        )
        guard !recentlyAdded.isEmpty else { throw HarnessFailure.homeRecentlyAddedMissing }

        var observedGenres = false
        var observedFixtureGenre = false
        var observedGenreTrack = false
        var observedGenreAlbum = false
        for _ in 0..<30 where !observedGenreAlbum {
            let genres = try await api.genres(
                userID: authentication.userID,
                libraryID: selectedLibrary.id
            )
            observedGenres = observedGenres || !genres.genres.isEmpty
            if let fixtureGenre = genres.genres.first(where: { $0.name == "Phase Three Fixture Genre" }) {
                observedFixtureGenre = true
                let genreAlbums = try await api.genreAlbums(
                    userID: authentication.userID,
                    genreID: fixtureGenre.id,
                    libraryID: selectedLibrary.id
                )
                let genreTracks = try await api.genreTracks(
                    userID: authentication.userID,
                    genreID: fixtureGenre.id,
                    libraryID: selectedLibrary.id
                )
                if let genreTrack = genreTracks.occurrences.first(where: {
                    $0.track.name == "Phase Three Genre Track"
                }) {
                    observedGenreTrack = true
                    if let genreAlbumID = genreTrack.track.albumID {
                        observedGenreAlbum = genreAlbums.albums.contains { $0.id == genreAlbumID }
                    }
                }
            }
            if !observedGenreAlbum { try await Task.sleep(for: .seconds(1)) }
        }
        guard observedGenres else { throw HarnessFailure.genreListEmpty }
        guard observedFixtureGenre else { throw HarnessFailure.genreMarkerMissing }
        guard observedGenreTrack else { throw HarnessFailure.genreTrackMissing }
        guard observedGenreAlbum else { throw HarnessFailure.genreAlbumMissing }
        let plan = try await api.playbackPlan(itemID: selectedTrack.id, userID: authentication.userID)
        guard plan.method == .transcode else { throw HarnessFailure.wrongPlaybackMethod }

        var request = URLRequest(url: plan.url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode,
              !data.isEmpty else { throw HarnessFailure.deliveryFailed }
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

        try requireAccepted(await api.reportStarted(
            itemID: selectedTrack.id, plan: plan, position: 0, paused: false
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.25, paused: false
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.25, paused: true
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.25, paused: false
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.75, paused: false
        ))
        try requireAccepted(await api.reportStopped(
            itemID: selectedTrack.id, plan: plan, position: 1.0
        ))

        var observedRecentlyPlayed = false
        for _ in 0..<30 where !observedRecentlyPlayed {
            let recentlyPlayed = try await api.recentlyPlayedTracks(
                userID: authentication.userID,
                libraryID: selectedLibrary.id
            )
            observedRecentlyPlayed = recentlyPlayed.contains { $0.id == selectedTrack.id }
            if !observedRecentlyPlayed { try await Task.sleep(for: .seconds(1)) }
        }
        guard observedRecentlyPlayed else { throw HarnessFailure.homeRecentlyPlayedMissing }

        // Only fixed allowlisted values reach stdout. Production diagnostics also
        // emit operation/status metadata, never credentials, endpoints or identity.
        print("LIVE_GATEWAY_RESULT version=pass tracks=complete genre=complete home=complete transcode=aac-mp4 lifecycle=complete")
    }

    private static func requireAccepted(_ outcome: PlaybackReportOutcome) throws {
        guard case let .accepted(status) = outcome, 200..<300 ~= status else {
            throw HarnessFailure.reportingFailed
        }
    }
}
