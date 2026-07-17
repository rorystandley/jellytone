import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: UserSession?
    @Published private(set) var libraries: [MusicLibrary] = []
    @Published var selectedLibraryID: String?
    @Published private(set) var albums: [Album] = []
    @Published private(set) var tracksByAlbum: [String: [Track]] = [:]
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
        if arguments.contains("--ui-testing-music-shell") || arguments.contains("--ui-testing-playlists") {
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
        selectedLibraryID = id
        if let session { persistProfile(session) }
        do { try await refreshAlbums(libraryID: id) }
        catch { errorMessage = error.localizedDescription }
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
            if let session { await loadCachedAlbums(for: session, libraryID: selectedLibraryID) }
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
    }
#endif
}
