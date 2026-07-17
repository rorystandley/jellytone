import Foundation

struct JellyfinAPI: Sendable {
    struct PublicInfo: Decodable, Sendable {
        let id: String
        let serverName: String
        let version: String

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case serverName = "ServerName"
            case version = "Version"
        }
    }

    struct Authentication: Sendable {
        let token: String
        let userID: String
        let username: String
    }

    let baseURL: URL
    let deviceID: String
    let token: String?
    private let urlSession: URLSession

    init(baseURL: URL, deviceID: String, token: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.token = token
        self.urlSession = urlSession
    }

    func publicInfo() async throws -> PublicInfo {
        try await send(operation: "public_info", path: ["System", "Info", "Public"], as: PublicInfo.self)
    }

    func authenticate(username: String, password: String) async throws -> Authentication {
        struct Body: Encodable { let Username: String; let Pw: String }
        struct Response: Decodable {
            struct User: Decodable { let Id: String; let Name: String }
            let AccessToken: String
            let User: User
        }
        let response = try await send(
            operation: "authenticate",
            path: ["Users", "AuthenticateByName"],
            method: "POST",
            body: Body(Username: username, Pw: password),
            as: Response.self
        )
        return Authentication(token: response.AccessToken, userID: response.User.Id, username: response.User.Name)
    }

    func musicLibraries(userID: String) async throws -> [MusicLibrary] {
        let response = try await send(
            operation: "music_views",
            path: ["Users", userID, "Views"],
            query: [URLQueryItem(name: "IncludeExternalContent", value: "false")],
            as: ItemsResponse<Item>.self
        )
        return response.Items.compactMap { item in
            guard item.CollectionType == "music", let identity = item.validatedIdentity else { return nil }
            return MusicLibrary(id: identity.id, name: identity.name)
        }
    }

    func albums(
        userID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> AlbumPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "albums",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let albums = response.Items.compactMap(mapAlbum)
        let hasMore = response.receivedItemCount > 0
            && (response.TotalRecordCount.map { startIndex + response.receivedItemCount < $0 }
                ?? (response.receivedItemCount == limit))
        return AlbumPage(
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func searchMusic(
        userID: String,
        libraryID: String?,
        query searchTerm: String,
        startIndex: Int = 0,
        limit: Int = 40
    ) async throws -> MusicSearchPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "SearchTerm", value: searchTerm),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicArtist,MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "music_search",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let artists = response.Items.compactMap { item -> Artist? in
            guard item.`Type` == "MusicArtist" else { return nil }
            guard let identity = item.validatedIdentity else { return nil }
            return Artist(id: identity.id, name: identity.name, imageTag: item.ImageTags?["Primary"])
        }
        let albums = response.Items.compactMap { item -> Album? in
            guard item.`Type` == "MusicAlbum" else { return nil }
            return mapAlbum(item)
        }
        let hasMore = response.receivedItemCount > 0
            && (response.TotalRecordCount.map { startIndex + response.receivedItemCount < $0 }
                ?? (response.receivedItemCount == limit))
        return MusicSearchPage(
            artists: artists,
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func playlists(
        userID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> PlaylistPage {
        let query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,ChildCount"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        // Jellyfin playlists are user-global and are not children of music views.
        _ = libraryID
        let response = try await send(
            operation: "playlists",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let playlists = response.Items.compactMap { item -> Playlist? in
            guard item.`Type` == nil || item.`Type` == "Playlist",
                  let identity = item.validatedIdentity else { return nil }
            return Playlist(
                id: identity.id,
                name: identity.name,
                imageTag: item.ImageTags?["Primary"],
                itemCount: item.ChildCount
            )
        }
        return PlaylistPage(
            playlists: playlists,
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func genres(
        userID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> GenrePage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            // Jellyfin 10.10.7 and 10.11.11 return no music genres when
            // IncludeItemTypes is supplied here. ParentId is the compatible
            // music-only scope; detail queries retain their explicit types.
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,ItemCounts"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "genres",
            path: ["Genres"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let genres = response.Items.compactMap { item -> Genre? in
            guard item.`Type` == nil || item.`Type` == "MusicGenre",
                  let identity = item.validatedIdentity else { return nil }
            return Genre(
                id: identity.id,
                name: identity.name,
                imageTag: item.ImageTags?["Primary"],
                itemCount: item.SongCount ?? item.RecursiveItemCount ?? item.ChildCount,
                albumCount: item.AlbumCount
            )
        }
        return GenrePage(
            genres: genres,
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func genreAlbums(
        userID: String,
        genreID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> AlbumPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "GenreIds", value: genreID),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "genre_albums",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        return AlbumPage(
            albums: response.Items.compactMap { item in
                item.`Type` == nil || item.`Type` == "MusicAlbum" ? mapAlbum(item) : nil
            },
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func genreTracks(
        userID: String,
        genreID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> GenreTrackPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "GenreIds", value: genreID),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "RunTimeTicks"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "Album,ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "genre_tracks",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let occurrences = response.wireItems.enumerated().compactMap { offset, item -> GenreTrackOccurrence? in
            guard let item, item.`Type` == nil || item.`Type` == "Audio",
                  let track = mapTrack(item) else { return nil }
            return GenreTrackOccurrence(
                id: "\(genreID):\(startIndex + offset):\(track.id)",
                track: track
            )
        }
        return GenreTrackPage(
            occurrences: occurrences,
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func playlistEntries(
        userID: String,
        playlistID: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> PlaylistEntryPage {
        let response = try await send(
            operation: "playlist_entries",
            path: ["Playlists", playlistID, "Items"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "Fields", value: "RunTimeTicks"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            ],
            as: ItemsResponse<Item>.self
        )
        let entries = response.wireItems.enumerated().compactMap { offset, item -> PlaylistEntry? in
            guard let item, item.`Type` == "Audio", let track = mapTrack(item) else { return nil }
            let wireIdentity = item.PlaylistItemId?.nonEmpty
            let occurrenceID = wireIdentity != track.id
                ? wireIdentity
                : nil
            return PlaylistEntry(
                id: occurrenceID ?? "\(playlistID):\(startIndex + offset):\(track.id)",
                track: track
            )
        }
        return PlaylistEntryPage(
            entries: entries,
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func albums(
        userID: String,
        artistID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 50
    ) async throws -> AlbumPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "ArtistIds", value: artistID),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "artist_albums",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let albums = response.Items.compactMap { item in
            item.`Type` == nil || item.`Type` == "MusicAlbum" ? mapAlbum(item) : nil
        }
        let hasMore = response.receivedItemCount > 0
            && (response.TotalRecordCount.map { startIndex + response.receivedItemCount < $0 }
                ?? (response.receivedItemCount == limit))
        return AlbumPage(
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func tracks(userID: String, albumID: String) async throws -> [Track] {
        let response = try await send(
            operation: "tracks",
            path: ["Items"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "ParentId", value: albumID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: "RunTimeTicks"),
                URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ],
            as: ItemsResponse<Item>.self
        )
        return response.Items.compactMap { item in
            guard let identity = item.validatedIdentity else { return nil }
            return Track(
                id: identity.id,
                name: identity.name,
                artist: item.Artists?.first?.nonEmpty ?? item.AlbumArtist?.nonEmpty ?? "Unknown Artist",
                album: item.Album?.nonEmpty ?? "",
                albumID: item.AlbumId?.nonEmpty,
                index: item.IndexNumber,
                disc: item.ParentIndexNumber,
                durationTicks: item.RunTimeTicks
            )
        }
        .sorted(by: trackPrecedes)
    }

    func playbackPlan(itemID: String, userID: String) async throws -> PlaybackPlan {
        let response = try await send(
            operation: "playback_info",
            path: ["Items", itemID, "PlaybackInfo"],
            query: [URLQueryItem(name: "userId", value: userID)],
            as: PlaybackInfoResponse.self
        )
        guard let source = response.MediaSources.first,
              let mediaSourceID = source.Id,
              let playSessionID = response.PlaySessionId else {
            throw APIError.noPlayableSource
        }
        let direct = source.SupportsDirectPlay == true && supportsDirectPlay(source)
        guard direct || source.SupportsTranscoding == true else { throw APIError.noPlayableSource }
        return PlaybackPlan(
            url: try direct
                ? streamURL(itemID: itemID, mediaSourceID: mediaSourceID, playSessionID: playSessionID)
                : transcodeURL(itemID: itemID, userID: userID, mediaSourceID: mediaSourceID, playSessionID: playSessionID),
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            method: direct ? .directPlay : .transcode
        )
    }

    @discardableResult
    func reportStarted(itemID: String, plan: PlaybackPlan, position: TimeInterval, paused: Bool) async -> PlaybackReportOutcome {
        await report(
            operation: "playback_started",
            path: ["Sessions", "Playing"],
            body: PlaybackReport(
                ItemId: itemID,
                MediaSourceId: plan.mediaSourceID,
                PlaySessionId: plan.playSessionID,
                PlayMethod: plan.method.rawValue,
                CanSeek: true,
                IsPaused: paused,
                PositionTicks: ticks(position)
            )
        )
    }

    @discardableResult
    func reportProgress(itemID: String, plan: PlaybackPlan, position: TimeInterval, paused: Bool) async -> PlaybackReportOutcome {
        await report(
            operation: "playback_progress",
            path: ["Sessions", "Playing", "Progress"],
            body: PlaybackReport(
                ItemId: itemID,
                MediaSourceId: plan.mediaSourceID,
                PlaySessionId: plan.playSessionID,
                PlayMethod: plan.method.rawValue,
                CanSeek: true,
                IsPaused: paused,
                PositionTicks: ticks(position)
            )
        )
    }

    @discardableResult
    func reportStopped(itemID: String, plan: PlaybackPlan, position: TimeInterval) async -> PlaybackReportOutcome {
        await report(
            operation: "playback_stopped",
            path: ["Sessions", "Playing", "Stopped"],
            body: PlaybackStopReport(
                ItemId: itemID,
                MediaSourceId: plan.mediaSourceID,
                PlaySessionId: plan.playSessionID,
                PositionTicks: ticks(position)
            )
        )
    }

    func artworkRequest(itemID: String, maxWidth: Int = 600) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(
            path: ["Items", itemID, "Images", "Primary"],
            query: [URLQueryItem(name: "maxWidth", value: String(maxWidth))]
        ))
        addAuthorization(to: &request)
        return request
    }

    func artworkData(itemID: String, maxWidth: Int = 1_200) async throws -> Data {
        let request = try artworkRequest(itemID: itemID, maxWidth: maxWidth)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.invalidResponse
        }
        return data
    }

    func streamURL(itemID: String) throws -> URL {
        guard let token else { throw APIError.notAuthenticated }
        return try makeURL(
            path: ["Audio", itemID, "stream"],
            query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "api_key", value: token),
            ]
        )
    }

    private func streamURL(itemID: String, mediaSourceID: String, playSessionID: String) throws -> URL {
        guard let token else { throw APIError.notAuthenticated }
        return try makeURL(
            path: ["Audio", itemID, "stream"],
            query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: mediaSourceID),
                URLQueryItem(name: "playSessionId", value: playSessionID),
                URLQueryItem(name: "api_key", value: token),
            ]
        )
    }

    private func transcodeURL(
        itemID: String,
        userID: String,
        mediaSourceID: String,
        playSessionID: String
    ) throws -> URL {
        guard let token else { throw APIError.notAuthenticated }
        return try makeURL(
            path: ["Audio", itemID, "universal"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "deviceId", value: deviceID),
                URLQueryItem(name: "mediaSourceId", value: mediaSourceID),
                URLQueryItem(name: "playSessionId", value: playSessionID),
                URLQueryItem(name: "container", value: "mp4"),
                URLQueryItem(name: "audioCodec", value: "aac"),
                URLQueryItem(name: "maxAudioChannels", value: "2"),
                URLQueryItem(name: "transcodingAudioChannels", value: "2"),
                URLQueryItem(name: "maxStreamingBitrate", value: "128000"),
                URLQueryItem(name: "audioBitRate", value: "128000"),
                URLQueryItem(name: "transcodingContainer", value: "mp4"),
                URLQueryItem(name: "transcodingProtocol", value: "http"),
                URLQueryItem(name: "enableDirectPlay", value: "false"),
                URLQueryItem(name: "enableDirectStream", value: "false"),
                URLQueryItem(name: "enableTranscoding", value: "true"),
                URLQueryItem(name: "enableRedirection", value: "false"),
                URLQueryItem(name: "api_key", value: token),
            ]
        )
    }

    private func supportsDirectPlay(_ source: PlaybackInfoResponse.MediaSource) -> Bool {
        guard let codec = source.MediaStreams?.first(where: { $0.type?.lowercased() == "audio" })?.codec?.lowercased()
        else { return false }
        let containers = Set((source.Container ?? "").lowercased().split(separator: ",").map(String.init))
        switch codec {
        case "mp3": return containers.isEmpty || containers.contains("mp3")
        case "flac": return containers.isEmpty || containers.contains("flac")
        case "aac": return !containers.isDisjoint(with: ["aac", "m4a", "mp4"])
        case "alac": return !containers.isDisjoint(with: ["m4a", "mp4"])
        case "vorbis", "opus": return !containers.isDisjoint(with: ["ogg", "oga", "webm"])
        default: return false
        }
    }

    private func mapAlbum(_ item: Item) -> Album? {
        guard let identity = item.validatedIdentity else { return nil }
        return Album(
            id: identity.id,
            name: identity.name,
            artist: item.AlbumArtist?.nonEmpty ?? item.Artists?.first?.nonEmpty ?? "Unknown Artist",
            productionYear: item.ProductionYear,
            imageTag: item.ImageTags?["Primary"]
        )
    }

    private func mapTrack(_ item: Item) -> Track? {
        guard let identity = item.validatedIdentity else { return nil }
        return Track(
            id: identity.id,
            name: identity.name,
            artist: item.Artists?.first?.nonEmpty ?? item.AlbumArtist?.nonEmpty ?? "Unknown Artist",
            album: item.Album?.nonEmpty ?? "",
            albumID: item.AlbumId?.nonEmpty,
            index: item.IndexNumber,
            disc: item.ParentIndexNumber,
            durationTicks: item.RunTimeTicks
        )
    }

    private func hasMore<Value>(response: ItemsResponse<Value>, startIndex: Int, limit: Int) -> Bool {
        response.receivedItemCount > 0
            && (response.TotalRecordCount.map { startIndex + response.receivedItemCount < $0 }
                ?? (response.receivedItemCount == limit))
    }

    private func trackPrecedes(_ lhs: Track, _ rhs: Track) -> Bool {
        if lhs.disc != rhs.disc { return optionalIndex(lhs.disc, precedes: rhs.disc) }
        if lhs.index != rhs.index { return optionalIndex(lhs.index, precedes: rhs.index) }
        let lhsName = lhs.name.precomposedStringWithCanonicalMapping
        let rhsName = rhs.name.precomposedStringWithCanonicalMapping
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id < rhs.id
    }

    private func optionalIndex(_ lhs: Int?, precedes rhs: Int?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): lhs < rhs
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): false
        }
    }

    private func report<Body: Encodable>(operation: String, path: [String], body: Body) async -> PlaybackReportOutcome {
        do {
            var request = URLRequest(url: try makeURL(path: path))
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addAuthorization(to: &request)
            let status = try await executeNoContent(request, operation: operation)
            return .accepted(status: status)
        } catch {
            let failure = PlaybackReportFailure(error: error)
            return .failed(failure)
        }
    }

    private func executeNoContent(_ request: URLRequest, operation: String) async throws -> Int {
        Diagnostics.event("request_started", ["operation": operation])
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        Diagnostics.event("response_received", ["operation": operation, "status": http.statusCode])
        guard 200..<300 ~= http.statusCode else { throw APIError.httpStatus(http.statusCode) }
        return http.statusCode
    }

    private func ticks(_ seconds: TimeInterval) -> Int64 {
        Int64(max(0, seconds) * 10_000_000)
    }

    private func send<Response: Decodable>(
        operation: String,
        path: [String],
        query: [URLQueryItem] = [],
        method: String = "GET",
        as type: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        addAuthorization(to: &request)
        return try await execute(request, operation: operation, as: type)
    }

    private func send<Body: Encodable, Response: Decodable>(
        operation: String,
        path: [String],
        method: String,
        body: Body,
        as type: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorization(to: &request)
        return try await execute(request, operation: operation, as: type)
    }

    private func execute<Response: Decodable>(
        _ request: URLRequest,
        operation: String,
        as type: Response.Type
    ) async throws -> Response {
        Diagnostics.event("request_started", ["operation": operation])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                Diagnostics.event("request_cancelled", ["operation": operation])
                throw CancellationError()
            }
            let failure = error as NSError
            Diagnostics.event("request_failed", [
                "code": failure.code,
                "domain": failure.domain,
                "operation": operation,
            ])
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        Diagnostics.event("response_received", [
            "bytes": data.count,
            "operation": operation,
            "status": http.statusCode,
        ])
        guard 200..<300 ~= http.statusCode else { throw APIError.httpStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Diagnostics.event("response_decode_failed", ["bytes": data.count, "operation": operation])
            throw APIError.invalidPayload
        }
    }

    private func makeURL(path: [String], query: [URLQueryItem] = []) throws -> URL {
        var url = baseURL
        for component in path { url.append(path: component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidServerURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let result = components.url else { throw APIError.invalidServerURL }
        return result
    }

    private func addAuthorization(to request: inout URLRequest) {
        request.setValue(
            "MediaBrowser Client=\"Jellyfin Audio\", Device=\"Apple Mobile\", DeviceId=\"\(deviceID)\", Version=\"0.1.0\"",
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        if let token { request.setValue(token, forHTTPHeaderField: "X-Emby-Token") }
    }
}

private struct ItemsResponse<Value: Decodable>: Decodable {
    let Items: [Value]
    let wireItems: [Value?]
    let TotalRecordCount: Int?
    let receivedItemCount: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let receivedItems = try container.decode([LossyDecodable<Value>].self, forKey: .Items)
        wireItems = receivedItems.map(\.value)
        Items = wireItems.compactMap { $0 }
        receivedItemCount = receivedItems.count
        TotalRecordCount = try? container.decodeIfPresent(Int.self, forKey: .TotalRecordCount)
    }

    private enum CodingKeys: String, CodingKey {
        case Items, TotalRecordCount
    }
}

private struct Item: Decodable {
    let Id: String?
    let Name: String?
    let `Type`: String?
    let CollectionType: String?
    let AlbumArtist: String?
    let Artists: [String]?
    let Album: String?
    let AlbumId: String?
    let ProductionYear: Int?
    let ImageTags: [String: String]?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?
    let RunTimeTicks: Int64?
    let ChildCount: Int?
    let RecursiveItemCount: Int?
    let SongCount: Int?
    let AlbumCount: Int?
    let PlaylistItemId: String?

    var validatedIdentity: (id: String, name: String)? {
        guard let id = Id?.nonEmpty, let name = Name?.nonEmpty else { return nil }
        return (id, name)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Id = container.lossy(String.self, forKey: .Id)
        Name = container.lossy(String.self, forKey: .Name)
        Type = container.lossy(String.self, forKey: .Type)
        CollectionType = container.lossy(String.self, forKey: .CollectionType)
        AlbumArtist = container.lossy(String.self, forKey: .AlbumArtist)
        Artists = container.lossy([String].self, forKey: .Artists)
        Album = container.lossy(String.self, forKey: .Album)
        AlbumId = container.lossy(String.self, forKey: .AlbumId)
        ProductionYear = container.lossy(Int.self, forKey: .ProductionYear)
        ImageTags = container.lossy([String: String].self, forKey: .ImageTags)
        IndexNumber = container.lossy(Int.self, forKey: .IndexNumber)
        ParentIndexNumber = container.lossy(Int.self, forKey: .ParentIndexNumber)
        RunTimeTicks = container.lossy(Int64.self, forKey: .RunTimeTicks)
        ChildCount = container.lossy(Int.self, forKey: .ChildCount)
        RecursiveItemCount = container.lossy(Int.self, forKey: .RecursiveItemCount)
        SongCount = container.lossy(Int.self, forKey: .SongCount)
        AlbumCount = container.lossy(Int.self, forKey: .AlbumCount)
        PlaylistItemId = container.lossy(String.self, forKey: .PlaylistItemId)
    }

    private enum CodingKeys: String, CodingKey {
        case Id, Name, `Type`, CollectionType, AlbumArtist, Artists, Album, AlbumId
        case ProductionYear, ImageTags, IndexNumber, ParentIndexNumber, RunTimeTicks
        case ChildCount, RecursiveItemCount, SongCount, AlbumCount, PlaylistItemId
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func lossy<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private struct PlaybackInfoResponse: Decodable {
    struct MediaSource: Decodable {
        struct MediaStream: Decodable {
            let type: String?
            let codec: String?

            enum CodingKeys: String, CodingKey {
                case type = "Type"
                case codec = "Codec"
            }
        }
        let Id: String?
        let Container: String?
        let SupportsDirectPlay: Bool?
        let SupportsTranscoding: Bool?
        let MediaStreams: [MediaStream]?
    }
    let MediaSources: [MediaSource]
    let PlaySessionId: String?
}

private struct PlaybackReport: Encodable {
    let ItemId: String
    let MediaSourceId: String
    let PlaySessionId: String
    let PlayMethod: String
    let CanSeek: Bool
    let IsPaused: Bool
    let PositionTicks: Int64
}

private struct PlaybackStopReport: Encodable {
    let ItemId: String
    let MediaSourceId: String
    let PlaySessionId: String
    let PositionTicks: Int64
}

enum PlaybackReportOutcome: Equatable {
    case accepted(status: Int)
    case failed(PlaybackReportFailure)

    var failure: PlaybackReportFailure? {
        guard case let .failed(failure) = self else { return nil }
        return failure
    }
}

struct PlaybackReportFailure: Equatable {
    enum Kind: Int, Equatable {
        case cancelled = 1
        case transport = 2
        case server = 3
        case invalidResponse = 4
        case encoding = 5
        case unknown = 6
    }

    let kind: Kind
    let code: Int

    init(error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            kind = .cancelled
        } else if error is URLError {
            kind = .transport
        } else if let apiError = error as? APIError {
            switch apiError {
            case .httpStatus:
                kind = .server
            case .invalidResponse:
                kind = .invalidResponse
            default:
                kind = .unknown
            }
        } else if error is EncodingError {
            kind = .encoding
        } else {
            kind = .unknown
        }
        code = (error as NSError).code
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidServerURL
    case invalidResponse
    case invalidPayload
    case httpStatus(Int)
    case notAuthenticated
    case noPlayableSource

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid Jellyfin server URL."
        case .invalidResponse: "The server returned an invalid response."
        case .invalidPayload: "The server response was not understood."
        case .httpStatus(401): "The username or password was rejected."
        case let .httpStatus(status): "The server returned HTTP \(status)."
        case .notAuthenticated: "Connect to Jellyfin before playing music."
        case .noPlayableSource: "Jellyfin did not return a playable audio source."
        }
    }
}
