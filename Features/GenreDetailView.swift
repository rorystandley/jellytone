import SwiftUI

/// Genre detail aligned with Album / Artist / Playlist: blurred artwork
/// backdrop, centred artwork card, left-aligned identity with shuffle + solid
/// accent play, themed album shelf and track rows. Cache-first: header +
/// skeletons paint immediately; network refresh is silent. Themed per
/// docs/design/design-system.md and AGENTS.md Priority 1 (finish design-system
/// migration). Presentation only — same play / push / refresh behaviour.
struct GenreDetailView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = GenreDetailState()

    let genre: Genre

    var body: some View {
        Group {
            // Priority 5: never block the whole screen with a spinner. Header +
            // skeletons paint immediately; cache-first load replaces them silently.
            if let message = initialError,
               state.hasLoaded,
               state.albums.isEmpty,
               state.trackOccurrences.isEmpty {
                unavailable(message)
            } else if state.hasLoaded && state.albums.isEmpty && state.trackOccurrences.isEmpty {
                emptyState
            } else {
                detailList
            }
        }
        .accessibilityIdentifier("genre-detail-screen")
        .navigationTitle(genre.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(
            JellytoneDetailBackdrop { GenreArtwork(genre: genre) }
        )
        .task(id: requestIdentity) { await load() }
    }

    private var scope: GenreFeatureScope {
        GenreFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var requestIdentity: String {
        "\(scope.serverID)|\(scope.accountID)|\(scope.libraryID ?? "")|\(genre.id)"
    }

    private var initialError: String? {
        state.trackErrorMessage ?? state.albumErrorMessage
    }

    private var detailList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                artworkCard
                identity
                albumSection
                trackSection
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.lg)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        // Background refreshes stay silent (Apple Music-style); the system
        // pull spinner is the only refresh indicator.
        .refreshable { await refresh() }
    }

    // MARK: Header

    private var artworkCard: some View {
        GenreArtwork(genre: genre)
            .frame(width: DetailMetrics.artworkSide, height: DetailMetrics.artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.largeArtwork, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
            Text("Genre")
                .jtEyebrowStyle()
                .foregroundStyle(Color.jtTextTertiary)
            Text(genre.name)
                .font(.jtDetailTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(trackCountLabel)
                .font(.jtCaption)
                .foregroundStyle(Color.jtTextTertiary)
            // Secondary bare-glyph actions grouped tightly; the filled play
            // circle sits apart — same language as Album / Artist / Playlist.
            HStack(spacing: JellytoneTheme.Space.xl) {
                FavouriteHeartButton(itemID: genre.id, identifierPrefix: "genre")
                Spacer()
                HStack(spacing: JellytoneTheme.Space.xl) {
                    Button { model.shuffle(state.trackOccurrences) } label: {
                        Image(systemName: "shuffle")
                            .font(.jtSubsectionHeader)
                            .foregroundStyle(Color.jtTextPrimary)
                            .frame(width: DetailMetrics.secondaryActionSide, height: DetailMetrics.secondaryActionSide)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                    .accessibilityIdentifier("genre-shuffle")
                    .accessibilityLabel("Shuffle")
                    Button { model.playAll(state.trackOccurrences) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: DetailMetrics.playDiameter / 3, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: DetailMetrics.playDiameter, height: DetailMetrics.playDiameter)
                            .background(Circle().fill(Color.jtAccent))
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                    .accessibilityIdentifier("genre-play-all")
                    .accessibilityLabel("Play All")
                }
                .disabled(state.trackOccurrences.isEmpty)
                .opacity(state.trackOccurrences.isEmpty ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackCountLabel: String {
        if state.isLoadingTracks && state.trackOccurrences.isEmpty {
            return "Loading…"
        }
        let count = state.trackOccurrences.count
        return count == 1 ? "1 playable track" : "\(count) playable tracks"
    }

    // MARK: Sections

    @ViewBuilder
    private var albumSection: some View {
        if state.isLoadingAlbums && state.albums.isEmpty {
            sectionHeader("Albums")
            JellytoneSkeletonGrid(columns: 2, rows: 1, label: "Loading albums")
                .accessibilityIdentifier("genre-albums-loading-skeleton")
        } else if let message = state.albumErrorMessage, state.albums.isEmpty {
            sectionHeader("Albums")
            retryStatus(message, title: "Retry Albums") { await refresh() }
        } else if state.hasLoadedAlbums && state.albums.isEmpty {
            sectionHeader("Albums")
            Text("No albums found for this genre.")
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
        } else if !state.albums.isEmpty {
            sectionHeader("Albums")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.lg) {
                    ForEach(state.albums) { album in
                        NavigationLink(value: album) {
                            GenreAlbumCard(album: album)
                        }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("genre-album-\(album.id)")
                        .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                        .accessibilityHint("Opens album")
                        .task {
                            if album.id == state.albums.last?.id { await loadMoreAlbums() }
                        }
                    }
                }
                .padding(.vertical, JellytoneTheme.Space.xxs)
            }

            if state.isLoadingMoreAlbums {
                centeredProgress("Loading more albums…")
                    .accessibilityIdentifier("genre-load-more")
            } else if let message = state.albumPaginationError {
                retryStatus(message, title: "Retry More Albums", identifier: "genre-retry-more-albums") {
                    await loadMoreAlbums()
                }
            }
        }
    }

    @ViewBuilder
    private var trackSection: some View {
        if state.isLoadingTracks && state.trackOccurrences.isEmpty {
            sectionHeader("Tracks")
            JellytoneSkeletonRows(rows: 6, label: "Loading tracks")
                .accessibilityIdentifier("genre-tracks-loading-skeleton")
        } else if let message = state.trackErrorMessage, state.trackOccurrences.isEmpty {
            sectionHeader("Tracks")
            retryStatus(message, title: "Retry Tracks") { await refresh() }
        } else if state.hasLoadedTracks && state.trackOccurrences.isEmpty {
            sectionHeader("Tracks")
            Text("No playable tracks found for this genre.")
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
        } else if !state.trackOccurrences.isEmpty {
            sectionHeader("Tracks")
            LazyVStack(spacing: 0) {
                ForEach(Array(state.trackOccurrences.enumerated()), id: \.offset) { offset, occurrence in
                    Button { model.play(occurrence, in: state.trackOccurrences) } label: {
                        GenreTrackRow(
                            position: offset + 1,
                            occurrence: occurrence,
                            isLast: offset == state.trackOccurrences.indices.last
                        )
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("genre-track-\(occurrence.id)")
                    .accessibilityLabel(trackAccessibilityLabel(occurrence, position: offset + 1))
                    .accessibilityHint("Starts playback from this genre occurrence")
                    .contextMenu {
                        let liked = model.isFavourite(occurrence.track.id)
                        Button(liked ? "Unfavourite" : "Favourite",
                               systemImage: liked ? "heart.slash" : "heart") {
                            model.toggleFavourite(id: occurrence.track.id)
                        }
                        Button("Play Next", systemImage: "text.insert") { model.playNext(occurrence.track) }
                            .disabled(model.playback.currentTrack == nil)
                        Button("Add to Queue", systemImage: "text.badge.plus") { model.addToQueue(occurrence.track) }
                            .disabled(model.playback.currentTrack == nil)
                    }
                    .task {
                        if offset == state.trackOccurrences.indices.last { await loadMoreTracks() }
                    }
                }
            }

            if state.isLoadingMoreTracks {
                centeredProgress("Loading more tracks…")
                    .accessibilityIdentifier("genre-load-more")
            } else if let message = state.trackPaginationError {
                retryStatus(message, title: "Retry More Tracks", identifier: "genre-retry-more-tracks") {
                    await loadMoreTracks()
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.jtSectionHeader)
            .foregroundStyle(Color.jtTextPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Empty / error

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
            detailStateCard(title: emptyTitle, detail: emptyDescription)
            Button("Refresh") { Task { await refresh() } }
                .buttonStyle(.jtCapsule(.secondaryFlat))
        }
        .padding(JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyTitle: String {
        (genre.itemCount ?? 0) > 0 ? "No playable audio" : "Empty genre"
    }

    private var emptyDescription: String {
        if (genre.itemCount ?? 0) > 0 {
            return "This genre contains items, but Jellyfin returned no albums or playable audio tracks."
        }
        return "Jellyfin returned no albums or playable tracks for this genre."
    }

    private func unavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
            detailStateCard(title: "Genre unavailable", detail: message)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.jtCapsule(.primaryFlat))
        }
        .padding(JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func centeredProgress(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
            Spacer()
        }
    }

    private func retryStatus(
        _ message: String,
        title: String,
        identifier: String? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(spacing: JellytoneTheme.Space.sm) {
            Text(message)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .multilineTextAlignment(.center)
            Button(title) { Task { await action() } }
                .buttonStyle(.jtCapsule(.secondaryFlat))
                .frame(minHeight: 44)
                .accessibilityIdentifier(identifier ?? "")
        }
        .frame(maxWidth: .infinity)
    }

    private func trackAccessibilityLabel(_ occurrence: GenreTrackOccurrence, position: Int) -> String {
        let track = occurrence.track
        let identity = "Track \(position), \(track.name), by \(track.artist)"
        guard track.durationTicks != nil else { return "\(identity), duration unavailable" }
        return "\(identity), \(track.durationLabel)"
    }

    // MARK: Data

    private func load() async {
        let requestScope = scope
        // Cache-first: the persisted snapshots paint immediately while the
        // network results replace them silently.
        let cachedAlbums = await model.cachedGenreAlbums(for: genre)
        let cachedTracks = await model.cachedGenreTracks(for: genre)
        await state.load(
            genre: genre,
            scope: requestScope,
            cachedAlbums: (cachedAlbums?.isEmpty == false) ? cachedAlbums : nil,
            cachedTracks: (cachedTracks?.isEmpty == false) ? cachedTracks : nil
        ) { startIndex in
            try await model.genreAlbums(for: genre, startIndex: startIndex)
        } loadTracks: { startIndex in
            try await model.genreTracks(for: genre, startIndex: startIndex)
        }
        await model.refreshFavouriteStatus(ids: [genre.id] + state.trackOccurrences.map(\.track.id))
    }

    private func refresh() async {
        let requestScope = scope
        await state.refresh(genre: genre, scope: requestScope) { startIndex in
            try await model.genreAlbums(for: genre, startIndex: startIndex)
        } loadTracks: { startIndex in
            try await model.genreTracks(for: genre, startIndex: startIndex)
        }
    }

    private func loadMoreAlbums() async {
        let requestScope = scope
        await state.loadMoreAlbums(genre: genre, scope: requestScope) { startIndex in
            try await model.genreAlbums(for: genre, startIndex: startIndex)
        }
    }

    private func loadMoreTracks() async {
        let requestScope = scope
        await state.loadMoreTracks(genre: genre, scope: requestScope) { startIndex in
            try await model.genreTracks(for: genre, startIndex: startIndex)
        }
    }
}

// MARK: - Rows / cards

private enum GenreDetailMetrics {
    /// Horizontal album shelf card — matches prior density, themed materials.
    static let albumCardSide: CGFloat = 132
}

private struct GenreAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            JellytoneItemArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
                .frame(width: GenreDetailMetrics.albumCardSide, height: GenreDetailMetrics.albumCardSide)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.gridArtwork, style: .continuous))
            Text(album.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(album.artist)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(1)
        }
        .frame(width: GenreDetailMetrics.albumCardSide, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct GenreTrackRow: View {
    let position: Int
    let occurrence: GenreTrackOccurrence
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            Text(String(position))
                .font(.jtCaption.monospacedDigit())
                .foregroundStyle(Color.jtTextTertiary)
                .frame(width: DetailMetrics.trackNumberWidth)
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(occurrence.track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(occurrence.track.artist)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
                if !occurrence.track.album.isEmpty {
                    Text(occurrence.track.album)
                        .font(.jtCaption)
                        .foregroundStyle(Color.jtTextTertiary)
                        .lineLimit(1)
                }
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
}
