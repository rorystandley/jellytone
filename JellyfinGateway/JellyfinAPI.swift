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
        try await send(path: ["System", "Info", "Public"], as: PublicInfo.self)
    }

    func authenticate(username: String, password: String) async throws -> Authentication {
        struct Body: Encodable { let Username: String; let Pw: String }
        struct Response: Decodable {
            struct User: Decodable { let Id: String; let Name: String }
            let AccessToken: String
            let User: User
        }
        let response = try await send(
            path: ["Users", "AuthenticateByName"],
            method: "POST",
            body: Body(Username: username, Pw: password),
            as: Response.self
        )
        return Authentication(token: response.AccessToken, userID: response.User.Id, username: response.User.Name)
    }

    func musicLibraries(userID: String) async throws -> [MusicLibrary] {
        let response = try await send(
            path: ["Users", userID, "Views"],
            query: [URLQueryItem(name: "IncludeExternalContent", value: "false")],
            as: ItemsResponse<Item>.self
        )
        return response.Items.compactMap { item in
            item.CollectionType == "music" ? MusicLibrary(id: item.Id, name: item.Name) : nil
        }
    }

    func albums(userID: String, libraryID: String?) async throws -> [Album] {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        return response.Items.map {
            Album(id: $0.Id, name: $0.Name, artist: $0.AlbumArtist ?? $0.Artists?.first ?? "Unknown Artist",
                  productionYear: $0.ProductionYear, imageTag: $0.ImageTags?["Primary"])
        }
    }

    func tracks(userID: String, albumID: String) async throws -> [Track] {
        let response = try await send(
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
                  album: $0.Album ?? "", index: $0.IndexNumber, disc: $0.ParentIndexNumber,
                  durationTicks: $0.RunTimeTicks)
        }
    }

    func artworkRequest(itemID: String, maxWidth: Int = 600) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(
            path: ["Items", itemID, "Images", "Primary"],
            query: [URLQueryItem(name: "maxWidth", value: String(maxWidth))]
        ))
        addAuthorization(to: &request)
        return request
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

    private func send<Response: Decodable>(
        path: [String],
        query: [URLQueryItem] = [],
        method: String = "GET",
        as type: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        addAuthorization(to: &request)
        return try await execute(request, as: type)
    }

    private func send<Body: Encodable, Response: Decodable>(
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
        return try await execute(request, as: type)
    }

    private func execute<Response: Decodable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw APIError.httpStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
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
}

private struct Item: Decodable {
    let Id: String
    let Name: String
    let CollectionType: String?
    let AlbumArtist: String?
    let Artists: [String]?
    let Album: String?
    let ProductionYear: Int?
    let ImageTags: [String: String]?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?
    let RunTimeTicks: Int64?
}

enum APIError: LocalizedError, Equatable {
    case invalidServerURL
    case invalidResponse
    case invalidPayload
    case httpStatus(Int)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid Jellyfin server URL."
        case .invalidResponse: "The server returned an invalid response."
        case .invalidPayload: "The server response was not understood."
        case .httpStatus(401): "The username or password was rejected."
        case let .httpStatus(status): "The server returned HTTP \(status)."
        case .notAuthenticated: "Connect to Jellyfin before playing music."
        }
    }
}
