import SwiftUI

// MARK: - Controller

@MainActor
final class MusicSearchController: ObservableObject {
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?

    private(set) var query = ""
    private var generation = 0
    private var hasMore = false
    private var nextStartIndex = 0

    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && tracks.isEmpty && playlists.isEmpty
    }

    var canLoadMore: Bool { hasMore && !isLoadingMore }

    /// Progressive load signature: `present` is invoked on the main actor with
    /// cache-first hits (if any) before the network merge returns, so typing
    /// can paint local results without waiting for debounce+server.
    func search(
        query rawQuery: String,
        debounceNanoseconds: UInt64 = 350_000_000,
        load: @escaping (String, Int, @escaping @MainActor (MusicSearchPage) -> Void) async throws -> MusicSearchPage
    ) async {
        generation += 1
        let requestGeneration = generation
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryChanged = normalized != query
        query = normalized
        errorMessage = nil
        paginationError = nil
        if queryChanged {
            // Clear previous query's rows so we never show stale titles under a
            // new term; cache present (if any) repaints immediately after.
            artists = []
            albums = []
            tracks = []
            playlists = []
            hasMore = false
            nextStartIndex = 0
        }

        guard !normalized.isEmpty else {
            artists = []
            albums = []
            tracks = []
            playlists = []
            hasMore = false
            nextStartIndex = 0
            isLoading = false
            return
        }

        isLoading = true
        do {
            if debounceNanoseconds > 0 {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            try Task.checkCancellation()
            let page = try await load(normalized, 0) { [weak self] interim in
                guard let self else { return }
                guard requestGeneration == self.generation, normalized == self.query else { return }
                self.apply(page: interim, replacePagination: false)
            }
            try Task.checkCancellation()
            guard requestGeneration == generation, normalized == query else { return }
            apply(page: page, replacePagination: true)
            Diagnostics.event("music_search_loaded", [
                "album_count": page.albums.count,
                "artist_count": page.artists.count,
                "track_count": page.tracks.count,
                "playlist_count": page.playlists.count,
                "has_more": page.hasMore,
            ])
        } catch is CancellationError {
            // Replaced and dismissed searches are expected; do not surface an error.
        } catch {
            guard !Task.isCancelled else {
                if requestGeneration == generation { isLoading = false }
                return
            }
            guard requestGeneration == generation, normalized == query else { return }
            // Keep any cache-painted rows when the network fails after present.
            if isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        if requestGeneration == generation { isLoading = false }
    }

    func loadMore(
        load: @escaping (String, Int, @escaping @MainActor (MusicSearchPage) -> Void) async throws -> MusicSearchPage
    ) async {
        guard canLoadMore, !query.isEmpty else { return }
        let requestGeneration = generation
        let startIndex = nextStartIndex
        isLoadingMore = true
        paginationError = nil
        defer {
            if requestGeneration == generation { isLoadingMore = false }
        }
        do {
            let page = try await load(query, startIndex) { _ in }
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            let artistIDs = Set(artists.map(\.id))
            let albumIDs = Set(albums.map(\.id))
            let trackIDs = Set(tracks.map(\.id))
            let playlistIDs = Set(playlists.map(\.id))
            artists.append(contentsOf: page.artists.filter { !artistIDs.contains($0.id) })
            albums.append(contentsOf: page.albums.filter { !albumIDs.contains($0.id) })
            tracks.append(contentsOf: page.tracks.filter { !trackIDs.contains($0.id) })
            playlists.append(contentsOf: page.playlists.filter { !playlistIDs.contains($0.id) })
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A new query owns the screen now.
        } catch {
            guard !Task.isCancelled else { return }
            guard requestGeneration == generation else { return }
            paginationError = error.localizedDescription
        }
    }

    private func apply(page: MusicSearchPage, replacePagination: Bool) {
        artists = page.artists
        albums = page.albums
        tracks = page.tracks
        playlists = page.playlists
        if replacePagination {
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
        }
    }
}

// MARK: - Recent searches (local, device-only)

enum RecentMusicSearches {
    private static let key = "jellytone.recentMusicSearches"
    private static let limit = 8

    static func load() -> [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func remember(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        var next = load().filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        next.insert(term, at: 0)
        if next.count > limit { next = Array(next.prefix(limit)) }
        UserDefaults.standard.set(next, forKey: key)
    }

    static func remove(_ term: String) {
        let next = load().filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        UserDefaults.standard.set(next, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Search screen

/// Apple Music–style Search: idle recent/browse entry points, typed results in
/// Top Results + Songs / Albums / Artists / Playlists sections, fully on
/// `JellytoneTheme` (AGENTS.md Priority 3).
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = MusicSearchController()
    @State private var query = ""
    @State private var recentSearches: [String] = RecentMusicSearches.load()

    var body: some View {
        NavigationStack {
            content
                .background(Color.jtBackground.ignoresSafeArea())
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.large)
                .accessibilityIdentifier("search-screen")
                .navigationDestination(for: Album.self) { AlbumView(album: $0) }
                .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
                .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
                .navigationDestination(for: Genre.self) { GenreDetailView(genre: $0) }
                .navigationDestination(for: LibrarySection.self) { section in
                    searchBrowseDestination(section)
                }
                .searchable(text: $query, prompt: "Songs, artists, albums, playlists")
                .task(id: query) {
                    await search.search(query: query) { value, startIndex, present in
                        try await model.searchMusic(
                            query: value,
                            startIndex: startIndex,
                            present: present
                        )
                    }
                    // Remember successful non-empty queries once results land.
                    if !search.query.isEmpty, !search.isEmpty {
                        RecentMusicSearches.remember(search.query)
                        recentSearches = RecentMusicSearches.load()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if search.query.isEmpty {
            idleState
        } else if search.isLoading && search.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                Text("Searching music")
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextSecondary)
                JellytoneSkeletonRows(rows: 10, label: "Searching music")
                    .accessibilityIdentifier("search-loading-skeleton")
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let message = search.errorMessage, search.isEmpty {
            searchStateCard(
                title: "Search unavailable",
                detail: message,
                actionTitle: "Try Again"
            ) {
                Task { await retrySearch() }
            }
        } else if search.isEmpty {
            searchStateCard(
                title: "No results for “\(search.query)”",
                detail: "Try another song, artist, album, or playlist name."
            )
        } else {
            resultsList
        }
    }

    // MARK: Idle

    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                if !recentSearches.isEmpty {
                    recentSection
                }
                browseSection
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.md)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
            HStack {
                Text("Recent")
                    .font(.jtSectionHeader)
                    .foregroundStyle(Color.jtTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") {
                    RecentMusicSearches.clear()
                    recentSearches = []
                }
                .font(.jtCaption.weight(.bold))
                .foregroundStyle(Color.jtAccent)
                .buttonStyle(.jtPressScale())
                .accessibilityIdentifier("search-recent-clear")
            }
            VStack(spacing: 0) {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        query = term
                    } label: {
                        HStack(spacing: JellytoneTheme.Space.mdPlus) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.jtSubsectionHeader.weight(.medium))
                                .foregroundStyle(Color.jtTextTertiary)
                                .frame(width: SearchMetrics.categoryIconWidth)
                            Text(term)
                                .font(.jtRowTitle)
                                .foregroundStyle(Color.jtTextPrimary)
                                .lineLimit(1)
                            Spacer(minLength: JellytoneTheme.Space.sm)
                            Image(systemName: "arrow.up.left")
                                .font(.jtCaption.weight(.bold))
                                .foregroundStyle(Color.jtTextTertiary)
                        }
                        .padding(.vertical, JellytoneTheme.Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                    .accessibilityIdentifier("search-recent-\(term)")
                    if term != recentSearches.last {
                        Rectangle().fill(Color.jtBorder).frame(height: 1)
                    }
                }
            }
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
            // Stable idle title (UI tests + first-run copy). Recent searches, when
            // present, sit above this block as their own section.
            Text("Search your music")
                .font(.jtSectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Find songs, artists, albums, and playlists across your selected Jellyfin music library.")
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
            Text("Browse")
                .font(.jtSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .padding(.top, JellytoneTheme.Space.sm)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                browseRow("Playlists", systemImage: "music.note.list",
                          identifier: "search-browse-playlists", section: .playlists)
                Rectangle().fill(Color.jtBorder).frame(height: 1)
                browseRow("Artists", systemImage: "music.mic",
                          identifier: "search-browse-artists", section: .artists)
                Rectangle().fill(Color.jtBorder).frame(height: 1)
                browseRow("Albums", systemImage: "square.stack",
                          identifier: "search-browse-albums", section: .albums)
                Rectangle().fill(Color.jtBorder).frame(height: 1)
                browseRow("Songs", systemImage: "music.note",
                          identifier: "search-browse-songs", section: .songs)
                Rectangle().fill(Color.jtBorder).frame(height: 1)
                browseRow("Genres", systemImage: "guitars",
                          identifier: "search-browse-genres", section: .genres)
                Rectangle().fill(Color.jtBorder).frame(height: 1)
                browseRow("Favourites", systemImage: "heart.fill",
                          identifier: "search-browse-favourites", section: .favourites)
                Rectangle().fill(Color.jtBorder).frame(height: 1)
                browseRow("Downloads", systemImage: "arrow.down.circle",
                          identifier: "search-browse-downloads", section: .downloads)
            }
        }
    }

    private func browseRow(
        _ title: String,
        systemImage: String,
        identifier: String,
        section: LibrarySection
    ) -> some View {
        NavigationLink(value: section) {
            HStack(spacing: JellytoneTheme.Space.mdPlus) {
                Image(systemName: systemImage)
                    .font(.jtSubsectionHeader.weight(.medium))
                    .foregroundStyle(Color.jtAccent)
                    .frame(width: SearchMetrics.categoryIconWidth)
                Text(title)
                    .font(.jtSubsectionHeader.weight(.medium))
                    .foregroundStyle(Color.jtTextPrimary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.jtCaption.weight(.bold))
                    .foregroundStyle(Color.jtTextTertiary)
            }
            .padding(.vertical, JellytoneTheme.Space.mdPlus)
            .contentShape(Rectangle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Browse \(title.lowercased())")
    }

    @ViewBuilder
    private func searchBrowseDestination(_ section: LibrarySection) -> some View {
        switch section {
        case .playlists: PlaylistLibraryView()
        case .artists: ArtistLibraryView()
        case .albums: AlbumLibraryView()
        case .songs: TrackCatalogView()
        case .genres: GenreLibraryView()
        case .favourites:
            FavouritesLibraryView(
                scope: FavouritesFeatureScope(
                    serverID: model.session?.serverID ?? "",
                    accountID: model.session?.userID ?? "",
                    libraryID: model.selectedLibraryID
                ),
                loadArtists: { try await model.favouriteArtistsPage(startIndex: $0) },
                loadAlbums: { try await model.favouriteAlbumsPage(startIndex: $0) },
                loadTracks: { try await model.favouriteTracksPage(startIndex: $0) },
                play: { model.play($0, in: $1) },
                playAll: { model.playAll($0) },
                shuffle: { model.shuffle($0) }
            )
        case .downloads: DownloadsView()
        }
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                if !topResults.isEmpty {
                    sectionHeader("Top Results")
                    VStack(spacing: 0) {
                        ForEach(Array(topResults.enumerated()), id: \.element.id) { index, hit in
                            topResultRow(hit, isLast: index == topResults.count - 1)
                        }
                    }
                }

                if !search.tracks.isEmpty {
                    sectionHeader("Songs")
                    VStack(spacing: 0) {
                        ForEach(Array(search.tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                model.play(track, in: search.tracks)
                                RecentMusicSearches.remember(search.query)
                                recentSearches = RecentMusicSearches.load()
                            } label: {
                                SearchSongRow(
                                    track: track,
                                    isLast: index == search.tracks.count - 1
                                )
                            }
                            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                            .accessibilityIdentifier("search-track-\(track.id)")
                            .accessibilityLabel("Song, \(track.name), by \(track.artist)")
                            .accessibilityHint("Plays this song")
                            .contextMenu {
                                trackContextMenu(track)
                            }
                        }
                    }
                }

                if !search.albums.isEmpty {
                    sectionHeader("Albums")
                    VStack(spacing: 0) {
                        ForEach(Array(search.albums.enumerated()), id: \.element.id) { index, album in
                            NavigationLink(value: album) {
                                SearchEntityRow(
                                    itemID: album.id,
                                    imageTag: album.imageTag,
                                    title: album.name,
                                    subtitle: album.artist,
                                    trailing: album.productionYear.map(String.init),
                                    circular: false,
                                    isLast: index == search.albums.count - 1
                                )
                            }
                            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                            .accessibilityIdentifier("search-album-\(album.id)")
                            .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                            .accessibilityHint("Opens album")
                        }
                    }
                }

                if !search.artists.isEmpty {
                    sectionHeader("Artists")
                    VStack(spacing: 0) {
                        ForEach(Array(search.artists.enumerated()), id: \.element.id) { index, artist in
                            NavigationLink(value: artist) {
                                SearchEntityRow(
                                    itemID: artist.id,
                                    imageTag: artist.imageTag,
                                    title: artist.name,
                                    subtitle: "Artist",
                                    trailing: nil,
                                    circular: true,
                                    isLast: index == search.artists.count - 1
                                )
                            }
                            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                            .accessibilityIdentifier("search-artist-\(artist.id)")
                            .accessibilityLabel("Artist, \(artist.name)")
                            .accessibilityHint("Opens artist")
                        }
                    }
                }

                if !search.playlists.isEmpty {
                    sectionHeader("Playlists")
                    VStack(spacing: 0) {
                        ForEach(Array(search.playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink(value: playlist) {
                                SearchEntityRow(
                                    itemID: playlist.id,
                                    imageTag: playlist.imageTag,
                                    title: playlist.name,
                                    subtitle: playlist.itemCount.map { "\($0) songs" } ?? "Playlist",
                                    trailing: nil,
                                    circular: false,
                                    isLast: index == search.playlists.count - 1
                                )
                            }
                            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                            .accessibilityIdentifier("search-playlist-\(playlist.id)")
                            .accessibilityLabel("Playlist, \(playlist.name)")
                            .accessibilityHint("Opens playlist")
                        }
                    }
                }

                if search.canLoadMore || search.isLoadingMore || search.paginationError != nil {
                    paginationFooter
                        .task {
                            if search.canLoadMore && !search.isLoadingMore {
                                await loadMore()
                            }
                        }
                }
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.md)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        // Cache/interim results stay on screen while the network merge lands —
        // no spinner overlay over painted rows (Priority 5 silent refresh).
        .animation(JellytoneTheme.Motion.crossfade, value: search.artists.map(\.id))
        .animation(JellytoneTheme.Motion.crossfade, value: search.albums.map(\.id))
        .animation(JellytoneTheme.Motion.crossfade, value: search.tracks.map(\.id))
        .animation(JellytoneTheme.Motion.crossfade, value: search.playlists.map(\.id))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.jtSectionHeader)
            .foregroundStyle(Color.jtTextPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Top Results

    /// Up to four strong hits (one of each type) when the query looks like a
    /// name match — prefix or exact, case/diacritic insensitive.
    private var topResults: [SearchTopHit] {
        let q = SearchMatch.normalized(search.query)
        guard !q.isEmpty else { return [] }
        var hits: [SearchTopHit] = []
        if let artist = search.artists.first(where: { SearchMatch.isStrong($0.name, query: q) })
            ?? search.artists.first {
            hits.append(.artist(artist))
        }
        if let album = search.albums.first(where: { SearchMatch.isStrong($0.name, query: q) })
            ?? search.albums.first {
            hits.append(.album(album))
        }
        if let track = search.tracks.first(where: { SearchMatch.isStrong($0.name, query: q) })
            ?? search.tracks.first {
            hits.append(.track(track))
        }
        if let playlist = search.playlists.first(where: { SearchMatch.isStrong($0.name, query: q) })
            ?? search.playlists.first {
            hits.append(.playlist(playlist))
        }
        // Only show Top Results when there is more than one section overall,
        // or at least one strong name match — avoids a redundant single row.
        var sectionCount = 0
        if !search.tracks.isEmpty { sectionCount += 1 }
        if !search.albums.isEmpty { sectionCount += 1 }
        if !search.artists.isEmpty { sectionCount += 1 }
        if !search.playlists.isEmpty { sectionCount += 1 }
        let hasStrong = hits.contains { hit in
            switch hit {
            case .artist(let a): return SearchMatch.isStrong(a.name, query: q)
            case .album(let a): return SearchMatch.isStrong(a.name, query: q)
            case .track(let t): return SearchMatch.isStrong(t.name, query: q)
            case .playlist(let p): return SearchMatch.isStrong(p.name, query: q)
            }
        }
        guard sectionCount > 1 || hasStrong else { return [] }
        return Array(hits.prefix(4))
    }

    @ViewBuilder
    private func topResultRow(_ hit: SearchTopHit, isLast: Bool) -> some View {
        switch hit {
        case .artist(let artist):
            NavigationLink(value: artist) {
                SearchEntityRow(
                    itemID: artist.id,
                    imageTag: artist.imageTag,
                    title: artist.name,
                    subtitle: "Artist",
                    trailing: nil,
                    circular: true,
                    isLast: isLast
                )
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("search-top-artist-\(artist.id)")
        case .album(let album):
            NavigationLink(value: album) {
                SearchEntityRow(
                    itemID: album.id,
                    imageTag: album.imageTag,
                    title: album.name,
                    subtitle: album.artist,
                    trailing: "Album",
                    circular: false,
                    isLast: isLast
                )
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("search-top-album-\(album.id)")
        case .track(let track):
            Button {
                model.play(track, in: search.tracks)
            } label: {
                SearchSongRow(track: track, isLast: isLast, kindLabel: "Song")
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("search-top-track-\(track.id)")
        case .playlist(let playlist):
            NavigationLink(value: playlist) {
                SearchEntityRow(
                    itemID: playlist.id,
                    imageTag: playlist.imageTag,
                    title: playlist.name,
                    subtitle: playlist.itemCount.map { "\($0) songs" } ?? "Playlist",
                    trailing: "Playlist",
                    circular: false,
                    isLast: isLast
                )
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("search-top-playlist-\(playlist.id)")
        }
    }

    // MARK: Chrome helpers

    private var paginationFooter: some View {
        VStack(spacing: JellytoneTheme.Space.sm) {
            if search.isLoadingMore {
                ProgressView("Loading more results…")
                    .font(.jtBody)
                    .foregroundStyle(Color.jtTextSecondary)
                    .frame(maxWidth: .infinity)
            } else if let message = search.paginationError {
                Text(message)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry More Results") {
                    Task { await loadMore() }
                }
                .buttonStyle(.jtCapsule(.secondaryFlat))
            }
        }
        .padding(.vertical, JellytoneTheme.Space.md)
    }

    private func searchStateCard(
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: JellytoneTheme.Space.md) {
            Spacer(minLength: JellytoneTheme.Space.xxxl)
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
                Text(title)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                Text(detail)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.jtCapsule(.secondaryFlat))
                        .padding(.top, JellytoneTheme.Space.xxs)
                }
            }
            .padding(JellytoneTheme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.jtSurface,
                in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
            )
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func trackContextMenu(_ track: Track) -> some View {
        let liked = model.isFavourite(track.id)
        Button(liked ? "Unfavourite" : "Favourite",
               systemImage: liked ? "heart.slash" : "heart") {
            model.toggleFavourite(id: track.id)
        }
        Button("Play Next", systemImage: "text.insert") { model.playNext(track) }
            .disabled(model.playback.currentTrack == nil)
        Button("Add to Queue", systemImage: "text.badge.plus") { model.addToQueue(track) }
            .disabled(model.playback.currentTrack == nil)
        if let albumID = track.albumID, !track.album.isEmpty {
            NavigationLink("Go to Album") {
                AlbumView(album: Album(
                    id: albumID,
                    name: track.album,
                    artist: track.artist,
                    productionYear: nil,
                    imageTag: track.imageTag
                ))
            }
        }
        if let artistID = track.artistID, !track.artist.isEmpty {
            NavigationLink("Go to Artist") {
                ArtistView(artist: Artist(id: artistID, name: track.artist, imageTag: nil))
            }
        }
    }

    private func retrySearch() async {
        await search.search(query: query, debounceNanoseconds: 0) { value, startIndex, present in
            try await model.searchMusic(query: value, startIndex: startIndex, present: present)
        }
    }

    private func loadMore() async {
        await search.loadMore { value, startIndex, present in
            try await model.searchMusic(query: value, startIndex: startIndex, present: present)
        }
    }
}

// MARK: - Rows

private enum SearchTopHit: Identifiable {
    case artist(Artist)
    case album(Album)
    case track(Track)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .artist(let a): return "top-artist-\(a.id)"
        case .album(let a): return "top-album-\(a.id)"
        case .track(let t): return "top-track-\(t.id)"
        case .playlist(let p): return "top-playlist-\(p.id)"
        }
    }
}

private enum SearchMatch {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    static func isStrong(_ name: String, query: String) -> Bool {
        let n = normalized(name)
        return n == query || n.hasPrefix(query)
    }
}

private enum SearchMetrics {
    static let artworkSide: CGFloat = 48
    static let categoryIconWidth: CGFloat = 28
}

private struct SearchSongRow: View {
    let track: Track
    let isLast: Bool
    var kindLabel: String? = nil

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            JellytoneTrackArtwork(track: track)
                .frame(width: SearchMetrics.artworkSide, height: SearchMetrics.artworkSide)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.rowArtwork, style: .continuous))
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: JellytoneTheme.Space.sm)
            if track.durationTicks != nil {
                Text(track.durationLabel)
                    .font(.jtCaption.monospacedDigit())
                    .foregroundStyle(Color.jtTextTertiary)
            }
        }
        .padding(.vertical, JellytoneTheme.Space.smPlus)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.jtBorder).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let kindLabel { parts.append(kindLabel) }
        if !track.artist.isEmpty { parts.append(track.artist) }
        if !track.album.isEmpty { parts.append(track.album) }
        return parts.joined(separator: " · ")
    }
}

private struct SearchEntityRow: View {
    let itemID: String
    let imageTag: String?
    let title: String
    let subtitle: String
    let trailing: String?
    let circular: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            artwork
                .frame(width: SearchMetrics.artworkSide, height: SearchMetrics.artworkSide)
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(title)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: JellytoneTheme.Space.sm)
            if let trailing {
                Text(trailing)
                    .font(.jtCaption)
                    .foregroundStyle(Color.jtTextTertiary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.forward")
                .font(.jtCaption.weight(.bold))
                .foregroundStyle(Color.jtTextTertiary)
        }
        .padding(.vertical, JellytoneTheme.Space.smPlus)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.jtBorder).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        let image = JellytoneItemArtwork(itemID: itemID, imageTag: imageTag, name: title)
        if circular {
            image.clipShape(Circle())
        } else {
            image.clipShape(
                RoundedRectangle(cornerRadius: JellytoneTheme.Radius.rowArtwork, style: .continuous)
            )
        }
    }
}
