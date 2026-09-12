import Foundation
import UIKit

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
    @Published private(set) var trackCatalogState = TrackCatalogState()
    @Published var errorMessage: String?

    let playback: PlaybackController
    let downloads: DownloadManager
    let recentAudio = RecentAudioCache()

    private let defaults: UserDefaults
    private let libraryStore: (any LibraryStoring)?
    private static let profileKey = "active-profile"
    private static let deviceIDKey = "installation-device-id"
    private var hasMoreAlbums = true
    private var albumLibraryID: String?
    private var nextAlbumStartIndex = 0
    private var homeRefreshGeneration = 0
    private var trackCatalogGeneration = 0
    /// Effective favourite ("like") state for songs, albums, and artists, driven
    /// by the registry so views can observe it. See [[FavouriteRegistry]].
    @Published private(set) var favouriteItemIDs: Set<String> = []
    private let favouriteReconciler: FavouriteReconciler?
    private var favouriteRegistry = FavouriteRegistry() {
        didSet { favouriteItemIDs = favouriteRegistry.favourites }
    }
    private var favouriteSequence: Int64 = 0

    init(defaults: UserDefaults = .standard, libraryStore: (any LibraryStoring)? = nil) {
        self.defaults = defaults
        self.libraryStore = libraryStore ?? Self.makeDefaultLibraryStore()
        self.favouriteReconciler = self.libraryStore.map { FavouriteReconciler(store: $0) }
        self.playback = PlaybackController(defaults: defaults)
        self.downloads = DownloadManager(store: self.libraryStore)
        downloads.scopeProvider = { [weak self] in
            self?.session.map { LibraryScope(serverID: $0.serverID, accountID: $0.userID) }
        }
        downloads.requestProvider = { [weak self] track in
            guard let api = self?.api else { throw APIError.notAuthenticated }
            return try api.audioDownloadRequest(itemID: track.id)
        }
        playback.localAudioURL = { [weak self] track in
            self?.downloads.localURL(for: track.id)
        }
        playback.replayCachedAudioURL = { [weak self] track in
            // Never used for downloaded tracks (those resolve as offline first).
            guard let self, !self.downloads.isDownloaded(track.id) else { return nil }
            return self.recentAudio.localURL(for: track.id)
        }
        playback.cacheAudioForReplay = { [weak self] track in
            guard let self, !self.downloads.isDownloaded(track.id),
                  let request = try? self.api?.audioDownloadRequest(itemID: track.id) else { return }
            self.recentAudio.enqueue([(trackID: track.id, request: request)])
        }
        playback.forgetCachedAudio = { [weak self] track in
            self?.recentAudio.remove(trackID: track.id)
        }
        downloads.artworkPrefetch = { [weak self] track in
            guard let self, let api = self.api, let session = self.session,
                  let artworkID = track.artworkItemID else { return }
            let key = ArtworkCache.key(serverID: session.serverID, itemID: artworkID)
            _ = await ArtworkCache.shared.image(forKey: key)
            guard await ArtworkCache.shared.takeRevalidation(forKey: key) else { return }
            if let data = try? await api.artworkData(itemID: artworkID) {
                await ArtworkCache.shared.store(data, forKey: key)
            } else {
                await ArtworkCache.shared.allowRevalidation(forKey: key)
            }
        }
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
            || arguments.contains("--ui-testing-home")
            || arguments.contains("--ui-testing-library")
            || arguments.contains("--ui-testing-search")
            || arguments.contains("--ui-testing-browse-details")
            || arguments.contains("--ui-testing-playlists")
            || arguments.contains("--ui-testing-genres")
            || arguments.contains("--ui-testing-favourites")
            || arguments.contains("--ui-testing-tracks") {
            configureUITestMusicShell()
            return
        }
#endif
        restoreSession()
    }

    func refreshTrackCatalog() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-tracks") {
            return
        }
#endif
        guard let session, let api, let libraryID = selectedLibraryID else { return }
        let scope = TrackCatalogScope(serverID: session.serverID, accountID: session.userID, libraryID: libraryID)
        if trackCatalogState.occurrences.isEmpty,
           let cached = try? await libraryStore?.cachedTrackCatalogPage(scope: libraryScope(for: session), libraryID: libraryID, limit: 100) {
            trackCatalogState.replaceCached(cached, scope: scope)
            prefetchDisplayedMedia(tracks: cached.occurrences.map(\.track))
        }
        trackCatalogGeneration += 1
        let generation = "track-catalog-\(trackCatalogGeneration)-\(session.serverID)-\(session.userID)-\(libraryID)"
        await trackCatalogState.refresh(scope: scope) { [weak self] startIndex in
            guard let self else { throw APIError.notAuthenticated }
            let page = try await api.trackCatalogPage(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
            if startIndex == 0 { try? await self.libraryStore?.replaceTrackCatalogPage(page, generation: generation, scope: self.libraryScope(for: session), libraryID: libraryID) }
            self.prefetchDisplayedMedia(tracks: page.occurrences.map(\.track))
            return page
        }
    }

    func loadMoreTrackCatalog() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-tracks-pagination-error") {
            return
        }
