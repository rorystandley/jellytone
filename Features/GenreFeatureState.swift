import Foundation

struct GenreFeatureScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
    let libraryID: String?
}

@MainActor
final class GenreLibraryState: ObservableObject {
    @Published private(set) var genres: [Genre] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?

    private var scope: GenreFeatureScope?
    private var generation = 0
    private var hasMore = false
    private var nextStartIndex = 0

    var canLoadMore: Bool { hasMore && !isLoading && !isLoadingMore }

    func load(
        scope requestedScope: GenreFeatureScope,
        loadPage: (Int) async throws -> GenrePage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        genres = []
        hasMore = false
        nextStartIndex = 0
        hasLoaded = false
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil

        await replacePage(
            requestedScope: requestedScope,
            requestGeneration: requestGeneration,
            loadPage: loadPage
        )
    }

    func refresh(
        scope requestedScope: GenreFeatureScope,
        loadPage: (Int) async throws -> GenrePage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil

        await replacePage(
            requestedScope: requestedScope,
            requestGeneration: requestGeneration,
            loadPage: loadPage
        )
    }

    func loadMore(
        scope requestedScope: GenreFeatureScope,
        loadPage: (Int) async throws -> GenrePage
    ) async {
        guard scope == requestedScope, canLoadMore else { return }
        let requestGeneration = generation
        let startIndex = nextStartIndex
        isLoadingMore = true
        paginationError = nil
        defer {
            if owns(requestGeneration, requestedScope) { isLoadingMore = false }
        }

        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            genres = Self.uniqueByIdentity(genres + page.genres)
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A newer load owns the screen now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            paginationError = error.localizedDescription
        }
    }

    private func replacePage(
        requestedScope: GenreFeatureScope,
        requestGeneration: Int,
        loadPage: (Int) async throws -> GenrePage
    ) async {
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            genres = Self.uniqueByIdentity(page.genres)
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            hasLoaded = true
        } catch is CancellationError {
            // Replacement, scope changes, and navigation cancellation are expected.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
        if owns(requestGeneration, requestedScope) { isLoading = false }
    }

    private func owns(_ requestGeneration: Int, _ requestedScope: GenreFeatureScope) -> Bool {
        generation == requestGeneration && scope == requestedScope
    }

    private static func uniqueByIdentity(_ values: [Genre]) -> [Genre] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
