import Foundation

struct PlaylistFeatureScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
    let libraryID: String?
}

@MainActor
final class PlaylistLibraryState: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?

    private var scope: PlaylistFeatureScope?
    private var generation = 0
    private var hasMore = false
    private var nextStartIndex = 0

    var canLoadMore: Bool { hasMore && !isLoading && !isLoadingMore }

    func load(
        scope requestedScope: PlaylistFeatureScope,
        loadPage: (Int) async throws -> PlaylistPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        playlists = []
        hasMore = false
        nextStartIndex = 0
        hasLoaded = false
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil

        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            playlists = Self.uniquePlaylists(page.playlists)
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

    func refresh(
        scope requestedScope: PlaylistFeatureScope,
        loadPage: (Int) async throws -> PlaylistPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil

        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            playlists = Self.uniquePlaylists(page.playlists)
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            hasLoaded = true
        } catch is CancellationError {
            // Keep the last complete snapshot when refresh is cancelled.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
        if owns(requestGeneration, requestedScope) { isLoading = false }
    }

    func loadMore(
        scope requestedScope: PlaylistFeatureScope,
        loadPage: (Int) async throws -> PlaylistPage
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
            playlists = Self.uniquePlaylists(playlists + page.playlists)
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A replacement load owns the screen now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope) else { return }
            paginationError = error.localizedDescription
        }
    }

    private func owns(_ requestGeneration: Int, _ requestedScope: PlaylistFeatureScope) -> Bool {
        generation == requestGeneration && scope == requestedScope
    }

    private static func uniquePlaylists(_ values: [Playlist]) -> [Playlist] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
final class PlaylistDetailState: ObservableObject {
    @Published private(set) var entries: [PlaylistEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?

    private var scope: PlaylistFeatureScope?
    private var playlistID: String?
    private var generation = 0
    private var hasMore = false
    private var nextStartIndex = 0

    var canLoadMore: Bool { hasMore && !isLoading && !isLoadingMore }

    func load(
        playlist: Playlist,
        scope requestedScope: PlaylistFeatureScope,
        cached: [PlaylistEntry]? = nil,
        loadPage: (Int) async throws -> PlaylistEntryPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        playlistID = playlist.id
        // Present the persisted snapshot immediately; the network result
        // replaces it below so the refresh stays silent.
        entries = cached ?? []
        hasMore = false
        nextStartIndex = 0
        hasLoaded = false
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil

        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, playlist.id) else { return }
            entries = page.entries
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            hasLoaded = true
        } catch is CancellationError {
            // Replacement, scope changes, and navigation cancellation are expected.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, playlist.id) else { return }
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
        if owns(requestGeneration, requestedScope, playlist.id) { isLoading = false }
    }

    func refresh(
        playlist: Playlist,
        scope requestedScope: PlaylistFeatureScope,
        loadPage: (Int) async throws -> PlaylistEntryPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        playlistID = playlist.id
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil

        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, playlist.id) else { return }
            entries = page.entries
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            hasLoaded = true
        } catch is CancellationError {
            // Keep the last complete snapshot when refresh is cancelled.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, playlist.id) else { return }
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
        if owns(requestGeneration, requestedScope, playlist.id) { isLoading = false }
    }

    func loadMore(
        playlist: Playlist,
        scope requestedScope: PlaylistFeatureScope,
        loadPage: (Int) async throws -> PlaylistEntryPage
    ) async {
        guard scope == requestedScope, playlistID == playlist.id, canLoadMore else { return }
        let requestGeneration = generation
        let startIndex = nextStartIndex
        isLoadingMore = true
        paginationError = nil
        defer {
            if owns(requestGeneration, requestedScope, playlist.id) { isLoadingMore = false }
        }

        do {
            let page = try await loadPage(startIndex)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope, playlist.id) else { return }
            // Occurrence identity and server order are authoritative. Do not collapse duplicate tracks.
            entries.append(contentsOf: page.entries)
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
        } catch is CancellationError {
            // A replacement load owns the screen now.
        } catch {
            guard !Task.isCancelled, owns(requestGeneration, requestedScope, playlist.id) else { return }
            paginationError = error.localizedDescription
        }
    }

    private func owns(
        _ requestGeneration: Int,
        _ requestedScope: PlaylistFeatureScope,
        _ requestedPlaylistID: String
    ) -> Bool {
        generation == requestGeneration && scope == requestedScope && playlistID == requestedPlaylistID
    }
}