#endif
        guard let session, let api, let libraryID = selectedLibraryID else { return }
        let scope = TrackCatalogScope(serverID: session.serverID, accountID: session.userID, libraryID: libraryID)
        await trackCatalogState.loadMore(scope: scope) { [weak self] startIndex in
            guard let self else { throw APIError.notAuthenticated }
            let page = try await api.trackCatalogPage(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
            // The state has already rejected a stale scope before this page can
            // affect presentation; persistence also rejects stale generations.
            try? await self.libraryStore?.appendTrackCatalogPage(page, generation: "track-catalog-\(self.trackCatalogGeneration)-\(session.serverID)-\(session.userID)-\(libraryID)", scope: self.libraryScope(for: session), libraryID: libraryID)
            return page
        }
    }

    var api: JellyfinAPI? {
        guard let session else { return nil }
        return JellyfinAPI(baseURL: session.serverURL, deviceID: session.deviceID, token: session.accessToken)
    }

    func connect(server: String, username: String, password: String) async {
        Diagnostics.event("connect_started")
        guard let serverURL = normalizedServerURL(server) else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            JellytoneHaptics.error()
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
            trackCatalogState.clear(for: TrackCatalogScope(serverID: info.id, accountID: authentication.userID, libraryID: nil))
            self.session = session
            persistProfile(session)
            await loadPendingFavourites()
            Task { await runFavouriteReconciliation() }
            try await refreshLibraries()
            JellytoneHaptics.success()
        } catch {
            let failure = error as NSError
            Diagnostics.event("connect_failed", ["code": failure.code, "domain": failure.domain])
            errorMessage = error.localizedDescription
            JellytoneHaptics.error()
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
        Task { await downloads.refreshRecords() }
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
            // Newest additions first — the Library shelf is "Recently Added".
            try await api.albums(
                userID: session.userID,
                libraryID: libraryID,
                sortBy: "DateCreated,SortName",
                sortOrder: "Descending"
            )
        }
        hasMoreAlbums = page.hasMore
        nextAlbumStartIndex = page.nextStartIndex
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: albums))
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
                startIndex: nextAlbumStartIndex,
                sortBy: "DateCreated,SortName",
                sortOrder: "Descending"
            )
            let existing = Set(albums.map(\.id))
            albums.append(contentsOf: page.albums.filter { !existing.contains($0.id) })
            // Persist each page as it arrives so a relaunch resumes with the
            // full scrolled-through shelf, not just the first page.
            try? await libraryStore?.appendAlbums(
                page.albums,
                scope: libraryScope(for: session),
                libraryID: albumLibraryID
            )
            hasMoreAlbums = page.hasMore
            nextAlbumStartIndex = page.nextStartIndex
            prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.albums))
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
        if let session { trackCatalogState.clear(for: TrackCatalogScope(serverID: session.serverID, accountID: session.userID, libraryID: id)) }
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
            prefetchHomeSnapshot(cached)
        }

        async let added = homeAlbumsResult(api: api, userID: session.userID, libraryID: libraryID)
        async let played = homeTracksResult(api: api, userID: session.userID, libraryID: libraryID)
        async let playlists = homePlaylistsResult()
        async let artists = homeFavouriteArtistsResult(api: api, userID: session.userID, libraryID: libraryID)
        async let topAlbums = homeFrequentlyPlayedAlbumsResult(api: api, userID: session.userID, libraryID: libraryID)
        async let rediscover = homeRediscoverAlbumsResult(api: api, userID: session.userID, libraryID: libraryID)
        async let genres = homeGenresResult(api: api, userID: session.userID, libraryID: libraryID)
        let addedResult = await added
        let playedResult = await played
        let playlistsResult = await playlists
        let artistsResult = await artists
        let topAlbumsResult = await topAlbums
        let rediscoverResult = await rediscover
        let genresResult = await genres
        guard ownsHomeRefresh(generation, scope: requestScope) else { return }

        var replacement = homeSnapshot ?? .empty
        var errors: [String] = []
        switch addedResult {
        case let .success(albums):
            replacement = replacement.updating(recentlyAddedAlbums: albums)
        case .failure: errors.append("Recently added albums couldn’t be refreshed.")
        }
        switch playedResult {
        case let .success(tracks):
            replacement = replacement.updating(recentlyPlayedTracks: tracks)
        case .failure: errors.append("Recently played music couldn’t be refreshed.")
        }
        switch playlistsResult {
        case let .success(list):
            replacement = replacement.updating(madeForYouPlaylists: list)
        case .failure:
            // Secondary Listen Now shelves quietly keep their last snapshot —
            // primary recently-added / recently-played carry Home's errors.
            break
        }
        switch artistsResult {
        case let .success(list):
            replacement = replacement.updating(favouriteArtists: list)
        case .failure:
            break
        }
        switch topAlbumsResult {
        case let .success(albums):
            replacement = replacement.updating(frequentlyPlayedAlbums: albums)
        case .failure:
            break
        }
        switch rediscoverResult {
        case let .success(albums):
            replacement = replacement.updating(rediscoverAlbums: albums)
        case .failure:
            break
        }
        switch genresResult {
        case let .success(list):
            replacement = replacement.updating(homeGenres: list)
        case .failure:
            break
        }

        // Rebuild Instant Mix tiles from the freshest favourite artists +
        // recent listening seeds available after this refresh merge.
        let mixes = DiscoveryMixCatalog.make(
            favouriteArtists: replacement.favouriteArtists,
            recentlyPlayedTracks: replacement.recentlyPlayedTracks
        )
        replacement = replacement.updating(discoveryMixes: mixes)

        homeSnapshot = replacement
        prefetchHomeSnapshot(replacement)
        var anySuccess = false
        if case .success = addedResult { anySuccess = true }
        if case .success = playedResult { anySuccess = true }
        if case .success = playlistsResult { anySuccess = true }
        if case .success = artistsResult { anySuccess = true }
        if case .success = topAlbumsResult { anySuccess = true }
        if case .success = rediscoverResult { anySuccess = true }
        if case .success = genresResult { anySuccess = true }
        if anySuccess { try? await libraryStore?.replaceHomeShelfSnapshot(replacement, scope: scope, libraryID: libraryID) }
        homeRefreshError = errors.isEmpty ? nil : errors.joined(separator: " ")
        isRefreshingHome = false
        prefetchLeadingDiscoveryMixSeed(replacement.discoveryMixes)
    }

    /// Warm the first Made for You artist mix so tapping it doesn't wait on
    /// a cold top-tracks query. Instant Mix from the artist entity is often
    /// empty (no Genres on MusicArtist), so playback seeds from these tracks.
    private func prefetchLeadingDiscoveryMixSeed(_ mixes: [DiscoveryMix]) {
        guard let first = mixes.first, first.seedKind == .artist else { return }
        let artist = Artist(id: first.seedItemID, name: first.title, imageTag: first.imageTag)
        Task { _ = try? await artistTopTracks(for: artist) }
    }

    private static let madeForYouShelfLimit = 10
    private static let favouriteArtistsShelfLimit = 20
    private static let listenNowAlbumShelfLimit = 16
    private static let homeGenresShelfLimit = 16
    private var discoveryMixGeneration = 0

    private func homePlaylistsResult() async -> Result<[Playlist], Error> {
        do { return .success(try await recentPlaylists(limit: Self.madeForYouShelfLimit)) }
        catch { return .failure(error) }
    }

    private func homeFavouriteArtistsResult(api: JellyfinAPI, userID: String, libraryID: String) async -> HomeQueryResult<[Artist]> {
        do {
            let page = try await api.favouriteArtists(
                userID: userID, libraryID: libraryID,
                startIndex: 0, limit: Self.favouriteArtistsShelfLimit
            )
            return .success(page.artists)
        } catch { return .failure }
    }

    private func homeFrequentlyPlayedAlbumsResult(api: JellyfinAPI, userID: String, libraryID: String) async -> HomeQueryResult<[Album]> {
        do {
            return .success(try await api.frequentlyPlayedAlbums(
                userID: userID, libraryID: libraryID, limit: Self.listenNowAlbumShelfLimit
            ))
        } catch { return .failure }
    }

    private func homeRediscoverAlbumsResult(api: JellyfinAPI, userID: String, libraryID: String) async -> HomeQueryResult<[Album]> {
        do {
            return .success(try await api.rediscoverAlbums(
                userID: userID, libraryID: libraryID, limit: Self.listenNowAlbumShelfLimit
            ))
        } catch { return .failure }
    }

    private func homeGenresResult(api: JellyfinAPI, userID: String, libraryID: String) async -> HomeQueryResult<[Genre]> {
        do {
            let page = try await api.genres(
                userID: userID, libraryID: libraryID,
                startIndex: 0, limit: Self.homeGenresShelfLimit
            )
            return .success(page.genres)
        } catch { return .failure }
    }

    /// Plays a Listen Now Instant Mix. Haptic and any in-memory seed start
    /// synchronously so the tap isn't a dead pause while Instant Mix computes.
    /// Failures surface on `errorMessage` without wiping the Home snapshot.
    ///
    /// Artist Instant Mix is unreliable: Jellyfin builds it from the artist's
    /// own Genres, which are often empty. We start a playable seed track
    /// (cached recently-played or the artist's top songs) and expand the
    /// queue from Instant Mix of that *track*.
    func playDiscoveryMix(_ mix: DiscoveryMix) {
        guard session != nil, api != nil else { return }
        JellytoneHaptics.playFromLibrary()
        discoveryMixGeneration += 1
        let generation = discoveryMixGeneration
        if let seed = inMemorySeedTrack(for: mix) {
            play(seed, in: [seed], haptic: false)
        }
        Task { await expandDiscoveryMix(mix, generation: generation) }
    }

    private func inMemorySeedTrack(for mix: DiscoveryMix) -> Track? {
        guard mix.seedKind == .track else { return nil }
        return homeSnapshot?.recentlyPlayedTracks.first { $0.id == mix.seedItemID }
    }

    private func expandDiscoveryMix(_ mix: DiscoveryMix, generation: Int) async {
        guard let session, let api else { return }
        do {
            let seedTracks = try await resolveDiscoveryMixSeedTracks(
                mix, api: api, session: session
            )
            guard generation == discoveryMixGeneration else { return }
            guard let seed = seedTracks.first else {
                errorMessage = "This mix didn’t return any playable tracks."
                return
            }
            if playback.currentTrack?.id != seed.id {
                play(seed, in: seedTracks, haptic: false)
            }

            let mixTracks = try await api.instantMixTracks(
                userID: session.userID, itemID: seed.id
            )
            guard generation == discoveryMixGeneration else { return }
            guard playback.currentTrack?.id == seed.id else { return }
            let upcoming = DiscoveryMixQueue.upcoming(from: mixTracks, playing: seed)
            if !upcoming.isEmpty {
                playback.replaceUpcoming(with: upcoming)
            }
        } catch {
            guard generation == discoveryMixGeneration else { return }
            if playback.currentTrack == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// A playable Audio seed so Instant Mix is never asked to mix from a
    /// MusicArtist (empty when the artist entity has no Genres).
    private func resolveDiscoveryMixSeedTracks(
        _ mix: DiscoveryMix,
        api: JellyfinAPI,
        session: UserSession
    ) async throws -> [Track] {
        if let cached = inMemorySeedTrack(for: mix) { return [cached] }

        switch mix.seedKind {
        case .track:
            return try await api.instantMixTracks(
                userID: session.userID, itemID: mix.seedItemID
            )
        case .artist:
            let artist = Artist(id: mix.seedItemID, name: mix.title, imageTag: mix.imageTag)
            if let cached = await cachedArtistTopTracks(for: artist), !cached.isEmpty {
                return cached
            }
            let top = try await artistTopTracks(for: artist)
            if !top.isEmpty { return top }
            // Last resort: artist Instant Mix (empty when the artist has no Genres).
            return try await api.instantMixTracks(
                userID: session.userID, itemID: mix.seedItemID
            )
        case .album:
            let album = Album(
                id: mix.seedItemID, name: mix.title, artist: "",
                productionYear: nil, imageTag: mix.imageTag
            )
            let tracks = await self.tracks(for: album)
            if !tracks.isEmpty { return tracks }
            return try await api.instantMixTracks(
                userID: session.userID, itemID: mix.seedItemID
            )
        }
    }

    func tracks(for album: Album) async -> [Track] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-browse-details")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-library")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-home") {
            return Self.syntheticAlbumTracks(albumID: album.id, albumName: album.name, artist: album.artist)
        }
