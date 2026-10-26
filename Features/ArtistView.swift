import SwiftUI

/// Apple Music-style artist detail: blurred artwork backdrop, centred circular
/// portrait, identity block with shuffle + solid accent play, "Top Songs" rows,
/// then the artist's releases as an album grid. Cache-first: the last visit's
/// snapshot paints instantly and the network refresh lands silently — the only
/// cold-start affordance is the skeleton, never a loading chip. Themed per
/// docs/design/design-system.md.
///
/// Album navigation is value-based and resolves through the destination the
/// host stack registers at its root (Search and Library both do). Declaring a
/// duplicate `navigationDestination(for: Album.self)` here — inside a pushed
/// screen — is unsupported and broke album taps into re-pushing this screen.
struct ArtistView: View {
    @EnvironmentObject private var model: AppModel
    let artist: Artist
    @State private var topTracks: [Track] = []
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextStartIndex = 0
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                portrait
                identity
                content
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.lg)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        .background(
            JellytoneDetailBackdrop {
                JellytoneItemArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name)
            }
        )
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .animation(JellytoneTheme.Motion.crossfade, value: albums)
        .animation(JellytoneTheme.Motion.crossfade, value: topTracks)
        .task(id: artist.id) { await load() }
    }

    // MARK: Header

    private var portrait: some View {
        JellytoneItemArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name)
            .frame(width: ArtistMetrics.portraitSide, height: ArtistMetrics.portraitSide)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
            Text("Artist")
                .jtEyebrowStyle()
                .foregroundStyle(Color.jtTextTertiary)
            Text(artist.name)
                .font(.jtDetailTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: JellytoneTheme.Space.xl) {
                Spacer()
                // Liking an artist is independent of whether they have top
                // songs, so the heart stays enabled while playback dims.
                FavouriteHeartButton(itemID: artist.id, identifierPrefix: "artist")
                HStack(spacing: JellytoneTheme.Space.xl) {
                    Button { model.shuffle(topTracks) } label: {
                        Image(systemName: "shuffle")
                            .font(.jtSubsectionHeader)
                            .foregroundStyle(Color.jtTextPrimary)
                            .frame(width: DetailMetrics.secondaryActionSide, height: DetailMetrics.secondaryActionSide)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                    .accessibilityIdentifier("artist-shuffle")
                    .accessibilityLabel("Shuffle top songs")
                    Button {
                        if let first = topTracks.first { model.play(first, in: topTracks) }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: DetailMetrics.playDiameter / 3, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: DetailMetrics.playDiameter, height: DetailMetrics.playDiameter)
                            .background(Circle().fill(Color.jtAccent))
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                    .accessibilityIdentifier("artist-play-all")
                    .accessibilityLabel("Play top songs")
                }
                .disabled(topTracks.isEmpty)
                .opacity(topTracks.isEmpty ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sections

    @ViewBuilder private var content: some View {
        if isLoading, topTracks.isEmpty, albums.isEmpty {
            JellytoneSkeletonRows(label: "Loading artist")
        } else if let errorMessage, topTracks.isEmpty, albums.isEmpty {
            failureCard(message: errorMessage)
        } else if topTracks.isEmpty, albums.isEmpty {
            detailStateCard(title: "No music found",
                            detail: "Jellyfin did not return songs or albums for this artist.")
        } else {
            topSongsSection
            albumsSection
        }
    }

    @ViewBuilder private var topSongsSection: some View {
        if !topTracks.isEmpty {
            Text("Top Songs")
                .font(.jtSectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVStack(spacing: 0) {
                ForEach(topTracks) { track in
                    Button { model.play(track, in: topTracks) } label: {
                        ArtistTopSongRow(track: track, isLast: track.id == topTracks.last?.id)
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("artist-top-track-\(track.id)")
                    .accessibilityLabel("Song, \(track.name), by \(track.artist)")
                    .accessibilityHint("Plays this song")
                    .contextMenu {
                        let liked = model.isFavourite(track.id)
                        Button(liked ? "Unfavourite" : "Favourite",
                               systemImage: liked ? "heart.slash" : "heart") {
                            model.toggleFavourite(id: track.id)
                        }
                        Button("Play Next", systemImage: "text.insert") { model.playNext(track) }
                            .disabled(model.playback.currentTrack == nil)
                        Button("Add to Queue", systemImage: "text.badge.plus") { model.addToQueue(track) }
                            .disabled(model.playback.currentTrack == nil)
                    }
                }
            }
        }
    }

    @ViewBuilder private var albumsSection: some View {
        if !albums.isEmpty {
            Text("Albums")
                .font(.jtSectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: albumColumns, spacing: JellytoneTheme.Space.lg) {
                ForEach(albums) { album in
                    NavigationLink(value: album) { ArtistAlbumCard(album: album) }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("artist-album-\(album.id)")
                        .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                        .accessibilityHint("Opens album")
                        .task {
                            if album.id == albums.last?.id, hasMore { await loadAlbums(replacing: false) }
                        }
                }
            }
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView("Loading more albums…")
                        .font(.jtBody)
                        .foregroundStyle(Color.jtTextSecondary)
                    Spacer()
                }
            } else if let errorMessage {
                failureCard(message: errorMessage)
            }
        }
    }

    private var albumColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: JellytoneTheme.Space.lg)]
    }

    private func failureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text("Couldn’t load this artist’s music")
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text(message)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.jtCapsule(.secondaryFlat))
                .accessibilityIdentifier("artist-retry")
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
    }

    // MARK: Data

    private func load() async {
        // Paint last visit's snapshot instantly, then refresh silently.
        if albums.isEmpty, let cached = await model.cachedArtistAlbums(for: artist), !cached.isEmpty {
            albums = cached
            isLoading = false
        }
        if topTracks.isEmpty, let cached = await model.cachedArtistTopTracks(for: artist), !cached.isEmpty {
            topTracks = cached
            isLoading = false
        }
        async let songs: Void = refreshTopTracks()
        await loadAlbums(replacing: true)
        await songs
        // Seed heart state for the artist and its now-loaded top songs.
        await model.refreshFavouriteStatus(ids: [artist.id] + topTracks.map(\.id))
        isLoading = false
    }

    private func refreshTopTracks() async {
        guard let fresh = try? await model.artistTopTracks(for: artist) else { return }
        if !fresh.isEmpty || topTracks.isEmpty { topTracks = fresh }
    }

    private func loadAlbums(replacing: Bool) async {
        guard replacing || (hasMore && !isLoadingMore) else { return }
        if !replacing { isLoadingMore = true }
        defer { isLoadingMore = false }
        do {
            let page = try await model.albums(for: artist, startIndex: replacing ? 0 : nextStartIndex)
            if replacing {
                // Keep the cached snapshot on an empty refresh, matching the
                // album screen's silent-refresh contract.
                if !page.albums.isEmpty || albums.isEmpty { albums = page.albums }
            } else {
                let existing = Set(albums.map(\.id))
                albums.append(contentsOf: page.albums.filter { !existing.contains($0.id) })
            }
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum ArtistMetrics {
    static let portraitSide: CGFloat = 200
}

private struct ArtistTopSongRow: View {
    let track: Track
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            JellytoneTrackArtwork(track: track)
                .frame(width: DetailMetrics.rowArtworkSide, height: DetailMetrics.rowArtworkSide)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.smallArtwork, style: .continuous))
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(.jtRowSubtitle)
                        .foregroundStyle(Color.jtTextSecondary)
                        .lineLimit(1)
                }
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
}

private struct ArtistAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            JellytoneItemArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.gridArtwork, style: .continuous))
            Text(album.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
            Text(album.productionYear.map(String.init) ?? album.artist)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
