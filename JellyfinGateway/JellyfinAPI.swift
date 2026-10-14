import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    struct PlaylistRenameRemoteState: Sendable, Equatable { let revision: String; let name: String }

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
        limit: Int = 100,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending"
    ) async throws -> AlbumPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: Self.albumIdentityFields),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortOrder),
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

    // Home shelves deliberately use bounded, music-only item queries. Their
    // ordering is server-authoritative so a warm cache can be replaced without
    // reinterpreting Jellyfin's history or creation semantics locally.
    func recentlyAddedAlbums(
        userID: String,
        libraryID: String,
        limit: Int = 20
    ) async throws -> [Album] {
        let response = try await homeShelfItems(
            operation: "home_recently_added_albums",
            userID: userID,
            libraryID: libraryID,
            itemType: "MusicAlbum",
            limit: limit,
            sortBy: "DateCreated,SortName"
        )
        return uniqueByID(response.Items.compactMap { item in
            guard item.`Type` == "MusicAlbum" else { return nil }
            return mapAlbum(item)
        })
    }

    func recentlyPlayedTracks(
        userID: String,
        libraryID: String,
        limit: Int = 20
    ) async throws -> [Track] {
        let response = try await homeShelfItems(
            operation: "home_recently_played_tracks",
            userID: userID,
            libraryID: libraryID,
            itemType: "Audio",
            limit: limit,
            sortBy: "DatePlayed",
            extraQuery: [URLQueryItem(name: "IsPlayed", value: "true")]
        )
        return uniqueByID(response.Items.compactMap { item in
            guard item.`Type` == "Audio" else { return nil }
            return mapTrack(item)
        })
    }

    /// Most-played albums in the library (server PlayCount). Powers Home's
    /// Listen Now "Top Albums" shelf — not a local reinterpretation of history.
    func frequentlyPlayedAlbums(
        userID: String,
        libraryID: String,
        limit: Int = 20
    ) async throws -> [Album] {
        let response = try await homeShelfItems(
            operation: "home_frequently_played_albums",
            userID: userID,
            libraryID: libraryID,
            itemType: "MusicAlbum",
            limit: limit,
            sortBy: "PlayCount,SortName"
        )
        return uniqueByID(response.Items.compactMap { item in
            guard item.`Type` == "MusicAlbum" else { return nil }
            return mapAlbum(item)
        })
    }

    /// Server-random albums for Home's Rediscover shelf. Ordering is
    /// intentionally non-deterministic across refreshes.
    func rediscoverAlbums(
        userID: String,
        libraryID: String,
        limit: Int = 20
    ) async throws -> [Album] {
        let response = try await homeShelfItems(
            operation: "home_rediscover_albums",
            userID: userID,
            libraryID: libraryID,
            itemType: "MusicAlbum",
            limit: limit,
            sortBy: "Random"
        )
        return uniqueByID(response.Items.compactMap { item in
            guard item.`Type` == "MusicAlbum" else { return nil }
            return mapAlbum(item)
        })
    }

    /// Jellyfin Instant Mix from a seed item (artist, album, or track). Used
    /// when the user plays a Listen Now "Made for You" mix tile.
    ///
    /// Always filtered to Audio: Instant Mix from a MusicArtist can prepend
    /// the artist itself, which is not playable. Callers should prefer a
    /// track seed — artist Instant Mix uses the artist's own Genres, which
    /// Jellyfin often leaves empty.
    func instantMixTracks(
        userID: String,
        itemID: String,
        limit: Int = 50
    ) async throws -> [Track] {
        let response = try await send(
            operation: "instant_mix_tracks",
            path: ["Items", itemID, "InstantMix"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "Limit", value: String(min(max(limit, 1), 100))),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Fields", value: "\(Self.audioIdentityFields),UserData"),
            ],
            as: ItemsResponse<Item>.self
        )
        return uniqueByID(response.Items.compactMap { item in
            guard item.`Type` == nil || item.`Type` == "Audio" else { return nil }
            return mapTrack(item)
        })
    }

    func searchMusic(
        userID: String,
        libraryID: String?,
        query searchTerm: String,
        startIndex: Int = 0,
        limit: Int = 40
    ) async throws -> MusicSearchPage {
        // Artists / albums / songs are library-scoped. Playlists are
        // user-global in Jellyfin and are not children of a music view, so
        // they are fetched without ParentId (first page only — mixed-type
        // pagination continues from the music items response).
        var musicQuery = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "SearchTerm", value: searchTerm),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicArtist,MusicAlbum,Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            // SortName keeps search-driven cache writes from erasing the
            // collation key the artist browse cache depends on. Track/album
            // fields power rich search rows (duration, artist, album art).
            URLQueryItem(
                name: "Fields",
                value: "PrimaryImageAspectRatio,SortName,RunTimeTicks,Album,AlbumId,AlbumArtist,Artists,ArtistItems,AlbumArtists,ArtistIds"
            ),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let libraryID {
            musicQuery.append(URLQueryItem(name: "ParentId", value: libraryID))
        }

        async let musicResponse = send(
            operation: "music_search",
            path: ["Items"],
            query: musicQuery,
            as: ItemsResponse<Item>.self
        )

        let playlists: [Playlist]
        if startIndex == 0 {
            playlists = try await searchPlaylists(userID: userID, searchTerm: searchTerm, limit: min(limit, 20))
        } else {
            playlists = []
        }

        let response = try await musicResponse
        let artists = response.Items.compactMap { item -> Artist? in
            guard item.`Type` == "MusicArtist" else { return nil }
            guard let identity = item.validatedIdentity else { return nil }
            return Artist(id: identity.id, name: identity.name, imageTag: item.ImageTags?["Primary"],
                          sortName: item.SortName?.nonEmpty)
        }
        let albums = response.Items.compactMap { item -> Album? in
            guard item.`Type` == "MusicAlbum" else { return nil }
            return mapAlbum(item)
        }
        let tracks = response.Items.compactMap { item -> Track? in
            guard item.`Type` == "Audio" else { return nil }
            return mapTrack(item)
        }
        let hasMore = response.receivedItemCount > 0
            && (response.TotalRecordCount.map { startIndex + response.receivedItemCount < $0 }
                ?? (response.receivedItemCount == limit))
        return MusicSearchPage(
            artists: artists,
            albums: albums,
            tracks: tracks,
            playlists: playlists,
            hasMore: hasMore,
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    /// Playlists are not scoped under a music library ParentId, so search
    /// hits them with a dedicated unscoped request.
    private func searchPlaylists(
        userID: String,
        searchTerm: String,
        limit: Int
    ) async throws -> [Playlist] {
        let query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "SearchTerm", value: searchTerm),
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,ChildCount"),
            URLQueryItem(name: "StartIndex", value: "0"),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        let response = try await send(
            operation: "music_search_playlists",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        return response.Items.compactMap { item -> Playlist? in
            guard item.`Type` == nil || item.`Type` == "Playlist",
                  let identity = item.validatedIdentity else { return nil }
            return Playlist(
                id: identity.id,
                name: identity.name,
                imageTag: item.ImageTags?["Primary"],
                itemCount: item.ChildCount
            )
        }
    }

    /// The full album-artist browse list, SortName-collated, for the Library
    /// Artists screen. AlbumArtists (not the plain Artists endpoint) mirrors
    /// Apple Music's Artists screen: album artists only, not every guest
    /// performer credited on a track.
    func artists(
        userID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> ArtistPage {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,SortName"),
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
            operation: "artists",
            path: ["Artists", "AlbumArtists"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        let artists = response.Items.compactMap { item -> Artist? in
            guard item.`Type` == nil || item.`Type` == "MusicArtist",
                  let identity = item.validatedIdentity else { return nil }
            return Artist(id: identity.id, name: identity.name, imageTag: item.ImageTags?["Primary"],
                          sortName: item.SortName?.nonEmpty)
        }
        return ArtistPage(
            artists: artists,
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func favouriteArtists(
        userID: String,
        libraryID: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> FavouriteArtistPage {
        let response = try await favouriteItems(
            operation: "favourite_artists",
            userID: userID,
            libraryID: libraryID,
            itemType: "MusicArtist",
            startIndex: startIndex,
            limit: limit
        )
        return FavouriteArtistPage(
            artists: response.Items.compactMap { item in
                guard item.isFavourite, item.`Type` == "MusicArtist",
                      let identity = item.validatedIdentity else { return nil }
                return Artist(id: identity.id, name: identity.name, imageTag: item.ImageTags?["Primary"],
                              sortName: item.SortName?.nonEmpty)
            },
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func favouriteAlbums(
        userID: String,
        libraryID: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> FavouriteAlbumPage {
        let response = try await favouriteItems(
            operation: "favourite_albums",
            userID: userID,
            libraryID: libraryID,
            itemType: "MusicAlbum",
            startIndex: startIndex,
            limit: limit
        )
        return FavouriteAlbumPage(
            albums: response.Items.compactMap { item in
                guard item.isFavourite, item.`Type` == "MusicAlbum" else { return nil }
                return mapAlbum(item)
            },
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func favouriteTracks(
        userID: String,
        libraryID: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> FavouriteTrackPage {
        let response = try await favouriteItems(
            operation: "favourite_tracks",
            userID: userID,
            libraryID: libraryID,
            itemType: "Audio",
            startIndex: startIndex,
            limit: limit
        )
        let occurrences = response.wireItems.enumerated().compactMap { offset, item -> FavouriteTrackOccurrence? in
            guard let item, item.isFavourite, item.`Type` == "Audio", let track = mapTrack(item) else {
                return nil
            }
            return FavouriteTrackOccurrence(id: "favourite:\(startIndex + offset):\(track.id)", track: track)
        }
        return FavouriteTrackPage(
            occurrences: occurrences,
            hasMore: hasMore(response: response, startIndex: startIndex, limit: limit),
            nextStartIndex: startIndex + response.receivedItemCount
        )
    }

    func setFavourite(userID: String, itemID: String, desired: Bool) async -> FavouriteMutationOutcome {
        do {
            var request = URLRequest(url: try makeURL(path: ["Users", userID, "FavoriteItems", itemID]))
            request.httpMethod = desired ? "POST" : "DELETE"
            addAuthorization(to: &request)
            _ = try await executeNoContent(request, operation: desired ? "favourite_set" : "favourite_clear")
            Diagnostics.event("favourite_mutation", ["operation": desired ? "favourite_set" : "favourite_clear", "outcome": "success", "retry_class": "none"])
            return .succeeded
        } catch is CancellationError { return .cancelled
        } catch let error as APIError {
            switch error {
            case .httpStatus(401), .httpStatus(403): return error == .httpStatus(401) ? .authenticationExpired : .permanent
            case .httpStatus(404): return .permanent
            case .httpStatus(let status) where status >= 500: return .transient
            default: return .transient
            }
        } catch { return .transient }
    }

    /// Current server-side favourite truth for a specific set of items, used to
    /// seed heart state on detail screens without paging a whole favourites list.
    /// Returns the subset of `itemIDs` the account has favourited.
    func favouriteStatus(userID: String, itemIDs: [String]) async throws -> Set<String> {
        let ids = itemIDs.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [] }
        let response = try await send(
            operation: "favourite_status",
            path: ["Users", userID, "Items"],
            query: [
                URLQueryItem(name: "Ids", value: ids.joined(separator: ",")),
                URLQueryItem(name: "Fields", value: "UserData"),
            ],
            as: ItemsResponse<Item>.self
        )
        return Set(response.Items.compactMap { item in
            guard item.isExplicitlyFavourite, let id = item.Id?.nonEmpty else { return nil }
            return id
        })
    }

    func playlists(
        userID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending"
    ) async throws -> PlaylistPage {
        let query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,ChildCount"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortOrder),
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

    func playlistRenameState(userID: String, playlistID: String) async throws -> PlaylistRenameRemoteState {
        let response = try await send(operation: "playlist_rename_read", path: ["Users", userID, "Items"], query: [URLQueryItem(name: "Ids", value: playlistID), URLQueryItem(name: "IncludeItemTypes", value: "Playlist")], as: ItemsResponse<Item>.self)
        guard let item = response.Items.first, let identity = item.validatedIdentity else { throw APIError.httpStatus(404) }
        return PlaylistRenameRemoteState(revision: "name:\(identity.name)", name: identity.name)
    }

    func renamePlaylist(userID: String, playlistID: String, expectedRevision: String, desiredName: String) async -> PlaylistRenameGatewayOutcome {
        do {
            let current = try await playlistRenameState(userID: userID, playlistID: playlistID)
            if current.revision == "name:\(desiredName)" { return .alreadyApplied }
            guard current.revision == expectedRevision else { return .conflict(current) }
            struct Body: Encodable { let Name: String }
            _ = try await sendNoContent(operation: "playlist_rename_write", path: ["Playlists", playlistID], method: "POST", body: Body(Name: desiredName))
            return .succeeded
        } catch is CancellationError { return .cancelled }
        catch APIError.httpStatus(401) { return .authenticationExpired }
        catch APIError.httpStatus(404) { return .notFound }
        catch APIError.httpStatus(403) { return .permissionDenied }
        catch APIError.httpStatus(let status) where status == 400 || status == 422 { return .validationFailed }
        catch { return .transient }
    }

    /// Library browse defaults to alphabetical `SortName`. Home's Listen Now
    /// shelf passes `sortBy: "Random"` for a fixed-size rotating sample —
    /// pagination belongs on the Library Genres screen, not the chip row.
    func genres(
        userID: String,
        libraryID: String?,
        startIndex: Int = 0,
        limit: Int = 100,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending"
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
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortOrder),
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
            URLQueryItem(name: "Fields", value: Self.albumIdentityFields),
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
            URLQueryItem(name: "Fields", value: Self.audioIdentityFields),
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
                URLQueryItem(name: "Fields", value: Self.audioIdentityFields),
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
            URLQueryItem(name: "Fields", value: Self.albumIdentityFields),
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

    /// The artist's most-played tracks, for the artist detail "Top Songs"
    /// shelf. Play-count order comes from the server's own user data.
    func artistTopTracks(
        userID: String,
        artistID: String,
        libraryID: String?,
        limit: Int = 5
    ) async throws -> [Track] {
        var query = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "ArtistIds", value: artistID),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: Self.audioIdentityFields),
            URLQueryItem(name: "StartIndex", value: "0"),
            URLQueryItem(name: "Limit", value: String(min(max(limit, 1), 25))),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
            URLQueryItem(name: "SortBy", value: "PlayCount,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
        ]
        if let libraryID {
            query.append(URLQueryItem(name: "ParentId", value: libraryID))
        }
        let response = try await send(
            operation: "artist_top_tracks",
            path: ["Items"],
            query: query,
            as: ItemsResponse<Item>.self
        )
        return uniqueByID(response.Items.compactMap { item in
            item.`Type` == nil || item.`Type` == "Audio" ? mapTrack(item) : nil
        })
    }

    /// Time-synced or plain lyrics for a track, or nil when the server has
    /// none (404). Jellyfin returns per-line timing at most — there is no
    /// per-word timing available.
    func lyrics(itemID: String) async throws -> TrackLyrics? {
        do {
            let response = try await send(
                operation: "lyrics",
                path: ["Audio", itemID, "Lyrics"],
                as: LyricResponse.self
            )
            let lines = response.Lyrics.enumerated().compactMap { index, raw -> LyricLine? in
                let text = raw.Text ?? ""
                // Jellyfin encodes line start as ticks (1 tick = 100ns).
                let start = raw.Start.map { Double($0) / 10_000_000 }
                // Per-word timing (Jellyfin 10.10+ `Cues`), if present.
                let words = (raw.Cues ?? []).compactMap { cue -> LyricWord? in
                    guard let cueStart = cue.Start else { return nil }
                    return LyricWord(
                        text: cue.Text ?? "",
                        startSeconds: Double(cueStart) / 10_000_000,
                        endSeconds: cue.End.map { Double($0) / 10_000_000 }
                    )
                }
                return LyricLine(index: index, text: text, startSeconds: start, words: words)
            }
            return lines.isEmpty ? nil : TrackLyrics(lines: lines)
        } catch APIError.httpStatus(404) {
            return nil
        }
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
                URLQueryItem(name: "Fields", value: Self.audioIdentityFields),
                URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ],
            as: ItemsResponse<Item>.self
        )
        return response.Items.compactMap(mapTrack).sorted(by: trackPrecedes)
    }

    /// Music-library catalog paging. The server's SortName/Id ordering is
    /// requested explicitly; the application repeats the same deterministic
    /// comparator when merging malformed, overlapping, or cached pages.
    func trackCatalogPage(
        userID: String,
        libraryID: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> TrackCatalogPage {
        let response = try await send(
            operation: "track_catalog",
            path: ["Items"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "ParentId", value: libraryID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: Self.audioIdentityFields),
                URLQueryItem(name: "StartIndex", value: String(max(0, startIndex))),
                URLQueryItem(name: "Limit", value: String(min(max(limit, 1), 200))),
                URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
                URLQueryItem(name: "SortBy", value: "SortName,Id"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ],
            as: ItemsResponse<Item>.self
        )
        let occurrences = response.wireItems.enumerated().compactMap { offset, item -> TrackCatalogOccurrence? in
            guard let item, item.`Type` == "Audio", let track = mapTrack(item) else { return nil }
            return TrackCatalogOccurrence(id: "track-catalog:\(startIndex + offset):\(track.id)", track: track, ordinal: startIndex + offset)
        }
        let page = TrackCatalogPage(
            occurrences: occurrences.sorted(by: TrackCatalogOrdering.precedes),
            hasMore: hasMore(response: response, startIndex: startIndex, limit: min(max(limit, 1), 200)),
            nextStartIndex: startIndex + response.receivedItemCount
        )
        return page
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

    /// Original-container audio for offline download. Header-authenticated so
    /// no token-bearing URL is ever persisted (ADR 0009).
    func audioDownloadRequest(itemID: String) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(
            path: ["Audio", itemID, "stream"],
            query: [URLQueryItem(name: "static", value: "true")]
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
        let artist = item.AlbumArtist?.nonEmpty ?? item.Artists?.first?.nonEmpty ?? "Unknown Artist"
        return Album(
            id: identity.id,
            name: identity.name,
            artist: artist,
            productionYear: item.ProductionYear,
            imageTag: item.ImageTags?["Primary"],
            artistID: item.albumArtistID(matching: artist)
        )
    }

    private func favouriteItems(
        operation: String,
        userID: String,
        libraryID: String,
        itemType: String,
        startIndex: Int,
        limit: Int
    ) async throws -> ItemsResponse<Item> {
        try await send(
            operation: operation,
            path: ["Items"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "ParentId", value: libraryID),
                URLQueryItem(name: "IncludeItemTypes", value: itemType),
                URLQueryItem(name: "IsFavorite", value: "true"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: "\(Self.audioIdentityFields),UserData"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            ],
            as: ItemsResponse<Item>.self
        )
    }

    private func homeShelfItems(
        operation: String,
        userID: String,
        libraryID: String,
        itemType: String,
        limit: Int,
        sortBy: String,
        extraQuery: [URLQueryItem] = []
    ) async throws -> ItemsResponse<Item> {
        try await send(
            operation: operation,
            path: ["Items"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "ParentId", value: libraryID),
                URLQueryItem(name: "IncludeItemTypes", value: itemType),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: "\(Self.audioIdentityFields),UserData"),
                URLQueryItem(name: "StartIndex", value: "0"),
                URLQueryItem(name: "Limit", value: String(homeShelfLimit(limit))),
                URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
                URLQueryItem(name: "SortBy", value: sortBy),
                URLQueryItem(name: "SortOrder", value: "Descending"),
            ] + extraQuery,
            as: ItemsResponse<Item>.self
        )
    }

    private func homeShelfLimit(_ requestedLimit: Int) -> Int {
        min(max(requestedLimit, 1), 100)
    }

    /// Fields that keep a mapped `Track` tied to its album and artist items.
    /// Jellyfin returns those IDs on `AlbumId` / `ArtistItems` / `AlbumArtists`;
    /// display names alone cannot open the library destination.
    private static let audioIdentityFields =
        "PrimaryImageAspectRatio,RunTimeTicks,Album,AlbumId,AlbumArtist,Artists,ArtistItems,AlbumArtists,ArtistIds,IndexNumber,ParentIndexNumber"

    /// Fields that keep a mapped `Album` tied to its album-artist library item.
    private static let albumIdentityFields =
        "PrimaryImageAspectRatio,AlbumArtist,Artists,AlbumArtists,ArtistItems,ArtistIds"

    private func uniqueByID<Value: Identifiable>(_ values: [Value]) -> [Value] where Value.ID == String {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func mapTrack(_ item: Item) -> Track? {
        guard let identity = item.validatedIdentity else { return nil }
        let artist = item.displayedArtistName
        return Track(
            id: identity.id,
            name: identity.name,
            artist: artist,
            album: item.Album?.nonEmpty ?? "",
            albumID: item.AlbumId?.nonEmpty,
            index: item.IndexNumber,
            disc: item.ParentIndexNumber,
            durationTicks: item.RunTimeTicks,
            artistID: item.artistID(matching: artist),
            imageTag: item.ImageTags?["Primary"]
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

    private func sendNoContent<Body: Encodable>(operation: String, path: [String], method: String, body: Body) async throws -> Int {
        var request = URLRequest(url: try makeURL(path: path)); request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); addAuthorization(to: &request)
        return try await executeNoContent(request, operation: operation)
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
            "MediaBrowser Client=\"Jellytone\", Device=\"Apple Mobile\", DeviceId=\"\(deviceID)\", Version=\"1.0.0\"",
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
    private struct UserData: Decodable {
        let IsFavorite: Bool?
    }

    /// Jellyfin `NameGuidPair` — artist/album-artist identity on Audio items.
    private struct NameIdPair: Decodable {
        let Name: String?
        let Id: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            Name = container.lossy(String.self, forKey: .Name)
            Id = container.lossy(String.self, forKey: .Id)
        }

        private enum CodingKeys: String, CodingKey { case Name, Id }
    }

    let Id: String?
    let Name: String?
    let SortName: String?
    let `Type`: String?
    let CollectionType: String?
    let AlbumArtist: String?
    let Artists: [String]?
    // NameIdPair is private, so these decoded fields stay private too.
    // Callers use artistID(matching:) and albumArtistID(matching:).
    private let ArtistItems: [NameIdPair]?
    private let AlbumArtists: [NameIdPair]?
    let ArtistIds: [String]?
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
    private let userData: UserData?

    var isFavourite: Bool {
        // IsFavorite=true was requested. Missing UserData remains compatible
        // with older Jellyfin responses; an explicit false is contradictory.
        userData?.IsFavorite != false
    }

    /// Strict favourite truth for status reads over an unfiltered item set,
    /// where a missing or false UserData flag means "not favourited".
    var isExplicitlyFavourite: Bool {
        userData?.IsFavorite == true
    }

    var validatedIdentity: (id: String, name: String)? {
        guard let id = Id?.nonEmpty, let name = Name?.nonEmpty else { return nil }
        return (id, name)
    }

    var displayedArtistName: String {
        Artists?.first?.nonEmpty ?? AlbumArtist?.nonEmpty ?? "Unknown Artist"
    }

    /// Prefer the ID that matches the displayed artist name so compilations
    /// open the track artist, not "Various Artists". Fall back through album
    /// artists, then a legacy `ArtistIds` array some payloads still send.
    func artistID(matching name: String) -> String? {
        id(matching: name, in: ArtistItems)
            ?? ArtistItems?.first?.Id?.nonEmpty
            ?? id(matching: name, in: AlbumArtists)
            ?? AlbumArtists?.first?.Id?.nonEmpty
            ?? ArtistIds?.first?.nonEmpty
    }

    /// Prefer album-artist IDs so album headers open the album artist, not a
    /// featured track performer. Fall back through track artists, then legacy IDs.
    func albumArtistID(matching name: String) -> String? {
        id(matching: name, in: AlbumArtists)
            ?? AlbumArtists?.first?.Id?.nonEmpty
            ?? id(matching: name, in: ArtistItems)
            ?? ArtistItems?.first?.Id?.nonEmpty
            ?? ArtistIds?.first?.nonEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Id = container.lossy(String.self, forKey: .Id)
        Name = container.lossy(String.self, forKey: .Name)
        SortName = container.lossy(String.self, forKey: .SortName)
        Type = container.lossy(String.self, forKey: .Type)
        CollectionType = container.lossy(String.self, forKey: .CollectionType)
        AlbumArtist = container.lossy(String.self, forKey: .AlbumArtist)
        Artists = container.lossy([String].self, forKey: .Artists)
        ArtistItems = container.lossy([NameIdPair].self, forKey: .ArtistItems)
        AlbumArtists = container.lossy([NameIdPair].self, forKey: .AlbumArtists)
        ArtistIds = container.lossy([String].self, forKey: .ArtistIds)
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
        userData = container.lossy(UserData.self, forKey: .UserData)
    }

    private func id(matching name: String, in pairs: [NameIdPair]?) -> String? {
        pairs?.first(where: { $0.Name?.nonEmpty == name })?.Id?.nonEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case Id, Name, SortName, `Type`, CollectionType, AlbumArtist, Artists, ArtistItems, AlbumArtists, ArtistIds
        case Album, AlbumId
        case ProductionYear, ImageTags, IndexNumber, ParentIndexNumber, RunTimeTicks
        case ChildCount, RecursiveItemCount, SongCount, AlbumCount, PlaylistItemId, UserData
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

private struct LyricResponse: Decodable {
    struct Cue: Decodable {
        let Text: String?
        let Start: Int64?
        let End: Int64?
    }
    struct Line: Decodable {
        let Text: String?
        let Start: Int64?
        let Cues: [Cue]?
    }
    let Lyrics: [Line]
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

extension JellyfinAPI: FavouriteWriteGateway {}
