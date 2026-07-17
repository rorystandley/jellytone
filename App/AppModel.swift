import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: UserSession?
    @Published private(set) var libraries: [MusicLibrary] = []
    @Published var selectedLibraryID: String?
    @Published private(set) var albums: [Album] = []
    @Published private(set) var tracksByAlbum: [String: [Track]] = [:]
    @Published private(set) var homeSnapshot: HomeShelfSnapshot?
    @Published private(set) var isRefreshingHome = false
    @Published private(set) var homeRefreshError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMoreAlbums = false
    @Published var errorMessage: String?

    let playback: PlaybackController

    private let defaults: UserDefaults
    private let libraryStore: (any LibraryStoring)?
    private static let profileKey = "active-profile"
    private static let deviceIDKey = "installation-device-id"
    private var hasMoreAlbums = true
    private var albumLibraryID: String?
    private var nextAlbumStartIndex = 0
    private var homeRefreshGeneration = 0

    init(defaults: UserDefaults = .standard, libraryStore: (any LibraryStoring)? = nil) {
        self.defaults = defaults
        self.libraryStore = libraryStore ?? Self.makeDefaultLibraryStore()
        self.playback = PlaybackController(defaults: defaults)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            defaults.removeObject(forKey: Self.profileKey)
            KeychainTokenStore.delete()
        }
        if defaults.string(forKey: Self.deviceIDKey) == nil {
            defaults.set(UUID().uuidString, forKey: Self.deviceIDKey)
        }
#if DEBUG
        if arguments.contains("--ui-testing-music-shell")
            || arguments.contains("--ui-testing-playlists")
            || arguments.contains("--ui-testing-genres")
            || arguments.contains("--ui-testing-favourites") {
            configureUITestMusicShell()
            return
        }