final class GenreDetailState: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var trackOccurrences: [GenreTrackOccurrence] = []
    @Published private(set) var isLoadingAlbums = false
    @Published private(set) var isLoadingTracks = false
    @Published private(set) var isLoadingMoreAlbums = false
    @Published private(set) var isLoadingMoreTracks = false
    @Published private(set) var hasLoadedAlbums = false
    @Published private(set) var hasLoadedTracks = false
    @Published private(set) var albumErrorMessage: String?
    @Published private(set) var trackErrorMessage: String?
    @Published private(set) var albumPaginationError: String?
    @Published private(set) var trackPaginationError: String?

    private var scope: GenreFeatureScope?
    private var genreID: String?
    private var generation = 0
    private var albumsHaveMore = false
    private var albumsNextStartIndex = 0
    private var tracksHaveMore = false
    private var tracksNextStartIndex = 0

    var isLoading: Bool { isLoadingAlbums || isLoadingTracks }
    var hasLoaded: Bool { hasLoadedAlbums && hasLoadedTracks }
    var canLoadMoreAlbums: Bool { albumsHaveMore && !isLoadingAlbums && !isLoadingMoreAlbums }
    var canLoadMoreTracks: Bool { tracksHaveMore && !isLoadingTracks && !isLoadingMoreTracks }

    func load(
        genre: Genre,
        scope requestedScope: GenreFeatureScope,
        loadAlbums: (Int) async throws -> AlbumPage,
        loadTracks: (Int) async throws -> GenreTrackPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        genreID = genre.id
        albums = []
        trackOccurrences = []
        resetPagination()
        hasLoadedAlbums = false
        hasLoadedTracks = false
        clearErrors()
        isLoadingAlbums = true
        isLoadingTracks = true

        await replaceAlbums(
            genre: genre,
            scope: requestedScope,
            generation: requestGeneration,
            loadPage: loadAlbums
        )
        guard !Task.isCancelled, owns(requestGeneration, requestedScope, genre.id) else {
            if owns(requestGeneration, requestedScope, genre.id) { isLoadingTracks = false }
            return
        }
        await replaceTracks(
            genre: genre,
            scope: requestedScope,
            generation: requestGeneration,
            loadPage: loadTracks
        )
    }

    func refresh(
        genre: Genre,
        scope requestedScope: GenreFeatureScope,
        loadAlbums: (Int) async throws -> AlbumPage,
        loadTracks: (Int) async throws -> GenreTrackPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        genreID = genre.id
        clearErrors()
        isLoadingMoreAlbums = false
        isLoadingMoreTracks = false
        isLoadingAlbums = true
        isLoadingTracks = true

        await replaceAlbums(
            genre: genre,
            scope: requestedScope,
            generation: requestGeneration,
            loadPage: loadAlbums
        )
        guard !Task.isCancelled, owns(requestGeneration, requestedScope, genre.id) else {
            if owns(requestGeneration, requestedScope, genre.id) { isLoadingTracks = false }
            return
        }
        await replaceTracks(
            genre: genre,
            scope: requestedScope,
            generation: requestGeneration,
            loadPage: loadTracks
        )
    }

    func loadMoreAlbums(
        genre: Genre,
        scope requestedScope: GenreFeatureScope,
        loadPage: (Int) async throws -> AlbumPage
    ) async {
        guard owns(generation, requestedScope, genre.id), canLoadMoreAlbums else { return }
        let requestGeneration = generation
        let startIndex = albumsNextStartIndex
        isLoadingMoreAlbums = true
        albumPaginationError = nil
        defer {
            if owns(requestGeneration, requestedScope, genre.id) { isLoadingMoreAlbums = false }
        }

        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, genre.id) else { return }
            albums = Self.uniqueAlbums(albums + page.albums)
            albumsHaveMore = page.hasMore
            albumsNextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A newer detail request owns the screen now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, genre.id) else { return }
            albumPaginationError = error.localizedDescription
        }
    }

    func loadMoreTracks(
        genre: Genre,
        scope requestedScope: GenreFeatureScope,
        loadPage: (Int) async throws -> GenreTrackPage
    ) async {
        guard owns(generation, requestedScope, genre.id), canLoadMoreTracks else { return }
        let requestGeneration = generation
        let startIndex = tracksNextStartIndex
        isLoadingMoreTracks = true
        trackPaginationError = nil
        defer {
            if owns(requestGeneration, requestedScope, genre.id) { isLoadingMoreTracks = false }
        }

        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, genre.id) else { return }
            // Occurrences are the server's ordered queue. Never collapse repeated tracks or occurrences.
            trackOccurrences.append(contentsOf: page.occurrences)
            tracksHaveMore = page.hasMore
            tracksNextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A newer detail request owns the screen now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, genre.id) else { return }
            trackPaginationError = error.localizedDescription
        }
    }

    private func replaceAlbums(
        genre: Genre,
        scope requestedScope: GenreFeatureScope,
        generation requestGeneration: Int,
        loadPage: (Int) async throws -> AlbumPage
    ) async {
        defer {
            if owns(requestGeneration, requestedScope, genre.id) { isLoadingAlbums = false }
        }
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, genre.id) else { return }
            albums = Self.uniqueAlbums(page.albums)
            albumsHaveMore = page.hasMore
            albumsNextStartIndex = page.nextStartIndex
            hasLoadedAlbums = true
        } catch is CancellationError {
            // Preserve the last complete album snapshot.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, genre.id) else { return }
            albumErrorMessage = error.localizedDescription
            hasLoadedAlbums = true
        }
    }

    private func replaceTracks(
        genre: Genre,
        scope requestedScope: GenreFeatureScope,
        generation requestGeneration: Int,
        loadPage: (Int) async throws -> GenreTrackPage
    ) async {
        defer {
            if owns(requestGeneration, requestedScope, genre.id) { isLoadingTracks = false }
        }
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, genre.id) else { return }
            trackOccurrences = page.occurrences
            tracksHaveMore = page.hasMore
            tracksNextStartIndex = page.nextStartIndex
            hasLoadedTracks = true
        } catch is CancellationError {
            // Preserve the last complete track snapshot.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, genre.id) else { return }
            trackErrorMessage = error.localizedDescription
            hasLoadedTracks = true
        }
    }

    private func resetPagination() {
        albumsHaveMore = false
        albumsNextStartIndex = 0
        tracksHaveMore = false
        tracksNextStartIndex = 0
    }

    private func clearErrors() {
        albumErrorMessage = nil
        trackErrorMessage = nil
        albumPaginationError = nil
        trackPaginationError = nil
    }

    private func owns(
        _ requestGeneration: Int,
        _ requestedScope: GenreFeatureScope,
        _ requestedGenreID: String
    ) -> Bool {
        generation == requestGeneration && scope == requestedScope && genreID == requestedGenreID
    }

    private static func uniqueAlbums(_ values: [Album]) -> [Album] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}
