import SwiftUI

struct GenreDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = GenreDetailState()

    let genre: Genre

    var body: some View {
        Group {
            if state.isLoading && state.albums.isEmpty && state.trackOccurrences.isEmpty {
                ProgressView("Loading genre…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = initialError, state.albums.isEmpty, state.trackOccurrences.isEmpty {
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
        List {
            Section { header.padding(.vertical, 8) }
                .listRowSeparator(.hidden)

            albumSection
            trackSection
        }
        .listStyle(.insetGrouped)
        .refreshable { await refresh() }
        .overlay(alignment: .top) {
            if state.isLoading && (!state.albums.isEmpty || !state.trackOccurrences.isEmpty) {
                ProgressView("Refreshing genre…")
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var albumSection: some View {
        Section {
            if state.isLoadingAlbums && state.albums.isEmpty {
                centeredProgress("Loading albums…")
            } else if let message = state.albumErrorMessage, state.albums.isEmpty {
                retryStatus(message, title: "Retry Albums") { await refresh() }
            } else if state.hasLoadedAlbums && state.albums.isEmpty {
                Text("No albums found for this genre.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(state.albums) { album in
                            NavigationLink(value: album) {
                                GenreAlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .task {
                                if album.id == state.albums.last?.id { await loadMoreAlbums() }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)

                if state.isLoadingMoreAlbums {
                    centeredProgress("Loading more albums…")
                        .accessibilityIdentifier("genre-load-more")
                } else if let message = state.albumPaginationError {
                    retryStatus(message, title: "Retry More Albums", identifier: "genre-retry-more-albums") {
                        await loadMoreAlbums()
                    }
                }
            }
        } header: {
            Text("Albums")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var trackSection: some View {
        Section {
            if state.isLoadingTracks && state.trackOccurrences.isEmpty {
                centeredProgress("Loading tracks…")
            } else if let message = state.trackErrorMessage, state.trackOccurrences.isEmpty {
                retryStatus(message, title: "Retry Tracks") { await refresh() }
            } else if state.hasLoadedTracks && state.trackOccurrences.isEmpty {
                Text("No playable tracks found for this genre.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(state.trackOccurrences.enumerated()), id: \.offset) { offset, occurrence in
                    Button { model.play(occurrence, in: state.trackOccurrences) } label: {
                        GenreTrackRow(position: offset + 1, occurrence: occurrence)
                    }
                    .accessibilityIdentifier("genre-track-\(occurrence.id)")
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel(trackAccessibilityLabel(occurrence, position: offset + 1))
                    .accessibilityHint("Starts playback from this genre occurrence")
                    .task {
                        if offset == state.trackOccurrences.indices.last { await loadMoreTracks() }
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
        } header: {
            Text("Tracks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                artwork.frame(width: horizontalSizeClass == .regular ? 180 : 132,
                              height: horizontalSizeClass == .regular ? 180 : 132)
                identityAndActions
                Spacer(minLength: 0)
            }
            VStack(spacing: 16) {
                artwork.frame(width: 180, height: 180)
                identityAndActions
            }
        }
    }

    private var artwork: some View {
        GenreArtwork(genre: genre)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var identityAndActions: some View {
        VStack(alignment: horizontalSizeClass == .regular ? .leading : .center, spacing: 10) {
            VStack(alignment: horizontalSizeClass == .regular ? .leading : .center, spacing: 4) {
                Text("Genre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(genre.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(horizontalSizeClass == .regular ? .leading : .center)
                Text(trackCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                Button { model.playAll(state.trackOccurrences) } label: {
                    Label("Play All", systemImage: "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.trackOccurrences.isEmpty)
                .accessibilityIdentifier("genre-play-all")
                .keyboardShortcut(.return, modifiers: [.command])

                Button { model.shuffle(state.trackOccurrences) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(state.trackOccurrences.isEmpty)
                .accessibilityIdentifier("genre-shuffle")
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .regular ? .leading : .center)
    }

    private var trackCountLabel: String {
        let count = state.trackOccurrences.count
        return count == 1 ? "1 playable track" : "\(count) playable tracks"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "music.note.slash")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("Refresh") { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
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
        ContentUnavailableView {
            Label("Genre unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
    }

    private func centeredProgress(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
    }

    private func retryStatus(
        _ message: String,
        title: String,
        identifier: String? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Button(title) { Task { await action() } }
                .buttonStyle(.bordered)
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

    private func load() async {
        let requestScope = scope
        await state.load(genre: genre, scope: requestScope) { startIndex in
            try await model.genreAlbums(for: genre, startIndex: startIndex)
        } loadTracks: { startIndex in
            try await model.genreTracks(for: genre, startIndex: startIndex)
        }
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

private struct GenreAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuthenticatedArtworkView(
                itemID: album.id,
                accessibilityLabel: album.imageTag == nil
                    ? "No artwork for \(album.name)"
                    : "Artwork for \(album.name)"
            )
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(album.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(album.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), by \(album.artist)")
        .accessibilityHint("Opens album")
    }
}

private struct GenreTrackRow: View {
    let position: Int
    let occurrence: GenreTrackOccurrence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(position))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.track.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(occurrence.track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if occurrence.track.durationTicks != nil {
                Text(occurrence.track.durationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
