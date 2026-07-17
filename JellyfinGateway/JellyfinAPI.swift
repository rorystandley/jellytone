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
            item.CollectionType == "music" ? MusicLibrary(id: item.Id, name: item.Name) : nil
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
        let albums = response.Items.map {
            Album(id: $0.Id, name: $0.Name, artist: $0.AlbumArtist ?? $0.Artists?.first ?? "Unknown Artist",
                  productionYear: $0.ProductionYear, imageTag: $0.ImageTags?["Primary"])
        }
        let hasMore = !response.Items.isEmpty
            && (response.TotalRecordCount.map { startIndex + response.Items.count < $0 }
                ?? (response.Items.count == limit))
        return AlbumPage(
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.Items.count
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
            return Artist(id: item.Id, name: item.Name, imageTag: item.ImageTags?["Primary"])
        }
        let albums = response.Items.compactMap { item -> Album? in
            guard item.`Type` == "MusicAlbum" else { return nil }
            return mapAlbum(item)
        }
        let hasMore = !response.Items.isEmpty
            && (response.TotalRecordCount.map { startIndex + response.Items.count < $0 }
                ?? (response.Items.count == limit))
        return MusicSearchPage(
            artists: artists,
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.Items.count
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
        let hasMore = !response.Items.isEmpty
            && (response.TotalRecordCount.map { startIndex + response.Items.count < $0 }
                ?? (response.Items.count == limit))
        return AlbumPage(
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.Items.count
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
        return response.Items.map {
            Track(id: $0.Id, name: $0.Name, artist: $0.AlbumArtist ?? $0.Artists?.first ?? "Unknown Artist",
                  album: $0.Album ?? "", albumID: $0.AlbumId, index: $0.IndexNumber, disc: $0.ParentIndexNumber,
                  durationTicks: $0.RunTimeTicks)
        }
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

    private func mapAlbum(_ item: Item) -> Album {
        Album(
            id: item.Id,
            name: item.Name,
            artist: item.AlbumArtist ?? item.Artists?.first ?? "Unknown Artist",
            productionYear: item.ProductionYear,
            imageTag: item.ImageTags?["Primary"]
        )
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
    let TotalRecordCount: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Items = try container.decode([Value].self, forKey: .Items)
        TotalRecordCount = try container.decodeIfPresent(Int.self, forKey: .TotalRecordCount)
    }

    private enum CodingKeys: String, CodingKey {
        case Items, TotalRecordCount
    }
}

private struct Item: Decodable {
    let Id: String
    let Name: String
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