#endif
        if let existing = tracksByAlbum[album.id] { return existing }
        guard let session, let api else { return [] }
        do {
            let tracks = try await api.tracks(userID: session.userID, albumID: album.id)
            tracksByAlbum[album.id] = tracks
            try? await libraryStore?.replaceAlbumTracks(
                tracks, albumID: album.id,
                scope: libraryScope(for: session), libraryID: selectedLibraryID
            )
            prefetchDisplayedMedia(tracks: tracks, artworkItemIDs: artworkItemIDs(from: [album]))
            return tracks
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Persisted snapshot from the last visit, for instant paint before the
    /// network refresh lands.
    func cachedAlbumTracks(for album: Album) async -> [Track]? {
        guard let session else { return nil }
        let tracks = try? await libraryStore?.cachedAlbumTracks(
            albumID: album.id, scope: libraryScope(for: session), libraryID: selectedLibraryID
        )
        if let tracks {
            prefetchDisplayedMedia(tracks: tracks, artworkItemIDs: artworkItemIDs(from: [album]))
        }
        return tracks
    }

    /// Playlists are user-global in Jellyfin, so their snapshots cache under
    /// the global library scope.
    func cachedPlaylistEntries(for playlist: Playlist) async -> [PlaylistEntry]? {
        guard let session else { return nil }
        let entries = try? await libraryStore?.cachedPlaylistEntries(
            playlistID: playlist.id, scope: libraryScope(for: session), libraryID: nil
        )
        if let entries {
            prefetchDisplayedMedia(tracks: entries.map(\.track), artworkItemIDs: artworkItemIDs(from: [playlist]))
        }
        return entries
    }

    func storePlaylistEntries(_ entries: [PlaylistEntry], for playlist: Playlist) async {
        guard let session else { return }
        try? await libraryStore?.replacePlaylistEntries(
            entries, playlistID: playlist.id, scope: libraryScope(for: session), libraryID: nil
        )
    }

    /// Lyrics for a track, or nil when the server has none. Results are cached
    /// in-memory for the session so re-opening the lyrics view is instant.
    func lyrics(for track: Track) async -> TrackLyrics? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-player-lyrics") {
            return TrackLyrics(lines: [
                LyricLine(index: 0, text: "Synthetic opening line", startSeconds: 0),
                LyricLine(index: 1, text: "A second line to read", startSeconds: 4),
                LyricLine(index: 2, text: "The chorus arrives now", startSeconds: 8),
            ])
        }
        if arguments.contains("--ui-testing") { return nil }
