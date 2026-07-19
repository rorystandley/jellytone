import SwiftUI

/// Read-only favourites browsing. Data loading and navigation are injected so this
/// surface stays independent of `AppModel` and can be reused by another coordinator.
struct FavouritesLibraryView<ArtistDestination: View, AlbumDestination: View>: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = FavouritesState()

    let scope: FavouritesFeatureScope
    let loadArtists: (Int) async throws -> FavouriteArtistPage
    let loadAlbums: (Int) async throws -> FavouriteAlbumPage
    let loadTracks: (Int) async throws -> FavouriteTrackPage
    let artistDestination: (Artist) -> ArtistDestination
    let albumDestination: (Album) -> AlbumDestination
    let play: (FavouriteTrackOccurrence, [FavouriteTrackOccurrence]) -> Void
    let playAll: ([FavouriteTrackOccurrence]) -> Void
    let shuffle: ([FavouriteTrackOccurrence]) -> Void

    var body: some View {
        content
        .navigationTitle("Favourites")
        .audioCanvas()
        .accessibilityIdentifier("favourites-screen")
        .refreshable { await refresh() }
        .overlay(alignment: .top) {
            if isRefreshingWithContent {
                ProgressView("Refreshing favourites…")
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .task(id: scope) { await load() }
    }

    private var isRefreshingWithContent: Bool {
        (state.isLoadingArtists || state.isLoadingAlbums || state.isLoadingTracks)
            && (!state.artists.isEmpty || !state.albums.isEmpty || !state.trackOccurrences.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if allSectionsFailedWithoutContent {
            AudioStateView(kind: .error, title: "Couldn’t load favourites",
                           detail: "Jellyfin could not load your favourite music right now.",
                           actionTitle: "Try Again") { Task { await refresh() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else if state.hasLoaded && hasNoContent && allErrorsAreNil {
            AudioStateView(kind: .empty, title: "No favourites found",
                           detail: "Favourite artists, albums, and tracks will appear here.")
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else {
            AudioBrowseContainer(spacing: AudioDesign.Space.xl) {
                trackActions
                artistsSection
                albumsSection
                tracksSection
            }
        }
    }

    private var hasNoContent: Bool {
        state.artists.isEmpty && state.albums.isEmpty && state.trackOccurrences.isEmpty
    }

    private var allErrorsAreNil: Bool {
        state.artistErrorMessage == nil && state.albumErrorMessage == nil && state.trackErrorMessage == nil
    }

    private var allSectionsFailedWithoutContent: Bool {
        state.hasLoaded && hasNoContent
            && state.artistErrorMessage != nil
            && state.albumErrorMessage != nil
            && state.trackErrorMessage != nil
    }

    @ViewBuilder
    private var trackActions: some View {
        if !state.trackOccurrences.isEmpty {
            AudioPlayActions(isDisabled: false, play: { playAll(state.trackOccurrences) },
                             shuffle: { shuffle(state.trackOccurrences) },
                             playIdentifier: "favourites-play-all", shuffleIdentifier: "favourites-shuffle")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        sectionHeading("Artists", systemImage: "music.mic")
        if state.isLoadingArtists && state.artists.isEmpty {
            loading("Loading favourite artists…")
        } else if let message = state.artistErrorMessage, state.artists.isEmpty {
            sectionFailure("Couldn’t load favourite artists", message: message, retry: refresh)
        } else if state.hasLoadedArtists && state.artists.isEmpty {
            emptySection("No favourite artists", description: "Favourite artists will appear here.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: AudioDesign.Space.md) {
                    ForEach(state.artists) { artist in
                        NavigationLink { artistDestination(artist) } label: { FavouriteArtistCard(artist: artist) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("favourites-artist-\(artist.id)")
                            .task { if artist.id == state.artists.last?.id { await loadMoreArtists() } }
                    }
                }
            }
            sectionPagination(
                isLoading: state.isLoadingMoreArtists,
                error: state.artistPaginationError,
                loadingTitle: "Loading more favourite artists…",
                retryTitle: "Retry More Artists",
                identifier: "favourites-retry-more-artists",
                retry: loadMoreArtists
            )
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        sectionHeading("Albums", systemImage: "square.stack")
        if state.isLoadingAlbums && state.albums.isEmpty {
            loading("Loading favourite albums…")
        } else if let message = state.albumErrorMessage, state.albums.isEmpty {
            sectionFailure("Couldn’t load favourite albums", message: message, retry: refresh)
        } else if state.hasLoadedAlbums && state.albums.isEmpty {
            emptySection("No favourite albums", description: "Favourite albums will appear here.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: AudioDesign.Space.md) {
                    ForEach(state.albums) { album in
                        NavigationLink { albumDestination(album) } label: { FavouriteAlbumCard(album: album) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("favourites-album-\(album.id)")
                            .task { if album.id == state.albums.last?.id { await loadMoreAlbums() } }
                    }
                }
            }
            sectionPagination(
                isLoading: state.isLoadingMoreAlbums,
                error: state.albumPaginationError,
                loadingTitle: "Loading more favourite albums…",
                retryTitle: "Retry More Albums",
                identifier: "favourites-retry-more-albums",
                retry: loadMoreAlbums
            )
        }
    }

    @ViewBuilder
    private var tracksSection: some View {
        sectionHeading("Tracks", systemImage: "music.note")
        if state.isLoadingTracks && state.trackOccurrences.isEmpty {
            loading("Loading favourite tracks…")
        } else if let message = state.trackErrorMessage, state.trackOccurrences.isEmpty {
            sectionFailure("Couldn’t load favourite tracks", message: message, retry: refresh)
        } else if state.hasLoadedTracks && state.trackOccurrences.isEmpty {
            emptySection("No favourite tracks", description: "Favourite tracks will appear here.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.trackOccurrences.enumerated()), id: \.element.id) { offset, occurrence in
                    Button { play(occurrence, state.trackOccurrences) } label: {
                        HStack {
                            FavouriteTrackRow(position: offset + 1, occurrence: occurrence)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("favourites-track-\(occurrence.id)")
                    .accessibilityLabel(trackLabel(occurrence, position: offset + 1))
                    .accessibilityHint("Starts playback from this favourite occurrence")
                    .task { if offset == state.trackOccurrences.indices.last { await loadMoreTracks() } }
                    Divider()
                }
            }
            sectionPagination(
                isLoading: state.isLoadingMoreTracks,
                error: state.trackPaginationError,
                loadingTitle: "Loading more favourite tracks…",
                retryTitle: "Retry More Tracks",
                identifier: "favourites-retry-more-tracks",
                retry: loadMoreTracks
            )
        }
    }

    private func sectionHeading(_ title: String, systemImage: String) -> some View {
        AudioSectionHeading(title: title, systemImage: systemImage)
    }

    private func loading(_ title: String) -> some View {
        HStack { Spacer(); ProgressView(title); Spacer() }
            .frame(minHeight: 72)
    }

    private func emptySection(_ title: String, description: String) -> some View {
        AudioStateView(kind: .empty, title: title, detail: description)
            .frame(maxWidth: .infinity)
    }

    private func sectionFailure(
        _ title: String,
        message: String,
        retry: @escaping () async -> Void
    ) -> some View {
        AudioStateView(kind: .error, title: title, detail: message,
                       actionTitle: "Try Again") { Task { await retry() } }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sectionPagination(
        isLoading: Bool,
        error: String?,
        loadingTitle: String,
        retryTitle: String,
        identifier: String,
        retry: @escaping () async -> Void
    ) -> some View {
        if isLoading {
            ProgressView(loadingTitle)
                .frame(maxWidth: .infinity)
        } else if let error {
            VStack(spacing: 8) {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button(retryTitle) { Task { await retry() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(identifier)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func trackLabel(_ occurrence: FavouriteTrackOccurrence, position: Int) -> String {
        let track = occurrence.track
        let duration = track.durationTicks == nil ? "" : ", \(track.durationLabel)"
        return "\(position). \(track.name), \(track.artist), \(track.album)\(duration)"
    }

    private func load() async {
        await state.load(
            scope: scope,
            loadArtists: loadArtists,
            loadAlbums: loadAlbums,
            loadTracks: loadTracks
        )
    }

    private func refresh() async {
        await state.refresh(
            scope: scope,
            loadArtists: loadArtists,
            loadAlbums: loadAlbums,
            loadTracks: loadTracks
        )
    }

    private func loadMoreArtists() async { await state.loadMoreArtists(scope: scope, loadPage: loadArtists) }
    private func loadMoreAlbums() async { await state.loadMoreAlbums(scope: scope, loadPage: loadAlbums) }
    private func loadMoreTracks() async { await state.loadMoreTracks(scope: scope, loadPage: loadTracks) }
}

private struct FavouriteArtistCard: View {
    let artist: Artist

    var body: some View {
        AudioMusicCard(title: artist.name, subtitle: "Artist", circular: true) {
            favouriteArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name, symbol: "music.mic")
        }
        .frame(width: 156)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(artist.name)
        .accessibilityHint("Opens artist")
    }
}

private struct FavouriteAlbumCard: View {
    let album: Album

    var body: some View {
        AudioMusicCard(title: album.name, subtitle: album.artist,
                       detail: album.productionYear.map(String.init)) {
            favouriteArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name, symbol: "square.stack")
        }
        .frame(width: 156)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), by \(album.artist)\(album.productionYear.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens album")
    }
}

private struct FavouriteTrackRow: View {
    let position: Int
    let occurrence: FavouriteTrackOccurrence

    var body: some View {
        AudioTrackRow(position: position, title: occurrence.track.name, artist: occurrence.track.artist,
                      album: occurrence.track.album,
                      duration: occurrence.track.durationTicks == nil ? nil : occurrence.track.durationLabel)
    }
}

@MainActor @ViewBuilder
private func favouriteArtwork(itemID: String, imageTag: String?, name: String, symbol: String) -> some View {
    if imageTag != nil {
        AuthenticatedArtworkView(itemID: itemID, accessibilityLabel: "Artwork for \(name)")
    } else {
        AudioMissingArtwork(label: name, systemImage: symbol)
    }
}
