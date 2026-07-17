import SwiftUI

@MainActor
final class MusicSearchController: ObservableObject {
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?

    private(set) var query = ""
    private var generation = 0
    private var hasMore = false
    private var nextStartIndex = 0

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty }
    var canLoadMore: Bool { hasMore && !isLoadingMore }

    func search(
        query rawQuery: String,
        debounceNanoseconds: UInt64 = 350_000_000,
        load: (String, Int) async throws -> MusicSearchPage
    ) async {
        generation += 1
        let requestGeneration = generation
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryChanged = normalized != query
        query = normalized
        errorMessage = nil
        paginationError = nil
        if queryChanged {
            artists = []
            albums = []
            hasMore = false
            nextStartIndex = 0
        }

        guard !normalized.isEmpty else {
            artists = []
            albums = []
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
            let page = try await load(normalized, 0)
            try Task.checkCancellation()
            guard requestGeneration == generation, normalized == query else { return }
            artists = page.artists
            albums = page.albums
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            Diagnostics.event("music_search_loaded", [
                "album_count": page.albums.count,
                "artist_count": page.artists.count,
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
            errorMessage = error.localizedDescription
        }
        if requestGeneration == generation { isLoading = false }
    }

    func loadMore(load: (String, Int) async throws -> MusicSearchPage) async {
        guard canLoadMore, !query.isEmpty else { return }
        let requestGeneration = generation
        let startIndex = nextStartIndex
        isLoadingMore = true
        paginationError = nil
        defer {
            if requestGeneration == generation { isLoadingMore = false }
        }
        do {
            let page = try await load(query, startIndex)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            let artistIDs = Set(artists.map(\.id))
            let albumIDs = Set(albums.map(\.id))
            artists.append(contentsOf: page.artists.filter { !artistIDs.contains($0.id) })
            albums.append(contentsOf: page.albums.filter { !albumIDs.contains($0.id) })
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
}

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = MusicSearchController()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .navigationDestination(for: Album.self) { AlbumView(album: $0) }
                .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
                .searchable(text: $query, prompt: "Artists and albums")
                .task(id: query) {
                    await search.search(query: query) { value, startIndex in
                        try await model.searchMusic(query: value, startIndex: startIndex)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if search.query.isEmpty {
            ContentUnavailableView(
                "Search your music",
                systemImage: "magnifyingglass",
                description: Text("Find artists and albums across your selected Jellyfin music library.")
            )
        } else if search.isLoading && search.isEmpty {
            ProgressView("Searching music…")
        } else if let message = search.errorMessage, search.isEmpty {
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await retrySearch() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if search.isEmpty {
            ContentUnavailableView.search(text: search.query)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            if !search.artists.isEmpty {
                Section("Artists") {
                    ForEach(search.artists) { artist in
                        NavigationLink(value: artist) {
                            HStack(spacing: 12) {
                                AuthenticatedArtworkView(
                                    itemID: artist.id,
                                    accessibilityLabel: "Artwork for \(artist.name)"
                                )
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                Text(artist.name).font(.headline).lineLimit(2)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            if !search.albums.isEmpty {
                Section("Albums") {
                    ForEach(search.albums) { album in
                        NavigationLink(value: album) {
                            HStack(spacing: 12) {
                                AuthenticatedArtworkView(
                                    itemID: album.id,
                                    accessibilityLabel: "Artwork for \(album.name)"
                                )
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(album.name).font(.headline).lineLimit(2)
                                    Text(album.artist).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            if search.canLoadMore || search.isLoadingMore || search.paginationError != nil {
                Section {
                    HStack {
                        Spacer()
                        if search.isLoadingMore {
                            ProgressView("Loading more…")
                        } else if search.paginationError != nil {
                            Button("Retry More Results") { Task { await loadMore() } }
                        } else {
                            ProgressView().task { await loadMore() }
                        }
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .top) {
            if search.isLoading && !search.isEmpty { ProgressView().padding(.top, 8) }
        }
    }

    private func retrySearch() async {
        await search.search(query: query, debounceNanoseconds: 0) { value, startIndex in
            try await model.searchMusic(query: value, startIndex: startIndex)
        }
    }

    private func loadMore() async {
        await search.loadMore { value, startIndex in
            try await model.searchMusic(query: value, startIndex: startIndex)
        }
    }
}