#endif
        if let cached = lyricsByTrack[track.id] { return cached.value }
        guard let api else { return nil }
        let result = try? await api.lyrics(itemID: track.id)
        lyricsByTrack[track.id] = LyricsCacheEntry(value: result)
        return result
    }

    private struct LyricsCacheEntry { let value: TrackLyrics? }
    private var lyricsByTrack: [String: LyricsCacheEntry] = [:]

    func searchMusic(
        query: String,
        startIndex: Int = 0,
        present: (@MainActor (MusicSearchPage) -> Void)? = nil
    ) async throws -> MusicSearchPage {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-search-loading") {
            while !Task.isCancelled { try await Task.sleep(for: .seconds(60)) }
        }
        if arguments.contains("--ui-testing-search-error") { throw APIError.httpStatus(503) }
        if arguments.contains("--ui-testing-search-no-results") {
            return MusicSearchPage()
        }
        if arguments.contains("--ui-testing-search") {
            return MusicSearchPage(
                artists: [Artist(id: "artist-unicode", name: "Björk Guðmundsdóttir & The Synthetic Orchestra", imageTag: nil)],
                albums: [
                    Album(id: "album-artwork", name: "Aurora Lines", artist: "Björk Guðmundsdóttir", productionYear: 2026, imageTag: "synthetic-art"),
                    Album(id: "album-missing", name: "夜明け — A Deliberately Long Album Title", artist: "Synthetic Artist", productionYear: 2025, imageTag: nil),
                ],
                tracks: [
                    Track(
                        id: "track-aurora",
                        name: "Aurora",
                        artist: "Björk Guðmundsdóttir",
                        album: "Aurora Lines",
                        albumID: "album-artwork",
                        index: 1,
                        disc: 1,
                        durationTicks: 2_100_000_000,
                        artistID: "artist-unicode",
                        imageTag: nil
                    ),
                ],
                playlists: [
                    Playlist(id: "playlist-aurora", name: "Aurora Mix", imageTag: nil, itemCount: 12),
                ],
                hasMore: false,
                nextStartIndex: 5
            )
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        let scope = libraryScope(for: session)
        let page = try await CacheBackedMusicSearch.execute(
            query: query,
            startIndex: startIndex,
            scope: scope,
            libraryID: selectedLibraryID,
            store: libraryStore,
            present: present
        ) {
            try await api.searchMusic(
                userID: session.userID,
                libraryID: selectedLibraryID,
                query: query,
                startIndex: startIndex
            )
        }
        prefetchDisplayedMedia(
            tracks: page.tracks,
            artworkItemIDs: artworkItemIDs(from: page.albums)
                + artworkItemIDs(from: page.artists)
                + artworkItemIDs(from: page.playlists)
        )
        return page
    }

    func albums(for artist: Artist, startIndex: Int = 0) async throws -> AlbumPage {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-browse-details")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-home") {
            let albums = [
                Album(id: "album-artwork", name: "Aurora Lines", artist: artist.name, productionYear: 2026, imageTag: "synthetic-art"),
                Album(id: "album-missing", name: "夜明け — A Deliberately Long Album Title", artist: artist.name, productionYear: 2025, imageTag: nil),
            ]
            return AlbumPage(albums: startIndex == 0 ? albums : [], hasMore: false, nextStartIndex: albums.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        let page = try await api.albums(
            userID: session.userID,
            artistID: artist.id,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
        // Keep last visit's snapshot current as each page resolves: the first
        // page replaces it, later pages extend it in received order.
        if startIndex == 0 {
            try? await libraryStore?.replaceArtistAlbums(
                page.albums, artistID: artist.id,
                scope: libraryScope(for: session), libraryID: selectedLibraryID
            )
        } else if !page.albums.isEmpty {
            let cached = (try? await libraryStore?.cachedArtistAlbums(
                artistID: artist.id, scope: libraryScope(for: session), libraryID: selectedLibraryID
            )) ?? []
            let existing = Set(cached.map(\.id))
            try? await libraryStore?.replaceArtistAlbums(
                cached + page.albums.filter { !existing.contains($0.id) },
                artistID: artist.id,
                scope: libraryScope(for: session), libraryID: selectedLibraryID
            )
        }
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.albums))
        return page
    }

    /// Persisted albums snapshot from the last visit to this artist, for
    /// instant paint before the network refresh lands.
    func cachedArtistAlbums(for artist: Artist) async -> [Album]? {
        guard let session else { return nil }
        let albums = try? await libraryStore?.cachedArtistAlbums(
            artistID: artist.id, scope: libraryScope(for: session), libraryID: selectedLibraryID
        )
        if let albums { prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: albums)) }
        return albums
    }

    /// The artist's most-played tracks, persisted as the refresh resolves.
    func artistTopTracks(for artist: Artist) async throws -> [Track] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-browse-details") {
            return Self.syntheticAlbumTracks(albumID: "artist-top", albumName: "Aurora Lines", artist: artist.name)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        let tracks = try await api.artistTopTracks(
            userID: session.userID,
            artistID: artist.id,
            libraryID: selectedLibraryID
        )
        try? await libraryStore?.replaceArtistTopTracks(
            tracks, artistID: artist.id,
            scope: libraryScope(for: session), libraryID: selectedLibraryID
        )
        prefetchDisplayedMedia(tracks: tracks, artworkItemIDs: artworkItemIDs(from: [artist]))
        return tracks
    }

    func cachedArtistTopTracks(for artist: Artist) async -> [Track]? {
        guard let session else { return nil }
        let tracks = try? await libraryStore?.cachedArtistTopTracks(
            artistID: artist.id, scope: libraryScope(for: session), libraryID: selectedLibraryID
        )
        if let tracks { prefetchDisplayedMedia(tracks: tracks, artworkItemIDs: artworkItemIDs(from: [artist])) }
        return tracks
    }

    func artistPage(startIndex: Int = 0) async throws -> ArtistPage {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-artists-loading") {
            try await Task.sleep(for: .seconds(5))
        }
        if arguments.contains("--ui-testing-artists-error") { throw APIError.httpStatus(503) }
        if arguments.contains("--ui-testing-artists-pagination-error"), startIndex > 0 {
            throw APIError.httpStatus(503)
        }
        if arguments.contains("--ui-testing-artists-empty") {
            return ArtistPage(artists: [], hasMore: false, nextStartIndex: 0)
        }
        if arguments.contains("--ui-testing-artists") {
            let artists = [
                Artist(id: "artist-artwork", name: "Aurora Ensemble", imageTag: "synthetic-art"),
                Artist(id: "artist-duplicate-name", name: "Aurora Ensemble", imageTag: nil),
                Artist(id: "artist-unicode", name: "Björk Guðmundsdóttir & The Synthetic Orchestra",
                       imageTag: nil),
            ]
            if arguments.contains("--ui-testing-artists-pagination-error") {
                return ArtistPage(artists: startIndex == 0 ? [artists[0]] : [], hasMore: startIndex == 0,
                                  nextStartIndex: startIndex == 0 ? 1 : startIndex)
            }
            return ArtistPage(artists: startIndex == 0 ? artists : [], hasMore: false,
                              nextStartIndex: artists.count)
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        let page = try await api.artists(
            userID: session.userID,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
        // Write-through browse cache: page 0 replaces the snapshot, later
        // pages append as they resolve, so the next visit paints instantly.
        if startIndex == 0 {
            try? await libraryStore?.replaceArtists(
                page.artists, scope: libraryScope(for: session), libraryID: selectedLibraryID
            )
        } else {
            try? await libraryStore?.appendArtists(
                page.artists, scope: libraryScope(for: session), libraryID: selectedLibraryID
            )
        }
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.artists))
        return page
    }

    /// Persisted artist browse snapshot for cache-first paint; empty when the
    /// account has never opened the Artists screen.
    func cachedArtists() async -> [Artist] {
        guard let session else { return [] }
        let artists = (try? await libraryStore?.cachedArtists(
            scope: libraryScope(for: session), libraryID: selectedLibraryID
        )) ?? []
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: artists))
        return artists
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
        let page = try await api.playlists(
            userID: session.userID,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
        // Playlists are user-global in Jellyfin (see cachedPlaylistEntries),
        // so the browse cache lives under the global library scope too.
        if startIndex == 0 {
            try? await libraryStore?.replacePlaylists(page.playlists, scope: libraryScope(for: session), libraryID: nil)
        } else {
            try? await libraryStore?.appendPlaylists(page.playlists, scope: libraryScope(for: session), libraryID: nil)
        }
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.playlists))
        return page
    }

    /// Persisted playlist browse snapshot for cache-first paint.
    func cachedPlaylists() async -> [Playlist] {
        guard let session else { return [] }
        let playlists = (try? await libraryStore?.cachedPlaylists(scope: libraryScope(for: session), libraryID: nil)) ?? []
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: playlists))
        return playlists
    }

    /// Most recently created playlists, for Home's "Made For You" shelf. The
    /// alphabetical `playlistPage` feed keeps serving the Library screen.
    func recentPlaylists(limit: Int) async throws -> [Playlist] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return Array(try await playlistPage().playlists.prefix(limit))
        }
