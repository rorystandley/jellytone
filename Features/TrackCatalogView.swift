import SwiftUI

/// Full-library Songs catalogue (Library → Songs). Dense artwork rows with
/// play / queue / favourite context menus. Themed per design-system.md.
struct TrackCatalogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        content
            .background(Color.jtBackground.ignoresSafeArea())
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier("library-tracks-screen")
            .refreshable {
                await model.refreshTrackCatalog()
                await model.refreshFavouriteStatus(ids: model.trackCatalogState.occurrences.map(\.track.id))
            }
            .task(id: model.selectedLibraryID) {
                await model.refreshTrackCatalog()
                await model.refreshFavouriteStatus(ids: model.trackCatalogState.occurrences.map(\.track.id))
            }
    }

    @ViewBuilder private var content: some View {
        let state = model.trackCatalogState
        if state.isLoading && state.occurrences.isEmpty {
            ScrollView {
                JellytoneSkeletonRows(rows: 12, label: "Loading tracks")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    .padding(.top, JellytoneTheme.Space.md)
                    .padding(.bottom, JellytoneTheme.Space.xxxl)
            }
            .accessibilityIdentifier("track-catalog-loading-skeleton")
        } else if let error = state.errorMessage, state.occurrences.isEmpty {
            catalogStateCard(
                title: "Couldn’t load tracks",
                detail: error,
                actionTitle: "Try Again"
            ) {
                Task { await model.refreshTrackCatalog() }
            }
        } else if state.hasLoaded && state.occurrences.isEmpty {
            catalogStateCard(
                title: "No tracks found",
                detail: "This music library has no playable audio tracks."
            )
        } else {
            trackList(state: state)
        }
    }

    private func trackList(state: TrackCatalogState) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(state.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                    Button {
                        model.play(occurrence, in: model.trackCatalogState.occurrences)
                    } label: {
                        CatalogTrackRow(
                            track: occurrence.track,
                            isLast: index == state.occurrences.count - 1
                        )
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("track-catalog-row-\(occurrence.id)")
                    .accessibilityLabel(trackLabel(occurrence.track, position: index + 1, total: state.occurrences.count))
                    .accessibilityHint("Starts playback at this displayed track")
                    .contextMenu { trackContextMenu(occurrence.track) }
                    .task {
                        if index == state.occurrences.indices.last {
                            await model.loadMoreTrackCatalog()
                        }
                    }
                }

                paginationFooter(state: state)
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
    }

    @ViewBuilder
    private func paginationFooter(state: TrackCatalogState) -> some View {
        if state.isLoadingMore {
            ProgressView("Loading more tracks…")
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, JellytoneTheme.Space.lg)
        } else if let message = state.paginationError {
            VStack(spacing: JellytoneTheme.Space.sm) {
                Text("Couldn’t load more tracks")
                    .font(.jtSubsectionHeader)
                    .foregroundStyle(Color.jtTextPrimary)
                Text(message)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry More Tracks") {
                    Task { await model.loadMoreTrackCatalog() }
                }
                .buttonStyle(.jtCapsule(.secondaryFlat))
                .accessibilityIdentifier("track-catalog-retry-more")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, JellytoneTheme.Space.lg)
        }
    }

    private func catalogStateCard(
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
        if let album = track.albumDestination {
            NavigationLink("Go to Album") {
                AlbumView(album: album)
            }
        }
        if let artist = track.artistDestination {
            NavigationLink("Go to Artist") {
                ArtistView(artist: artist)
            }
        }
    }

    private func trackLabel(_ track: Track, position: Int, total: Int) -> String {
        var parts = [track.name]
        if !track.artist.isEmpty { parts.append("by \(track.artist)") }
        if !track.album.isEmpty { parts.append("album \(track.album)") }
        return "\(parts.joined(separator: ", ")). Track \(position) of \(total)"
    }
}

private enum CatalogMetrics {
    static let artworkSide: CGFloat = 48
}

private struct CatalogTrackRow: View {
    let track: Track
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            JellytoneTrackArtwork(track: track)
                .frame(width: CatalogMetrics.artworkSide, height: CatalogMetrics.artworkSide)
                .clipShape(
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.rowArtwork, style: .continuous)
                )
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
        if !track.artist.isEmpty { parts.append(track.artist) }
        if !track.album.isEmpty { parts.append(track.album) }
        return parts.joined(separator: " · ")
    }
}
