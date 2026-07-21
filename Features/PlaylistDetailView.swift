import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = PlaylistDetailState()

    let playlist: Playlist

    var body: some View {
        Group {
            if let message = state.errorMessage, state.entries.isEmpty {
                unavailable(message)
            } else if state.hasLoaded, !state.isLoading, state.entries.isEmpty {
                emptyState
            } else {
                // Covers loaded content AND the cold load — the header always
                // paints immediately; only the rows show skeletons.
                detailList
            }
        }
        .accessibilityIdentifier("playlist-detail-screen")
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(
            JellytoneDetailBackdrop { PlaylistArtwork(playlist: playlist) }
        )
        .task(id: requestIdentity) { await load() }
    }

    private var scope: PlaylistFeatureScope {
        PlaylistFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var requestIdentity: String {
        "\(scope.serverID)|\(scope.accountID)|\(scope.libraryID ?? "")|\(playlist.id)"
    }

    private var detailList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                artworkCard
                identity
                if state.isLoading && state.entries.isEmpty {
                    JellytoneSkeletonRows(label: "Loading playlist")
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.entries.enumerated()), id: \.element.id) { offset, entry in
                        Button { model.play(entry, in: state.entries) } label: {
                            PlaylistEntryRow(entry: entry, isLast: entry.id == state.entries.last?.id,
                                             downloads: model.downloads)
                        }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("playlist-track-\(entry.id)")
                        .accessibilityLabel(trackAccessibilityLabel(entry, position: offset + 1))
                        .accessibilityHint("Starts playback from this playlist occurrence")
                        .contextMenu {
                            let liked = model.isFavourite(entry.track.id)
                            Button(liked ? "Unfavourite" : "Favourite",
                                   systemImage: liked ? "heart.slash" : "heart") {
                                model.toggleFavourite(id: entry.track.id)
                            }
                            if model.downloads.isDownloaded(entry.track.id) {
                                Button("Remove Download", systemImage: "trash") {
                                    Task { await model.downloads.remove(entry.track.id) }
                                }
                            } else {
                                Button("Download", systemImage: "arrow.down.circle") {
                                    model.downloads.download([entry.track], container: playlistContainer)
                                }
                            }
                        }
                        .task {
                            if entry.id == state.entries.last?.id { await loadMore() }
                        }
                    }
                }
                if state.isLoadingMore || state.paginationError != nil || state.errorMessage != nil {
                    paginationStatus
                }
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.lg)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        // Background refreshes stay silent (Apple Music-style); the system
        // pull spinner is the only indicator.
        .refreshable { await refresh() }
    }

    private var artworkCard: some View {
        PlaylistArtwork(playlist: playlist)
            .frame(width: DetailMetrics.artworkSide, height: DetailMetrics.artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.largeArtwork, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
            Text(playlist.name)
                .font(.jtDetailTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(metaLine)
                .font(.jtCaption)
                .foregroundStyle(Color.jtTextTertiary)
            // Secondary bare-glyph actions grouped tightly; the filled play
            // circle sits apart. The tighter inner gap compensates for the
            // glyphs' frame padding so every optical gap reads even.
            HStack(spacing: JellytoneTheme.Space.xl) {
                Spacer()
                // Liking the playlist itself is independent of whether its
                // tracks have loaded, so the heart never dims.
                FavouriteHeartButton(itemID: playlist.id, identifierPrefix: "playlist")
                HStack(spacing: JellytoneTheme.Space.xl) {
                    HStack(spacing: JellytoneTheme.Space.md) {
                        DownloadStatusButton(
                            downloads: model.downloads,
                            tracks: state.entries.map(\.track),
                            container: playlistContainer,
                            identifierPrefix: "playlist"
                        )
                        Button { model.shuffle(state.entries) } label: {
                            Image(systemName: "shuffle")
                                .font(.jtSubsectionHeader)
                                .foregroundStyle(Color.jtTextPrimary)
                                .frame(width: DetailMetrics.secondaryActionSide, height: DetailMetrics.secondaryActionSide)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                        .accessibilityIdentifier("playlist-shuffle")
                        .accessibilityLabel("Shuffle")
                    }
                    Button { model.playAll(state.entries) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: DetailMetrics.playDiameter / 3, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: DetailMetrics.playDiameter, height: DetailMetrics.playDiameter)
                            .background(Circle().fill(Color.jtAccent))
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                    .accessibilityIdentifier("playlist-play-all")
                    .accessibilityLabel("Play All")
                }
                .disabled(state.entries.isEmpty)
                .opacity(state.entries.isEmpty ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playlistContainer: DownloadContainer {
        DownloadContainer(kind: .playlist, id: playlist.id, name: playlist.name)
    }

    private var metaLine: String {
        if state.isLoading && state.entries.isEmpty { return "Loading…" }
        let count = state.entries.count
        var parts = [count == 1 ? "1 playable track" : "\(count) playable tracks"]
        let totalSeconds = Int(state.entries.reduce(0) { $0 + $1.track.duration }.rounded())
        if totalSeconds > 0 {
            parts.append(DetailMetrics.durationLabel(totalSeconds: totalSeconds))
        }
        return parts.joined(separator: " · ")
    }

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
        (playlist.itemCount ?? 0) > 0 ? "No playable audio" : "Empty playlist"
    }

    private var emptyDescription: String {
        if (playlist.itemCount ?? 0) > 0 {
            return "This playlist contains items, but Jellyfin returned no playable audio tracks."
        }
        return "This playlist does not contain any tracks."
    }

    @ViewBuilder
    private var paginationStatus: some View {
        HStack {
            Spacer()
            if state.isLoadingMore {
                ProgressView("Loading more tracks…")
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
            } else if let message = state.paginationError ?? state.errorMessage {
                VStack(spacing: JellytoneTheme.Space.sm) {
                    Text(message)
                        .font(.jtRowSubtitle)
                        .foregroundStyle(Color.jtTextSecondary)
                    Button(state.paginationError == nil ? "Retry Refresh" : "Retry More Tracks") {
                        Task {
                            if state.paginationError == nil { await refresh() } else { await loadMore() }
                        }
                    }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
                }
            }
            Spacer()
        }
    }

    private func unavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
            detailStateCard(title: "Playlist unavailable", detail: message)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.jtCapsule(.primaryFlat))
        }
        .padding(JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func trackAccessibilityLabel(_ entry: PlaylistEntry, position: Int) -> String {
        let identity = "Track \(position), \(entry.track.name), by \(entry.track.artist)"
        guard entry.track.durationTicks != nil else { return "\(identity), duration unavailable" }
        return "\(identity), \(entry.track.durationLabel)"
    }

    private func load() async {
        let requestScope = scope
        let cached = await model.cachedPlaylistEntries(for: playlist)
        await state.load(
            playlist: playlist,
            scope: requestScope,
            cached: (cached?.isEmpty == false) ? cached : nil
        ) { startIndex in
            try await model.playlistEntries(for: playlist, startIndex: startIndex)
        }
        await persistSnapshot()
        await model.refreshFavouriteStatus(ids: [playlist.id] + state.entries.map(\.track.id))
    }

    private func refresh() async {
        let requestScope = scope
        await state.refresh(playlist: playlist, scope: requestScope) { startIndex in
            try await model.playlistEntries(for: playlist, startIndex: startIndex)
        }
        await persistSnapshot()
    }

    private func loadMore() async {
        let requestScope = scope
        await state.loadMore(playlist: playlist, scope: requestScope) { startIndex in
            try await model.playlistEntries(for: playlist, startIndex: startIndex)
        }
        await persistSnapshot()
    }

    /// Persists the accumulated snapshot (including partial pagination) so the
    /// next visit paints instantly; failed loads never overwrite the cache.
    private func persistSnapshot() async {
        guard state.hasLoaded, state.errorMessage == nil else { return }
        await model.storePlaylistEntries(state.entries, for: playlist)
    }
}

private struct PlaylistEntryRow: View {
    let entry: PlaylistEntry
    let isLast: Bool
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            JellytoneTrackArtwork(track: entry.track)
                .frame(width: DetailMetrics.rowArtworkSide, height: DetailMetrics.rowArtworkSide)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.smallArtwork, style: .continuous))
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(entry.track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(entry.track.artist)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: JellytoneTheme.Space.sm)
            TrackDownloadIndicator(downloads: downloads, trackID: entry.track.id)
            if entry.track.durationTicks != nil {
                Text(entry.track.durationLabel)
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