#endif
        guard let session, let api else { throw APIError.notAuthenticated }
        return try await api.playlists(
            userID: session.userID,
            libraryID: selectedLibraryID,
            limit: limit,
            sortBy: "DateCreated",
            sortOrder: "Descending"
        ).playlists
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
        let page = try await api.playlistEntries(
            userID: session.userID,
            playlistID: playlist.id,
            startIndex: startIndex
        )
        prefetchDisplayedMedia(tracks: page.entries.map(\.track), artworkItemIDs: artworkItemIDs(from: [playlist]))
        return page
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
        let page = try await api.genres(
            userID: session.userID,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
        if startIndex == 0 {
            try? await libraryStore?.replaceGenres(page.genres, scope: libraryScope(for: session), libraryID: selectedLibraryID)
        } else {
            try? await libraryStore?.appendGenres(page.genres, scope: libraryScope(for: session), libraryID: selectedLibraryID)
        }
        prefetchDisplayedMedia(artworkItemIDs: page.genres.compactMap { $0.imageTag == nil ? nil : $0.id })
        return page
    }

    /// Persisted genre browse snapshot for cache-first paint.
    func cachedGenres() async -> [Genre] {
        guard let session else { return [] }
        let genres = (try? await libraryStore?.cachedGenres(scope: libraryScope(for: session), libraryID: selectedLibraryID)) ?? []
        prefetchDisplayedMedia(artworkItemIDs: genres.compactMap { $0.imageTag == nil ? nil : $0.id })
        return genres
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
        let page = try await api.genreAlbums(
            userID: session.userID,
            genreID: genre.id,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
        if let store = libraryStore {
            let scope = libraryScope(for: session)
            let libraryID = selectedLibraryID
            await Self.persistPagedSnapshot(
                page.albums, startIndex: startIndex,
                read: { try await store.cachedGenreAlbums(genreID: genre.id, scope: scope, libraryID: libraryID) },
                write: { try await store.replaceGenreAlbums($0, genreID: genre.id, scope: scope, libraryID: libraryID) }
            )
        }
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.albums))
        return page
    }

    /// Persisted genre-albums snapshot for instant paint.
    func cachedGenreAlbums(for genre: Genre) async -> [Album]? {
        guard let session else { return nil }
        let albums = try? await libraryStore?.cachedGenreAlbums(
            genreID: genre.id, scope: libraryScope(for: session), libraryID: selectedLibraryID
        )
        if let albums { prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: albums)) }
        return albums
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
        let page = try await api.genreTracks(
            userID: session.userID,
            genreID: genre.id,
            libraryID: selectedLibraryID,
            startIndex: startIndex
        )
        if let store = libraryStore {
            let scope = libraryScope(for: session)
            let libraryID = selectedLibraryID
            // Occurrence IDs encode the wire offset, so identity dedupe keeps
            // genuinely repeated tracks while dropping re-received pages.
            await Self.persistPagedSnapshot(
                page.occurrences, startIndex: startIndex,
                read: { try await store.cachedGenreTracks(genreID: genre.id, scope: scope, libraryID: libraryID) },
                write: { try await store.replaceGenreTracks($0, genreID: genre.id, scope: scope, libraryID: libraryID) }
            )
        }
        prefetchDisplayedMedia(tracks: page.occurrences.map(\.track))
        return page
    }

    /// Persisted genre-tracks snapshot for instant paint.
    func cachedGenreTracks(for genre: Genre) async -> [GenreTrackOccurrence]? {
        guard let session else { return nil }
        let occurrences = try? await libraryStore?.cachedGenreTracks(
            genreID: genre.id, scope: libraryScope(for: session), libraryID: selectedLibraryID
        )
        if let occurrences { prefetchDisplayedMedia(tracks: occurrences.map(\.track)) }
        return occurrences
    }

    /// Write-through for paginated detail snapshots: page 0 replaces the cache;
    /// later pages merge in received order, deduped by identity so re-received
    /// pages never duplicate rows.
    private static func persistPagedSnapshot<Item: Identifiable & Sendable>(
        _ items: [Item],
        startIndex: Int,
        read: () async throws -> [Item]?,
        write: ([Item]) async throws -> Void
    ) async {
        if startIndex == 0 {
            try? await write(items)
            return
        }
        let existing = (try? await read()) ?? []
        var seen = Set(existing.map(\.id))
        let merged = existing + items.filter { seen.insert($0.id).inserted }
        try? await write(merged)
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
        let page = try await api.favouriteArtists(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.artists))
        return page
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
        let page = try await api.favouriteAlbums(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: page.albums))
        return page
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
        let page = try await api.favouriteTracks(userID: session.userID, libraryID: libraryID, startIndex: startIndex)
        prefetchDisplayedMedia(tracks: page.occurrences.map(\.track))
        return page
    }

    func play(_ track: Track, in queue: [Track], haptic: Bool = true) {
        guard let api, let session else { return }
        if haptic { JellytoneHaptics.playFromLibrary() }
        playback.play(
            track,
            queue: queue,
            using: api,
            userID: session.userID,
            scope: playbackScope(for: session)
        )
    }

    func playAll(_ tracks: [Track]) {
        guard let first = tracks.first else { return }
        play(first, in: tracks)
    }

    func shuffle(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        playAll(tracks)
        playback.toggleShuffle()
    }

    func play(_ occurrence: TrackCatalogOccurrence, in occurrences: [TrackCatalogOccurrence]) {
        guard let api, let session,
              let selectedIndex = occurrences.firstIndex(where: { $0.id == occurrence.id }) else { return }
        JellytoneHaptics.playFromLibrary()
        let entries = occurrences.map { QueueEntry(id: UUID(), track: $0.track) }
        playback.play(entries: entries, startingAt: entries[selectedIndex].id, using: api,
                      userID: session.userID, scope: playbackScope(for: session))
    }

    func play(_ entry: PlaylistEntry, in playlistEntries: [PlaylistEntry]) {
        guard let api, let session,
              let selectedIndex = playlistEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        JellytoneHaptics.playFromLibrary()
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
        JellytoneHaptics.playFromLibrary()
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
        JellytoneHaptics.playFromLibrary()
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

    // MARK: - Favourites ("likes")

    /// Effective favourite state for any item ID — song, album, or artist.
    func isFavourite(_ id: String) -> Bool { favouriteRegistry.isFavourite(id) }

    /// Optimistically flip an item's favourite state, durably enqueue the change,
    /// and kick reconciliation so it persists to the Jellyfin server. Safe to call
    /// offline: the outbox retries until the write lands.
    func toggleFavourite(id: String) {
        guard let session, let store = libraryStore, !id.isEmpty else { return }
        let desired = favouriteRegistry.toggle(id)
        JellytoneHaptics.favourite(adding: desired)
        favouriteSequence += 1
        let sequence = favouriteSequence
        let scope = libraryScope(for: session)
        Diagnostics.event("favourite_toggle", ["desired": desired ? "1" : "0"])
        Task {
            _ = try? await store.enqueueFavourite(scope: scope, itemID: id, desired: desired, sequence: sequence)
            await runFavouriteReconciliation()
        }
    }

    /// Fetch current server favourite truth for the given items and merge it in,
    /// used when a detail screen appears so its heart reflects the server without
    /// clobbering an unsynced local toggle.
    func refreshFavouriteStatus(ids: [String]) async {
        let observed = ids.filter { !$0.isEmpty }
        guard let session, let api, !observed.isEmpty else { return }
        guard let favourited = try? await api.favouriteStatus(userID: session.userID, itemIDs: observed) else { return }
        favouriteRegistry.applyServerTruth(favourited: favourited, observed: Set(observed))
    }

    /// Seed optimistic state from the durable outbox at session start so pending
    /// likes survive relaunch even before they reconcile.
    func loadPendingFavourites() async {
        guard let session, let store = libraryStore else { return }
        guard let rows = try? await store.pendingFavourites(scope: libraryScope(for: session)) else { return }
        var desired: [String: Bool] = [:]
        for row in rows where row.state != .completed { desired[row.itemID] = row.desired }
        favouriteRegistry.applyPending(desired)
        favouriteSequence = max(favouriteSequence, rows.map(\.sequence).max() ?? 0)
    }

    /// Drain the favourite outbox against the server, then drop reconciled intents
    /// from the pending overlay so later loads reflect authoritative truth.
    func runFavouriteReconciliation() async {
        guard let session, let api, let reconciler = favouriteReconciler, let store = libraryStore else { return }
        let scope = libraryScope(for: session)
        let now = Int64(Date().timeIntervalSince1970)
        await reconciler.reconcile(scope: scope, gateway: api, now: now)
        if let rows = try? await store.pendingFavourites(scope: scope) {
            var stillPending: [String: Bool] = [:]
            for row in rows where row.state != .completed { stillPending[row.itemID] = row.desired }
            favouriteRegistry.replacePending(stillPending)
        }
    }

    func mediaCacheBytes() async -> Int64 {
        await ArtworkCache.shared.diskBytes() + recentAudio.totalBytes
    }

    func clearMediaCache() async {
        await ArtworkCache.shared.clear()
        recentAudio.clear()
    }

    /// Warm disk artwork into memory and queue original audio for tracks the
    /// user can already see, so a subsequent tap plays without waiting on the
    /// server. No-op during UI tests and when signed out.
    func prefetchDisplayedMedia(tracks: [Track] = [], artworkItemIDs: [String] = []) {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        guard let session, let api else { return }
        let ids = Array(Set(artworkItemIDs + tracks.compactMap(\.artworkItemID)))
        if !ids.isEmpty {
            let capturedSession = session
            let capturedAPI = api
            Task { await self.warmAndRefreshArtwork(itemIDs: ids, session: capturedSession, api: capturedAPI) }
        }
        let items = tracks.compactMap { track -> (trackID: String, request: URLRequest)? in
            guard !downloads.isDownloaded(track.id),
                  let request = try? api.audioDownloadRequest(itemID: track.id) else { return nil }
            return (track.id, request)
        }
        if !items.isEmpty { recentAudio.enqueue(items) }
    }

    private func warmAndRefreshArtwork(itemIDs: [String], session: UserSession, api: JellyfinAPI) async {
        let keys = itemIDs.map { ArtworkCache.key(serverID: session.serverID, itemID: $0) }
        await ArtworkCache.shared.warm(keys: keys)
        for itemID in itemIDs {
            let key = ArtworkCache.key(serverID: session.serverID, itemID: itemID)
            guard await ArtworkCache.shared.takeRevalidation(forKey: key) else { continue }
            if let data = try? await api.artworkData(itemID: itemID) {
                await ArtworkCache.shared.store(data, forKey: key)
            } else {
                await ArtworkCache.shared.allowRevalidation(forKey: key)
            }
        }
    }

    private func artworkItemIDs(from albums: [Album]) -> [String] {
        albums.compactMap { $0.imageTag == nil ? nil : $0.id }
    }

    private func artworkItemIDs(from artists: [Artist]) -> [String] {
        artists.compactMap { $0.imageTag == nil ? nil : $0.id }
    }

    private func artworkItemIDs(from playlists: [Playlist]) -> [String] {
        playlists.compactMap { $0.imageTag == nil ? nil : $0.id }
    }

    private func prefetchHomeSnapshot(_ snapshot: HomeShelfSnapshot) {
        prefetchDisplayedMedia(
            tracks: snapshot.recentlyPlayedTracks,
            artworkItemIDs: artworkItemIDs(from: snapshot.recentlyAddedAlbums)
                + artworkItemIDs(from: snapshot.favouriteArtists)
                + artworkItemIDs(from: snapshot.madeForYouPlaylists)
                + artworkItemIDs(from: snapshot.frequentlyPlayedAlbums)
                + artworkItemIDs(from: snapshot.rediscoverAlbums)
                + snapshot.discoveryMixes.compactMap { $0.imageTag == nil ? nil : $0.artworkItemID }
                + snapshot.homeGenres.compactMap { $0.imageTag == nil ? nil : $0.id }
        )
    }

    func playNext(_ track: Track) {
        JellytoneHaptics.play(.light)
        playback.playNext(track)
    }

    func addToQueue(_ track: Track) {
        JellytoneHaptics.play(.soft)
        playback.addToQueue(track)
    }

    func logout() async {
        JellytoneHaptics.destructive()
        await playback.stopAndWait()
        KeychainTokenStore.delete()
        await ArtworkCache.shared.clear()
        await downloads.removeAll()
        recentAudio.clear()
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
        favouriteRegistry = FavouriteRegistry()
        favouriteSequence = 0
    }

    private var installationDeviceID: String {
        defaults.string(forKey: Self.deviceIDKey) ?? "jellytone-installation"
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
                await loadPendingFavourites()
                await runFavouriteReconciliation()
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
        prefetchDisplayedMedia(artworkItemIDs: artworkItemIDs(from: cached))
    }

    private func loadCachedHomeShelves(for session: UserSession, libraryID: String?) async {
        guard let cached = try? await libraryStore?.cachedHomeShelfSnapshot(
            scope: libraryScope(for: session), libraryID: libraryID
        ) else { return }
        homeSnapshot = cached
        prefetchHomeSnapshot(cached)
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
        let directory = support.appendingPathComponent("Jellytone", isDirectory: true)
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
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func configureUITestMusicShell() {
        let arguments = ProcessInfo.processInfo.arguments
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
        albums = [
            Album(id: "album-artwork", name: "Aurora Lines", artist: "Synthetic Artist", productionYear: 2026, imageTag: "synthetic-art"),
            Album(id: "album-missing", name: "夜明け — A Deliberately Long Album Title", artist: "Björk Guðmundsdóttir", productionYear: 2025, imageTag: nil),
        ]
        if arguments.contains("--ui-testing-library-empty") { albums = [] }
        hasMoreAlbums = false
        albumLibraryID = "music"
        nextAlbumStartIndex = albums.count
        let longMetadata = arguments.contains("--ui-testing-player-long-unicode")
        let track = Track(
            id: "track",
            name: longMetadata ? "夜明けの街で聴く A deliberately very long song title that should remain readable" : "Visible Mini Player",
            artist: longMetadata ? "Björk Guðmundsdóttir & The Synthetic Orchestra" : "Synthetic Artist",
            album: longMetadata ? "An exceptionally long album name for accessibility testing" : "Synthetic Album",
            index: 1,
            disc: 1,
            durationTicks: 1_800_000_000
        )
        if !arguments.contains("--ui-testing-home") || arguments.contains("--ui-testing-restored-playback") {
            playback.configureForUITesting(track: track, upcoming: [
                Track(id: "next-1", name: "First Up Next", artist: "Synthetic Artist",
                      album: "Synthetic Album", index: 2, disc: 1, durationTicks: 1_800_000_000),
                Track(id: "next-2", name: "Second Up Next", artist: "Synthetic Artist",
                      album: "Synthetic Album", index: 3, disc: 1, durationTicks: 1_800_000_000),
                Track(id: "next-1", name: "First Up Next (again)", artist: "Synthetic Artist",
                      album: "Synthetic Album", index: 4, disc: 1, durationTicks: 1_800_000_000),
            ], elapsed: arguments.contains("--ui-testing-restored-playback") ? 73 : 0,
            isPlaying: arguments.contains("--ui-testing-player-playing"),
            isPreparing: arguments.contains("--ui-testing-player-preparing"),
            artwork: arguments.contains("--ui-testing-player-artwork") ? Self.syntheticArtwork() : nil,
            errorMessage: arguments.contains("--ui-testing-player-failure") ? "Playback could not continue. Try another track." : nil)
        }
        if arguments.contains("--ui-testing-home")
            && !arguments.contains("--ui-testing-home-loading")
            && !arguments.contains("--ui-testing-home-empty")
            && !arguments.contains("--ui-testing-home-error") {
            homeSnapshot = Self.syntheticHomeSnapshot(albumID: "home-album-new")
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-tracks") {
            let scope = TrackCatalogScope(serverID: "synthetic-server", accountID: "synthetic-user", libraryID: "music")
            let tracks = [
                TrackCatalogOccurrence(id: "track-catalog:0:track-1", track: Track(id: "track-1", name: "A First Song", artist: "Synthetic Artist", album: "Synthetic Album", albumID: "album-synthetic", index: 1, disc: 1, durationTicks: 1_800_000_000), ordinal: 0),
                TrackCatalogOccurrence(id: "track-catalog:1:track-2", track: Track(id: "track-2", name: "B Second Song", artist: "Other Artist", album: "", index: nil, disc: nil, durationTicks: nil), ordinal: 1),
            ]
            let page = TrackCatalogPage(occurrences: tracks, hasMore: false, nextStartIndex: 2)
            if arguments.contains("--ui-testing-tracks-loading") {
                trackCatalogState.configureLoadingForUITesting(scope: scope)
            } else if arguments.contains("--ui-testing-tracks-empty") {
                trackCatalogState.replaceCached(TrackCatalogPage(occurrences: [], hasMore: false, nextStartIndex: 0), scope: scope)
            } else if arguments.contains("--ui-testing-tracks-pagination-error") {
                trackCatalogState.configurePaginationFailureForUITesting(page, scope: scope, error: APIError.httpStatus(503))
            } else {
                trackCatalogState.replaceCached(page, scope: scope)
            }
        }
    }

    private static func syntheticAlbumTracks(albumID: String, albumName: String, artist: String) -> [Track] {
        [
            Track(id: "\(albumID)-track-1", name: "Opening Light", artist: artist, album: albumName,
                  albumID: albumID, index: 1, disc: 1, durationTicks: 1_810_000_000),
            Track(id: "\(albumID)-track-2", name: "夜明けの街で聴く — A Long Unicode Movement", artist: artist,
                  album: albumName, albumID: albumID, index: 2, disc: 1, durationTicks: 2_420_000_000),
            Track(id: "\(albumID)-track-3", name: "Second Disc Prelude", artist: artist, album: albumName,
                  albumID: albumID, index: 1, disc: 2, durationTicks: 1_500_000_000),
        ]
    }

    private static func syntheticHomeSnapshot(albumID: String) -> HomeShelfSnapshot {
        HomeShelfSnapshot(
            recentlyAddedAlbums: [Album(id: albumID, name: "New Album", artist: "Synthetic Artist", productionYear: 2026, imageTag: nil)],
            recentlyPlayedTracks: [Track(id: "home-track-1", name: "Recently Played", artist: "Synthetic Artist", album: "New Album", albumID: albumID, index: 1, disc: 1, durationTicks: 1_800_000_000)],
            favouriteArtists: [Artist(id: "home-artist-1", name: "Synthetic Artist", imageTag: nil)]
        )
    }

    private static func syntheticArtwork() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        return renderer.image { context in
            UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            let colors = [UIColor(red: 0.93, green: 0.34, blue: 0.27, alpha: 1).cgColor,
                          UIColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 600), end: CGPoint(x: 600, y: 0), options: [])
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            "J A".draw(in: CGRect(x: 0, y: 238, width: 600, height: 90), withAttributes: [.font: UIFont.systemFont(ofSize: 94, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
    }
#endif
}
