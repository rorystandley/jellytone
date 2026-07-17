import Foundation

struct FavouritesFeatureScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
    let libraryID: String?
}

@MainActor
final class FavouritesState: ObservableObject {
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var trackOccurrences: [FavouriteTrackOccurrence] = []
    @Published private(set) var isLoadingArtists = false
    @Published private(set) var isLoadingAlbums = false
    @Published private(set) var isLoadingTracks = false
    @Published private(set) var isLoadingMoreArtists = false
    @Published private(set) var isLoadingMoreAlbums = false
    @Published private(set) var isLoadingMoreTracks = false
    @Published private(set) var hasLoadedArtists = false
    @Published private(set) var hasLoadedAlbums = false
    @Published private(set) var hasLoadedTracks = false
    @Published private(set) var artistErrorMessage: String?
    @Published private(set) var albumErrorMessage: String?
    @Published private(set) var trackErrorMessage: String?
    @Published private(set) var artistPaginationError: String?
    @Published private(set) var albumPaginationError: String?
    @Published private(set) var trackPaginationError: String?

    private var scope: FavouritesFeatureScope?
    private var generation = 0
    private var artistsHaveMore = false
    private var albumsHaveMore = false
    private var tracksHaveMore = false
    private var artistsNextStartIndex = 0
    private var albumsNextStartIndex = 0
    private var tracksNextStartIndex = 0

    var canLoadMoreArtists: Bool { artistsHaveMore && !isLoadingArtists && !isLoadingMoreArtists }
    var canLoadMoreAlbums: Bool { albumsHaveMore && !isLoadingAlbums && !isLoadingMoreAlbums }
    var canLoadMoreTracks: Bool { tracksHaveMore && !isLoadingTracks && !isLoadingMoreTracks }
    var hasLoaded: Bool { hasLoadedArtists && hasLoadedAlbums && hasLoadedTracks }

    func load(
        scope requestedScope: FavouritesFeatureScope,
        loadArtists: @escaping (Int) async throws -> FavouriteArtistPage,
        loadAlbums: @escaping (Int) async throws -> FavouriteAlbumPage,
        loadTracks: @escaping (Int) async throws -> FavouriteTrackPage
    ) async {
        beginReplacement(scope: requestedScope, clearingSnapshots: true)
        await replaceAll(
            scope: requestedScope,
            generation: generation,
            loadArtists: loadArtists,
            loadAlbums: loadAlbums,
            loadTracks: loadTracks
        )
    }

    func refresh(
        scope requestedScope: FavouritesFeatureScope,
        loadArtists: @escaping (Int) async throws -> FavouriteArtistPage,
        loadAlbums: @escaping (Int) async throws -> FavouriteAlbumPage,
        loadTracks: @escaping (Int) async throws -> FavouriteTrackPage
    ) async {
        beginReplacement(scope: requestedScope, clearingSnapshots: false)
        await replaceAll(
            scope: requestedScope,
            generation: generation,
            loadArtists: loadArtists,
            loadAlbums: loadAlbums,
            loadTracks: loadTracks
        )
    }

