import SwiftUI

/// Read-only favourites browsing. Data loading is injected so this surface stays
/// independent of `AppModel`; navigation is value-based (artists and albums push
/// through the destinations the host stack registers at its root).
/// Themed per design-system.md and AGENTS.md Priority 4.
struct FavouritesLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = FavouritesState()

    let scope: FavouritesFeatureScope
    let loadArtists: (Int) async throws -> FavouriteArtistPage
    let loadAlbums: (Int) async throws -> FavouriteAlbumPage
    let loadTracks: (Int) async throws -> FavouriteTrackPage
    let play: (FavouriteTrackOccurrence, [FavouriteTrackOccurrence]) -> Void
    let playAll: ([FavouriteTrackOccurrence]) -> Void
    let shuffle: ([FavouriteTrackOccurrence]) -> Void

    var body: some View {
        content
            .background(Color.jtBackground.ignoresSafeArea())
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier("favourites-screen")
            .refreshable { await refresh() }
            .task(id: scope) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if allSectionsFailedWithoutContent {
            stateCard(
                title: "Couldn’t load favourites",
                detail: "Jellyfin could not load your favourite music right now.",
                actionTitle: "Try Again"
            ) {
                Task { await refresh() }
            }
        } else if isInitialLoading {
            ScrollView {
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                    JellytoneSkeletonRows(rows: 6, label: "Loading favourites")
                }
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, JellytoneTheme.Space.md)
            }
        } else if state.hasLoaded && hasNoContent && allErrorsAreNil {
            stateCard(
                title: "No favourites found",
                detail: "Favourite artists, albums, and tracks will appear here."
            )
        } else {
            favouritesScroll
        }
    }

    private var isInitialLoading: Bool {
        !state.hasLoaded
            && hasNoContent
            && (state.isLoadingArtists || state.isLoadingAlbums || state.isLoadingTracks)
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

    private var favouritesScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                trackActions
                artistsSection
                albumsSection
                tracksSection
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.sm)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
    }

    @ViewBuilder
    private var trackActions: some View {
        if !state.trackOccurrences.isEmpty {
            HStack(spacing: JellytoneTheme.Space.md) {
                Button {
                    playAll(state.trackOccurrences)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.jtCapsule(.primaryFlat))
                .accessibilityIdentifier("favourites-play-all")

                Button {
                    shuffle(state.trackOccurrences)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(.jtCapsule(.secondaryFlat))
                .accessibilityIdentifier("favourites-shuffle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        sectionHeading("Artists")
        if state.isLoadingArtists && state.artists.isEmpty {
            loadingRow("Loading favourite artists…")
        } else if let message = state.artistErrorMessage, state.artists.isEmpty {
            sectionFailure("Couldn’t load favourite artists", message: message, retry: refresh)
        } else if state.hasLoadedArtists && state.artists.isEmpty {
            emptySection("No favourite artists", description: "Favourite artists will appear here.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.md) {
                    ForEach(state.artists) { artist in
                        NavigationLink(value: artist) {
                            FavouriteArtistCard(artist: artist)
                        }
                        .buttonStyle(.jtPressScale())
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
        sectionHeading("Albums")
        if state.isLoadingAlbums && state.albums.isEmpty {
            loadingRow("Loading favourite albums…")
        } else if let message = state.albumErrorMessage, state.albums.isEmpty {
            sectionFailure("Couldn’t load favourite albums", message: message, retry: refresh)
        } else if state.hasLoadedAlbums && state.albums.isEmpty {
            emptySection("No favourite albums", description: "Favourite albums will appear here.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.md) {
                    ForEach(state.albums) { album in
                        NavigationLink(value: album) {
                            FavouriteAlbumCard(album: album)
                        }
                        .buttonStyle(.jtPressScale())
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
        sectionHeading("Songs")
        if state.isLoadingTracks && state.trackOccurrences.isEmpty {
            loadingRow("Loading favourite tracks…")
        } else if let message = state.trackErrorMessage, state.trackOccurrences.isEmpty {
            sectionFailure("Couldn’t load favourite tracks", message: message, retry: refresh)
        } else if state.hasLoadedTracks && state.trackOccurrences.isEmpty {
            emptySection("No favourite tracks", description: "Favourite tracks will appear here.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.trackOccurrences.enumerated()), id: \.element.id) { offset, occurrence in
                    Button {
                        play(occurrence, state.trackOccurrences)
                    } label: {
                        FavouriteTrackRow(
                            occurrence: occurrence,
                            isLast: offset == state.trackOccurrences.count - 1
                        )
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("favourites-track-\(occurrence.id)")
                    .accessibilityLabel(trackLabel(occurrence, position: offset + 1))
                    .accessibilityHint("Starts playback from this favourite occurrence")
                    .task { if offset == state.trackOccurrences.indices.last { await loadMoreTracks() } }
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

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.jtSectionHeader)
            .foregroundStyle(Color.jtTextPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingRow(_ title: String) -> some View {
        ProgressView(title)
            .font(.jtBody)
            .foregroundStyle(Color.jtTextSecondary)
            .frame(maxWidth: .infinity, minHeight: 72)
    }

    private func emptySection(_ title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
            Text(title)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text(description)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
        }
        .padding(JellytoneTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.jtSurface,
            in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
        )
    }

    private func sectionFailure(
        _ title: String,
        message: String,
        retry: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text(title)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text(message)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
            Button("Try Again") { Task { await retry() } }
                .buttonStyle(.jtCapsule(.secondaryFlat))
        }
        .padding(JellytoneTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.jtSurface,
            in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
        )
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
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
                .frame(maxWidth: .infinity)
        } else if let error {
            VStack(spacing: JellytoneTheme.Space.sm) {
                Text(error)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .multilineTextAlignment(.center)
                Button(retryTitle) { Task { await retry() } }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
                    .accessibilityIdentifier(identifier)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stateCard(
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, JellytoneTheme.Space.md)
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

private enum FavouritesMetrics {
    static let cardSide: CGFloat = 140
    static let artworkSide: CGFloat = 48
    static let artistCircle: CGFloat = 120
}

private struct FavouriteArtistCard: View {
    let artist: Artist

    var body: some View {
        VStack(spacing: JellytoneTheme.Space.sm) {
            JellytoneItemArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name)
                .frame(width: FavouritesMetrics.artistCircle, height: FavouritesMetrics.artistCircle)
                .clipShape(Circle())
            Text(artist.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(width: FavouritesMetrics.artistCircle)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(artist.name)
        .accessibilityHint("Opens artist")
    }
}

private struct FavouriteAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            JellytoneItemArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
                .frame(width: FavouritesMetrics.cardSide, height: FavouritesMetrics.cardSide)
                .clipShape(
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.gridArtwork, style: .continuous)
                )
            Text(album.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
            Text(album.artist)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(1)
        }
        .frame(width: FavouritesMetrics.cardSide, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), by \(album.artist)\(album.productionYear.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens album")
    }
}

private struct FavouriteTrackRow: View {
    let occurrence: FavouriteTrackOccurrence
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            JellytoneTrackArtwork(track: occurrence.track)
                .frame(width: FavouritesMetrics.artworkSide, height: FavouritesMetrics.artworkSide)
                .clipShape(
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.rowArtwork, style: .continuous)
                )
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(occurrence.track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: JellytoneTheme.Space.sm)
            if occurrence.track.durationTicks != nil {
                Text(occurrence.track.durationLabel)
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
        if !occurrence.track.artist.isEmpty { parts.append(occurrence.track.artist) }
        if !occurrence.track.album.isEmpty { parts.append(occurrence.track.album) }
        return parts.joined(separator: " · ")
    }
}