#endif
        restoreSession()
    }

    var api: JellyfinAPI? {
        guard let session else { return nil }
        return JellyfinAPI(baseURL: session.serverURL, deviceID: session.deviceID, token: session.accessToken)
    }

    func connect(server: String, username: String, password: String) async {
        Diagnostics.event("connect_started")
        guard let serverURL = normalizedServerURL(server) else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let deviceID = installationDeviceID
            let unauthenticated = JellyfinAPI(baseURL: serverURL, deviceID: deviceID)
            let info = try await unauthenticated.publicInfo()
            let authentication = try await unauthenticated.authenticate(username: username, password: password)
            Diagnostics.event("authentication_succeeded")
            try KeychainTokenStore.save(authentication.token)
            let session = UserSession(
                serverURL: serverURL,
                serverID: info.id,
                serverName: info.serverName,
                serverVersion: info.version,
                userID: authentication.userID,
                username: authentication.username,
                accessToken: authentication.token,
                deviceID: deviceID
            )
            homeRefreshGeneration += 1
            homeSnapshot = nil
            homeRefreshError = nil
            self.session = session
            persistProfile(session)
            try await refreshLibraries()
        } catch {
            let failure = error as NSError
            Diagnostics.event("connect_failed", ["code": failure.code, "domain": failure.domain])
            errorMessage = error.localizedDescription
        }
    }

    func refreshLibraries() async throws {
        guard let session, let api else { return }
        Diagnostics.event("library_refresh_started")
        libraries = try await api.musicLibraries(userID: session.userID)
        Diagnostics.event("music_views_loaded", ["count": libraries.count])
        if selectedLibraryID == nil || !libraries.contains(where: { $0.id == selectedLibraryID }) {
            selectedLibraryID = libraries.first?.id
        }
        persistProfile(session)
        try await refreshAlbums(libraryID: selectedLibraryID)
        Task { await refreshHomeShelves() }
    }

    func refreshAlbums(libraryID: String?) async throws {
        guard let session, let api else { return }
        isLoading = true
        defer { isLoading = false }
        albumLibraryID = libraryID
        let page = try await CacheFirstAlbumRefresh.execute(
            scope: libraryScope(for: session),
            libraryID: libraryID,
            store: libraryStore,
            present: { albums = $0 }
        ) {
            try await api.albums(userID: session.userID, libraryID: libraryID)
        }
        hasMoreAlbums = page.hasMore
        nextAlbumStartIndex = page.nextStartIndex
        Diagnostics.event("albums_loaded", ["count": albums.count, "has_more": page.hasMore, "scoped": libraryID != nil])
    }

    func loadMoreAlbumsIfNeeded(after album: Album) async {
        guard album.id == albums.last?.id, hasMoreAlbums, !isLoadingMoreAlbums,
              let session, let api else { return }
        isLoadingMoreAlbums = true
        defer { isLoadingMoreAlbums = false }
        do {
            let page = try await api.albums(
                userID: session.userID,
                libraryID: albumLibraryID,
                startIndex: nextAlbumStartIndex
            )
            let existing = Set(albums.map(\.id))
            albums.append(contentsOf: page.albums.filter { !existing.contains($0.id) })
            try? await libraryStore?.storeSearchMetadata(
                artists: [],
                albums: page.albums,
                scope: libraryScope(for: session),
                libraryID: albumLibraryID
            )
            hasMoreAlbums = page.hasMore
            nextAlbumStartIndex = page.nextStartIndex
            Diagnostics.event("albums_page_loaded", ["count": page.albums.count, "total": albums.count])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectLibrary(_ id: String) async {
        guard selectedLibraryID != id else { return }
        homeRefreshGeneration += 1
        homeSnapshot = nil
        homeRefreshError = nil
        selectedLibraryID = id
        if let session { persistProfile(session) }
        do { try await refreshAlbums(libraryID: id) }
        catch { errorMessage = error.localizedDescription }
        await refreshHomeShelves()
    }

    /// Shows the scoped database snapshot first, then replaces only the shelves
    /// whose current, music-library-scoped request completed successfully.
    func refreshHomeShelves() async {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-home") {
            if arguments.contains("--ui-testing-home-loading") {
                isRefreshingHome = true
                try? await Task.sleep(for: .seconds(5))
                return
            }
            if arguments.contains("--ui-testing-home-empty") {
                homeSnapshot = .empty
                isRefreshingHome = false
                homeRefreshError = nil
                return
            }
            if arguments.contains("--ui-testing-home-error") {
                homeSnapshot = nil
                isRefreshingHome = false
                homeRefreshError = "Recently added albums couldn’t be refreshed."
                return
            }
            if arguments.contains("--ui-testing-home-cached-partial-error") {
                homeSnapshot = Self.syntheticHomeSnapshot(albumID: "home-album-cached")
                isRefreshingHome = true
                homeRefreshError = "Recently played music couldn’t be refreshed."
                return
            }
            isRefreshingHome = false
            homeRefreshError = nil
            return
        }
#endif
        guard let session, let api, let libraryID = selectedLibraryID else { return }
        let scope = libraryScope(for: session)
        let requestScope = HomeFeatureScope(serverID: scope.serverID, accountID: scope.accountID, libraryID: libraryID)
        homeRefreshGeneration += 1
        let generation = homeRefreshGeneration
        isRefreshingHome = true
        homeRefreshError = nil

        if homeSnapshot == nil,
           let cached = try? await libraryStore?.cachedHomeShelfSnapshot(scope: scope, libraryID: libraryID),
           ownsHomeRefresh(generation, scope: requestScope) {
            homeSnapshot = cached
        }

        async let added = homeAlbumsResult(api: api, userID: session.userID, libraryID: libraryID)
        async let played = homeTracksResult(api: api, userID: session.userID, libraryID: libraryID)
        let addedResult = await added
        let playedResult = await played
        guard ownsHomeRefresh(generation, scope: requestScope) else { return }

        var replacement = homeSnapshot ?? .empty
        var errors: [String] = []
        switch addedResult {
        case let .success(albums): replacement = HomeShelfSnapshot(recentlyAddedAlbums: albums, recentlyPlayedTracks: replacement.recentlyPlayedTracks)
        case .failure: errors.append("Recently added albums couldn’t be refreshed.")
        }
        switch playedResult {
        case let .success(tracks): replacement = HomeShelfSnapshot(recentlyAddedAlbums: replacement.recentlyAddedAlbums, recentlyPlayedTracks: tracks)
        case .failure: errors.append("Recently played music couldn’t be refreshed.")
        }
        homeSnapshot = replacement
        if case .success = addedResult { try? await libraryStore?.replaceHomeShelfSnapshot(replacement, scope: scope, libraryID: libraryID) }
        else if case .success = playedResult { try? await libraryStore?.replaceHomeShelfSnapshot(replacement, scope: scope, libraryID: libraryID) }
        homeRefreshError = errors.isEmpty ? nil : errors.joined(separator: " ")
        isRefreshingHome = false
    }

    func tracks(for album: Album) async -> [Track] {
        if let existing = tracksByAlbum[album.id] { return existing }
        guard let session, let api else { return [] }
        do {
            let tracks = try await api.tracks(userID: session.userID, albumID: album.id)
            tracksByAlbum[album.id] = tracks
            return tracks
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func searchMusic(query: String, startIndex: Int = 0) async throws -> MusicSearchPage {
        guard let session, let api else { throw APIError.notAuthenticated }
        let scope = libraryScope(for: session)
        return try await CacheBackedMusicSearch.execute(
            query: query,
            startIndex: startIndex,
            scope: scope,
            libraryID: selectedLibraryID,
            store: libraryStore
        ) {
            try await api.searchMusic(
                userID: session.userID,
                libraryID: selectedLibraryID,
                query: query,
                startIndex: startIndex
            )
        }
    }

    func albums(for artist: Artist, startIndex: Int = 0) async throws -> AlbumPage {
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.albums(
            userID: session.userID,
            artistID: artist.id,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
    }

    func playlistPage(startIndex: Int = 0) async throws -> PlaylistPage {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-playlists-error") { throw APIError.httpStatus(503) }
        if arguments.contains("--ui-testing-playlists-empty") {
            return PlaylistPage(playlists: [], hasMore: false, nextStartIndex: 0)
        }
        if arguments.contains("--ui-testing-playlists") {
            let playlists = [
                Playlist(id: "playlist-road", name: "Road Mix 🎧", imageTag: nil, itemCount: 3),
                Playlist(id: "playlist-empty", name: "Quiet Queue", imageTag: nil, itemCount: 0),
                Playlist(id: "playlist-nonplayable", name: "Unsupported Items", imageTag: nil, itemCount: 2),
            ]
            return PlaylistPage(playlists: startIndex == 0 ? playlists : [], hasMore: false,
                                nextStartIndex: playlists.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.playlists(
            userID: session.userID,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
    }

    func playlistEntries(for playlist: Playlist, startIndex: Int = 0) async throws -> PlaylistEntryPage {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-playlists") {
            let duplicate = Track(id: "track-shared", name: "Repeated Song", artist: "Synthetic Artist",
                                  album: "Synthetic Playlist Album", index: nil, disc: nil,
                                  durationTicks: 1_800_000_000)
            let entries = ["playlist-empty", "playlist-nonplayable"].contains(playlist.id) ? [] : [
                PlaylistEntry(id: "occurrence-1", track: duplicate),
                PlaylistEntry(id: "occurrence-2", track: Track(
                    id: "track-unicode", name: "夜の音", artist: "Unknown Artist",
                    album: "Unknown Album", index: nil, disc: nil, durationTicks: nil
                )),
                PlaylistEntry(id: "occurrence-3", track: duplicate),
            ]
            return PlaylistEntryPage(entries: startIndex == 0 ? entries : [], hasMore: false,
                                     nextStartIndex: entries.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.playlistEntries(
            userID: session.userID,
            playlistID: playlist.id,
            startIndex: startIndex
        )
    }

    func genrePage(startIndex: Int = 0) async throws -> GenrePage {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-genres-loading") {
            try await Task.sleep(for: .seconds(5))
        }
        if arguments.contains("--ui-testing-genres-error") { throw APIError.httpStatus(503) }
        if arguments.contains("--ui-testing-genres-pagination-error"), startIndex > 0 {
            throw APIError.httpStatus(503)
        }
        if arguments.contains("--ui-testing-genres-empty") {
            return GenrePage(genres: [], hasMore: false, nextStartIndex: 0)
        }
        if arguments.contains("--ui-testing-genres") {
            let genres = [
                Genre(id: "genre-rock", name: "Rock", imageTag: nil, itemCount: 4, albumCount: 2),
                Genre(id: "genre-rock-b", name: "Rock", imageTag: nil, itemCount: 1, albumCount: 1),
                Genre(id: "genre-empty", name: "日本の音楽 🎧", imageTag: nil, itemCount: 0, albumCount: 0),
                Genre(id: "genre-nonplayable", name: "Unsupported Collection", imageTag: nil,
                      itemCount: 2, albumCount: 0),
            ]
            if arguments.contains("--ui-testing-genres-pagination-error") {
                return GenrePage(genres: startIndex == 0 ? [genres[0]] : [], hasMore: startIndex == 0,
                                 nextStartIndex: startIndex == 0 ? 1 : startIndex)
            }
            return GenrePage(genres: startIndex == 0 ? genres : [], hasMore: false,
                             nextStartIndex: genres.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.genres(
            userID: session.userID,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
    }

    func genreAlbums(for genre: Genre, startIndex: Int = 0) async throws -> AlbumPage {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-genres") {
            let albums = [
                Album(id: "genre-album-1", name: "Synthetic Compilation", artist: "Various Artists",
                      productionYear: 2026, imageTag: nil),
                Album(id: "genre-album-2", name: "Second Record", artist: "Synthetic Artist",
                      productionYear: nil, imageTag: nil),
            ]
            let values = ["genre-empty", "genre-nonplayable"].contains(genre.id) ? [] : albums
            return AlbumPage(albums: startIndex == 0 ? values : [], hasMore: false,
                             nextStartIndex: values.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.genreAlbums(
            userID: session.userID,
            genreID: genre.id,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
    }

    func genreTracks(for genre: Genre, startIndex: Int = 0) async throws -> GenreTrackPage {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-genres") {
            let duplicate = Track(id: "genre-track-shared", name: "Repeated Song", artist: "Synthetic Artist",
                                  album: "Synthetic Compilation", albumID: "genre-album-1", index: 1, disc: 1,
                                  durationTicks: 1_800_000_000)
            let occurrences = ["genre-empty", "genre-nonplayable"].contains(genre.id) ? [] : [
                GenreTrackOccurrence(id: "genre-occurrence-1", track: duplicate),
                GenreTrackOccurrence(id: "genre-occurrence-2", track: Track(
                    id: "genre-track-unicode", name: "夜の音", artist: "Unknown Artist",
                    album: "Synthetic Compilation", albumID: "genre-album-1", index: 2, disc: 2,
                    durationTicks: nil
                )),
                GenreTrackOccurrence(id: "genre-occurrence-3", track: duplicate),
            ]
            return GenreTrackPage(occurrences: startIndex == 0 ? occurrences : [], hasMore: false,
                                  nextStartIndex: occurrences.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.genreTracks(
            userID: session.userID,
            genreID: genre.id,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
    }

    func favouriteArtistsPage(startIndex: Int = 0) async throws -> FavouriteArtistPage {
#if DEBUG
        try await favouriteUITestDelayIfNeeded(startIndex: startIndex)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-error") {
            throw APIError.httpStatus(503)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-empty") {
            return FavouriteArtistPage(artists: [], hasMore: false, nextStartIndex: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites") {
            let artists = [
                Artist(id: "artist-favourite", name: "Favourite Artist", imageTag: nil),
                Artist(id: "artist-favourite-duplicate-name", name: "Favourite Artist", imageTag: nil),
            ]
            return FavouriteArtistPage(artists: startIndex == 0 ? artists : [], hasMore: false,
                                       nextStartIndex: artists.count)
        }
#endif
        guard let session, let api, let libraryID = selectedLibraryID else { throw APIError.notAuthenticated }
        return try await api.favouriteArtists(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
    }

    func favouriteAlbumsPage(startIndex: Int = 0) async throws -> FavouriteAlbumPage {
#if DEBUG
        try await favouriteUITestDelayIfNeeded(startIndex: startIndex)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-error") {
            throw APIError.httpStatus(503)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-empty") {
            return FavouriteAlbumPage(albums: [], hasMore: false, nextStartIndex: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites") {
            let albums = [
                Album(id: "album-favourite", name: "Favourite Album", artist: "Favourite Artist",
                      productionYear: 2026, imageTag: nil),
                Album(id: "album-favourite-compilation", name: "Favourite Album", artist: "Various Artists",
                      productionYear: nil, imageTag: nil),
            ]
            return FavouriteAlbumPage(albums: startIndex == 0 ? albums : [], hasMore: false,
                                      nextStartIndex: albums.count)
        }
#endif
        guard let session, let api, let libraryID = selectedLibraryID else { throw APIError.notAuthenticated }
        return try await api.favouriteAlbums(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
    }

    func favouriteTracksPage(startIndex: Int = 0) async throws -> FavouriteTrackPage {
#if DEBUG
        try await favouriteUITestDelayIfNeeded(startIndex: startIndex)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-error") {
            throw APIError.httpStatus(503)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-empty") {
            return FavouriteTrackPage(occurrences: [], hasMore: false, nextStartIndex: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites") {
            let duplicate = Track(id: "track-favourite-shared", name: "Repeated Favourite", artist: "Favourite Artist",
                                  album: "Favourite Album", albumID: "album-favourite", index: 1, disc: 1,
                                  durationTicks: 1_800_000_000)
            let occurrences = [
                FavouriteTrackOccurrence(id: "favourite-occurrence-1", track: duplicate),
                FavouriteTrackOccurrence(id: "favourite-occurrence-2", track: Track(
                    id: "track-favourite-unicode", name: "夜の音", artist: "Unknown Artist", album: "Favourite Album",
                    albumID: "album-favourite", index: 2, disc: 2, durationTicks: nil
                )),
                FavouriteTrackOccurrence(id: "favourite-occurrence-3", track: duplicate),
            ]
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-favourites-pagination-error") {
                if startIndex > 0 { throw APIError.httpStatus(503) }
                return FavouriteTrackPage(occurrences: [occurrences[0]], hasMore: true, nextStartIndex: 1)
            }
            return FavouriteTrackPage(occurrences: startIndex == 0 ? occurrences : [], hasMore: false,
                                      nextStartIndex: occurrences.count)
        }
#endif
        guard let session, let api, let libraryID = selectedLibraryID else { throw APIError.notAuthenticated }
        return try await api.favouriteTracks(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
    }

    func play(_ track: Track, in queue: [Track]) {
        guard let api, let session else { return }
        playback.play(
            track,
            queue: queue,
            using: api,
            userID: session.userID,
            scope: playbackScope(for: session)
        )
    }

    func play(_ entry: PlaylistEntry, in playlistEntries: [PlaylistEntry]) {
        guard let api, let session,
              let selectedIndex = playlistEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        let queue = playlistEntries.map { QueueEntry(track: $0.track) }
        playback.play(
            entries: queue,
            startingAt: queue[selectedIndex].id,
            using: api,
            userID: session.userID,
            scope: playbackScope(for: session)
        )
    }

    func playAll(_ playlistEntries: [PlaylistEntry]) {
        guard let first = playlistEntries.first else { return }
        play(first, in: playlistEntries)
    }

    func shuffle(_ playlistEntries: [PlaylistEntry]) {
        guard !playlistEntries.isEmpty else { return }
        playAll(playlistEntries)
        playback.toggleShuffle()
    }

    func play(_ occurrence: GenreTrackOccurrence, in occurrences: [GenreTrackOccurrence]) {
        guard let api, let session,
              let selectedIndex = occurrences.firstIndex(where: { $0.id == occurrence.id }) else { return }
        let queue = occurrences.map { QueueEntry(track: $0.track) }
        playback.play(
            entries: queue,
            startingAt: queue[selectedIndex].id,
            using: api,
            userID: session.userID,
            scope: playbackScope(for: session)
        )
    }

    func playAll(_ occurrences: [GenreTrackOccurrence]) {
        guard let first = occurrences.first else { return }
        play(first, in: occurrences)
    }

    func shuffle(_ occurrences: [GenreTrackOccurrence]) {
        guard !occurrences.isEmpty else { return }
        playAll(occurrences)
        playback.toggleShuffle()
    }

    func play(_ occurrence: FavouriteTrackOccurrence, in occurrences: [FavouriteTrackOccurrence]) {
        guard let api, let session,
              let selectedIndex = occurrences.firstIndex(where: { $0.id == occurrence.id }) else { return }
        let queue = occurrences.map { QueueEntry(track: $0.track) }
        playback.play(
            entries: queue,
            startingAt: queue[selectedIndex].id,
            using: api,
            userID: session.userID,
            scope: playbackScope(for: session)
        )
    }

    func playAll(_ occurrences: [FavouriteTrackOccurrence]) {
        guard let first = occurrences.first else { return }
        play(first, in: occurrences)
    }

    func shuffle(_ occurrences: [FavouriteTrackOccurrence]) {
        guard !occurrences.isEmpty else { return }
        playAll(occurrences)
        playback.toggleShuffle()
    }

    func playNext(_ track: Track) {
        playback.playNext(track)
    }

    func addToQueue(_ track: Track) {
        playback.addToQueue(track)
    }

    func logout() async {
        await playback.stopAndWait()
        KeychainTokenStore.delete()
        defaults.removeObject(forKey: Self.profileKey)
        session = nil
        libraries = []
        albums = []
        homeSnapshot = nil
        homeRefreshGeneration += 1
        isRefreshingHome = false
        homeRefreshError = nil
        nextAlbumStartIndex = 0
        tracksByAlbum = [:]
        selectedLibraryID = nil
    }

    private var installationDeviceID: String {
        defaults.string(forKey: Self.deviceIDKey) ?? "jellyfin-audio-installation"
    }

    private func normalizedServerURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.host != nil else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func persistProfile(_ session: UserSession) {
        struct Profile: Codable {
            let serverURL: URL
            let serverID: String
            let serverName: String
            let serverVersion: String
            let userID: String
            let username: String
            let deviceID: String
            let selectedLibraryID: String?
        }
        let profile = Profile(serverURL: session.serverURL, serverID: session.serverID,
                              serverName: session.serverName, serverVersion: session.serverVersion,
                              userID: session.userID, username: session.username, deviceID: session.deviceID,
                              selectedLibraryID: selectedLibraryID)
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.profileKey) }
    }

    private func restoreSession() {
        struct Profile: Codable {
            let serverURL: URL
            let serverID: String
            let serverName: String
            let serverVersion: String
            let userID: String
            let username: String
            let deviceID: String
            let selectedLibraryID: String?
        }
        guard let data = defaults.data(forKey: Self.profileKey),
              let profile = try? JSONDecoder().decode(Profile.self, from: data),
              let token = KeychainTokenStore.load() else { return }
        session = UserSession(serverURL: profile.serverURL, serverID: profile.serverID,
                              serverName: profile.serverName, serverVersion: profile.serverVersion,
                              userID: profile.userID, username: profile.username,
                              accessToken: token, deviceID: profile.deviceID)
        selectedLibraryID = profile.selectedLibraryID
        Diagnostics.event("session_restored")
        if let session, let api {
            playback.restore(using: api, userID: session.userID, scope: playbackScope(for: session))
        }
        Task {
            if let session {
                await loadCachedAlbums(for: session, libraryID: selectedLibraryID)
                await loadCachedHomeShelves(for: session, libraryID: selectedLibraryID)
            }
            do { try await refreshLibraries() }
            catch {
                let failure = error as NSError
                Diagnostics.event("restore_refresh_failed", ["code": failure.code, "domain": failure.domain])
                errorMessage = error.localizedDescription
            }
        }
    }

    private func playbackScope(for session: UserSession) -> String {
        "\(session.serverID):\(session.userID)"
    }

    private func libraryScope(for session: UserSession) -> LibraryScope {
        LibraryScope(serverID: session.serverID, accountID: session.userID)
    }

    private func loadCachedAlbums(for session: UserSession, libraryID: String?) async {
        guard let cached = try? await libraryStore?.cachedAlbums(
            scope: libraryScope(for: session),
            libraryID: libraryID
        ) else { return }
        albums = cached
    }

    private func loadCachedHomeShelves(for session: UserSession, libraryID: String?) async {
        guard let cached = try? await libraryStore?.cachedHomeShelfSnapshot(
            scope: libraryScope(for: session), libraryID: libraryID
        ) else { return }
        homeSnapshot = cached
    }

    private func ownsHomeRefresh(_ generation: Int, scope: HomeFeatureScope) -> Bool {
        guard let session else { return false }
        return homeRefreshGeneration == generation
            && HomeFeatureScope(serverID: session.serverID, accountID: session.userID, libraryID: selectedLibraryID) == scope
    }

    private enum HomeQueryResult<Value: Sendable>: Sendable {
        case success(Value)
        case failure
    }

    private func homeAlbumsResult(api: JellyfinAPI, userID: String, libraryID: String) async -> HomeQueryResult<[Album]> {
        do { return .success(try await api.recentlyAddedAlbums(userID: userID, libraryID: libraryID)) }
        catch { return .failure }
    }

    private func homeTracksResult(api: JellyfinAPI, userID: String, libraryID: String) async -> HomeQueryResult<[Track]> {
        do { return .success(try await api.recentlyPlayedTracks(userID: userID, libraryID: libraryID)) }
        catch { return .failure }
    }

    private static func makeDefaultLibraryStore() -> (any LibraryStoring)? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = support.appendingPathComponent("JellyfinAudio", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try SQLiteLibraryStore(databaseURL: directory.appendingPathComponent("library.sqlite"))
        } catch {
            return nil
        }
    }

#if DEBUG
    private func favouriteUITestDelayIfNeeded(startIndex: Int) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-favourites-loading"), startIndex == 0 {
            try await Task.sleep(for: .seconds(5))
        }
    }

    private func configureUITestMusicShell() {
        guard let serverURL = URL(string: "https://example.invalid") else { return }
        session = UserSession(
            serverURL: serverURL,
            serverID: "synthetic-server",
            serverName: "Synthetic Jellyfin",
            serverVersion: "test",
            userID: "synthetic-user",
            username: "Listener",
            accessToken: "synthetic-token",
            deviceID: "synthetic-device"
        )
        libraries = [MusicLibrary(id: "music", name: "Music")]
        selectedLibraryID = "music"
        playback.configureForUITesting(track: Track(
            id: "track",
            name: "Visible Mini Player",
            artist: "Synthetic Artist",
            album: "Synthetic Album",
            index: 1,
            disc: 1,
            durationTicks: 1_800_000_000
        ), upcoming: [
            Track(id: "next-1", name: "First Up Next", artist: "Synthetic Artist",
                  album: "Synthetic Album", index: 2, disc: 1, durationTicks: 1_800_000_000),
            Track(id: "next-2", name: "Second Up Next", artist: "Synthetic Artist",
                  album: "Synthetic Album", index: 3, disc: 1, durationTicks: 1_800_000_000),
        ], elapsed: ProcessInfo.processInfo.arguments.contains("--ui-testing-restored-playback") ? 73 : 0)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-home") {
            homeSnapshot = Self.syntheticHomeSnapshot(albumID: "home-album-new")
        }
    }

    private static func syntheticHomeSnapshot(albumID: String) -> HomeShelfSnapshot {
        HomeShelfSnapshot(
            recentlyAddedAlbums: [Album(id: albumID, name: "New Album", artist: "Synthetic Artist", productionYear: 2026, imageTag: nil)],
            recentlyPlayedTracks: [Track(id: "home-track-1", name: "Recently Played", artist: "Synthetic Artist", album: "New Album", albumID: albumID, index: 1, disc: 1, durationTicks: 1_800_000_000)]
        )
    }
#endif
}
