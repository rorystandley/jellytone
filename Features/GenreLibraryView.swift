import SwiftUI

struct GenreLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = GenreLibraryState()

    var body: some View {
        Group {
            if state.isLoading && state.genres.isEmpty {
                AudioStateView(kind: .loading, title: "Loading genres", detail: "Organising your library by sound…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else if let message = state.errorMessage, state.genres.isEmpty {
                unavailable(message)
            } else if state.hasLoaded && state.genres.isEmpty {
                AudioStateView(kind: .empty, title: "No genres found",
                               detail: "This music library has no genres available in Jellyfin.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                genreGrid
            }
        }
        .accessibilityIdentifier("genres-screen")
        .navigationTitle("Genres")
        .audioCanvas()
        .task(id: scope) {
            // Cache-first: paint the persisted snapshot, then refresh silently.
            state.seed(await model.cachedGenres(), scope: scope)
            if state.genres.isEmpty { await load() } else { await refresh() }
        }
    }

    private var scope: GenreFeatureScope {
        GenreFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var genreGrid: some View {
        AudioBrowseContainer(spacing: AudioDesign.Space.lg) {
            AudioSectionHeading(title: "Explore Genres", detail: "Browse the library without invented cover art")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(state.genres) { genre in
                    NavigationLink(value: genre) {
                        GenreCard(genre: genre)
                    }
                    .accessibilityIdentifier("genre-row-\(genre.id)")
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .task {
                        if genre.id == state.genres.last?.id { await loadMore() }
                    }
                }
            }
            paginationStatus
        }
        .refreshable { await refresh() }
        .overlay(alignment: .top) {
            if state.isLoading && !state.genres.isEmpty {
                ProgressView("Refreshing genres…")
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var columns: [GridItem] {
        let minimum: CGFloat = horizontalSizeClass == .regular ? 210 : 145
        return [GridItem(.adaptive(minimum: minimum, maximum: 280), spacing: 16)]
    }

    @ViewBuilder
    private var paginationStatus: some View {
        if state.isLoadingMore {
            ProgressView("Loading more genres…")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("genre-load-more")
        } else if let message = state.paginationError {
            VStack(spacing: 8) {
                Text("Couldn’t load more genres").font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry loading more genres") { Task { await loadMore() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("genre-load-more")
            }
            .frame(maxWidth: .infinity)
        } else if let message = state.errorMessage {
            VStack(spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry Refresh") { Task { await refresh() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func unavailable(_ message: String) -> some View {
        AudioStateView(kind: .error, title: "Couldn’t load genres", detail: message,
                       actionTitle: "Try Again") { Task { await load() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func load() async {
        let requestScope = scope
        await state.load(scope: requestScope) { startIndex in
            try await model.genrePage(startIndex: startIndex)
        }
    }

    private func refresh() async {
        let requestScope = scope
        await state.refresh(scope: requestScope) { startIndex in
            try await model.genrePage(startIndex: startIndex)
        }
    }

    private func loadMore() async {
        let requestScope = scope
        await state.loadMore(scope: requestScope) { startIndex in
            try await model.genrePage(startIndex: startIndex)
        }
    }
}

private struct GenreCard: View {
    let genre: Genre

    var body: some View {
        VStack(alignment: .leading, spacing: AudioDesign.Space.md) {
            HStack {
                Image(systemName: "guitars")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AudioDesign.accent)
                    .frame(width: 52, height: 52)
                    .background(AudioDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AudioDesign.Radius.compact))
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
            }
            Text(genre.name).font(.title3.bold()).lineLimit(2)
            if let summary { Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(AudioDesign.Space.md)
        .audioElevatedSurface(cornerRadius: AudioDesign.Radius.compact)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens genre")
    }

    private var summary: String? {
        if let albumCount = genre.albumCount {
            return albumCount == 1 ? "1 album" : "\(albumCount) albums"
        }
        if let itemCount = genre.itemCount {
            return itemCount == 1 ? "1 track" : "\(itemCount) tracks"
        }
        return nil
    }

    private var accessibilityLabel: String {
        guard let summary else { return genre.name }
        return "\(genre.name), \(summary)"
    }
}

struct GenreArtwork: View {
    let genre: Genre

    var body: some View {
        if genre.imageTag != nil {
            AuthenticatedArtworkView(
                itemID: genre.id,
                accessibilityLabel: "Artwork for \(genre.name)"
            )
        } else {
            AudioMissingArtwork(label: genre.name, systemImage: "guitars")
        }
    }
}