    func loadMoreArtists(
        scope requestedScope: FavouritesFeatureScope,
        loadPage: (Int) async throws -> FavouriteArtistPage
    ) async {
        guard owns(generation, requestedScope), canLoadMoreArtists else { return }
        let requestGeneration = generation
        let startIndex = artistsNextStartIndex
        isLoadingMoreArtists = true
        artistPaginationError = nil
        defer { if owns(requestGeneration, requestedScope) { isLoadingMoreArtists = false } }
        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            artists = Self.uniqueArtists(artists + page.artists)
            artistsHaveMore = page.hasMore
            artistsNextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A newer scope or replacement owns this section now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            artistPaginationError = error.localizedDescription
        }
    }

    func loadMoreAlbums(
        scope requestedScope: FavouritesFeatureScope,
        loadPage: (Int) async throws -> FavouriteAlbumPage
    ) async {
        guard owns(generation, requestedScope), canLoadMoreAlbums else { return }
        let requestGeneration = generation
        let startIndex = albumsNextStartIndex
        isLoadingMoreAlbums = true
        albumPaginationError = nil
        defer { if owns(requestGeneration, requestedScope) { isLoadingMoreAlbums = false } }
        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            albums = Self.uniqueAlbums(albums + page.albums)
            albumsHaveMore = page.hasMore
            albumsNextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A newer scope or replacement owns this section now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            albumPaginationError = error.localizedDescription
        }
    }

    func loadMoreTracks(
        scope requestedScope: FavouritesFeatureScope,
        loadPage: (Int) async throws -> FavouriteTrackPage
    ) async {
        guard owns(generation, requestedScope), canLoadMoreTracks else { return }
        let requestGeneration = generation
        let startIndex = tracksNextStartIndex
        isLoadingMoreTracks = true
        trackPaginationError = nil
        defer { if owns(requestGeneration, requestedScope) { isLoadingMoreTracks = false } }
        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            // Favourites are a displayed occurrence list. Repeated track IDs stay distinct.
            trackOccurrences.append(contentsOf: page.occurrences)
            tracksHaveMore = page.hasMore
            tracksNextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A newer scope or replacement owns this section now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            trackPaginationError = error.localizedDescription
        }
    }

    private func beginReplacement(scope requestedScope: FavouritesFeatureScope, clearingSnapshots: Bool) {
        generation += 1
        scope = requestedScope
        isLoadingMoreArtists = false
        isLoadingMoreAlbums = false
        isLoadingMoreTracks = false
        artistErrorMessage = nil
        albumErrorMessage = nil
        trackErrorMessage = nil
        artistPaginationError = nil
        albumPaginationError = nil
        trackPaginationError = nil
        if clearingSnapshots {
            artists = []
            albums = []
            trackOccurrences = []
            artistsHaveMore = false
            albumsHaveMore = false
            tracksHaveMore = false
            artistsNextStartIndex = 0
            albumsNextStartIndex = 0
            tracksNextStartIndex = 0
            hasLoadedArtists = false
            hasLoadedAlbums = false
            hasLoadedTracks = false
        }
        isLoadingArtists = true
        isLoadingAlbums = true
        isLoadingTracks = true
    }

    private func replaceAll(
        scope requestedScope: FavouritesFeatureScope,
        generation requestGeneration: Int,
        loadArtists: @escaping (Int) async throws -> FavouriteArtistPage,
        loadAlbums: @escaping (Int) async throws -> FavouriteAlbumPage,
        loadTracks: @escaping (Int) async throws -> FavouriteTrackPage
    ) async {
        // These tasks stay MainActor-isolated because their injected loaders often
        // capture the app coordinator. Each loader still suspends independently,
        // so a slow/failing section cannot block the other sections from starting.
        let artistsTask = Task { @MainActor in
            await self.replaceArtists(scope: requestedScope, generation: requestGeneration, loadPage: loadArtists)
        }
        let albumsTask = Task { @MainActor in
            await self.replaceAlbums(scope: requestedScope, generation: requestGeneration, loadPage: loadAlbums)
        }
        let tracksTask = Task { @MainActor in
            await self.replaceTracks(scope: requestedScope, generation: requestGeneration, loadPage: loadTracks)
        }
        _ = await (artistsTask.value, albumsTask.value, tracksTask.value)
    }

    private func replaceArtists(
        scope requestedScope: FavouritesFeatureScope,
        generation requestGeneration: Int,
        loadPage: (Int) async throws -> FavouriteArtistPage
    ) async {
        defer { if owns(requestGeneration, requestedScope) { isLoadingArtists = false } }
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            artists = Self.uniqueArtists(page.artists)
            artistsHaveMore = page.hasMore
            artistsNextStartIndex = page.nextStartIndex
            hasLoadedArtists = true
        } catch is CancellationError {
            // Keep the last valid section snapshot.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            artistErrorMessage = error.localizedDescription
            hasLoadedArtists = true
        }
    }

    private func replaceAlbums(
        scope requestedScope: FavouritesFeatureScope,
        generation requestGeneration: Int,
        loadPage: (Int) async throws -> FavouriteAlbumPage
    ) async {
        defer { if owns(requestGeneration, requestedScope) { isLoadingAlbums = false } }
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            albums = Self.uniqueAlbums(page.albums)
            albumsHaveMore = page.hasMore
            albumsNextStartIndex = page.nextStartIndex
            hasLoadedAlbums = true
        } catch is CancellationError {
            // Keep the last valid section snapshot.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            albumErrorMessage = error.localizedDescription
            hasLoadedAlbums = true
        }
    }

    private func replaceTracks(
        scope requestedScope: FavouritesFeatureScope,
        generation requestGeneration: Int,
        loadPage: (Int) async throws -> FavouriteTrackPage
    ) async {
        defer { if owns(requestGeneration, requestedScope) { isLoadingTracks = false } }
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            trackOccurrences = page.occurrences
            tracksHaveMore = page.hasMore
            tracksNextStartIndex = page.nextStartIndex
            hasLoadedTracks = true
        } catch is CancellationError {
            // Keep the last valid section snapshot.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            trackErrorMessage = error.localizedDescription
            hasLoadedTracks = true
        }
    }

    private func owns(_ requestGeneration: Int, _ requestedScope: FavouritesFeatureScope) -> Bool {
        generation == requestGeneration && scope == requestedScope
    }

    private static func uniqueArtists(_ values: [Artist]) -> [Artist] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func uniqueAlbums(_ values: [Album]) -> [Album] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}
