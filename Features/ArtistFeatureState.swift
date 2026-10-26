import Foundation

struct ArtistFeatureScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
    let libraryID: String?
}

@MainActor
final class ArtistLibraryState: ObservableObject {
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paginationError: String?

    private var scope: ArtistFeatureScope?
    private var generation = 0
    private var hasMore = false
    private var nextStartIndex = 0

    var canLoadMore: Bool { hasMore && !isLoading && !isLoadingMore }

    /// Paints a persisted snapshot immediately (cache-first) so the screen
    /// never opens empty when a cache exists; the silent network refresh that
    /// follows replaces it. Ignored once this scope already has content, so a
    /// stale cache read can never clobber live results.
    func seed(_ cached: [Artist], scope requestedScope: ArtistFeatureScope) {
        guard !cached.isEmpty else { return }
        if scope == requestedScope, hasLoaded || !artists.isEmpty { return }
        generation += 1
        scope = requestedScope
        artists = Self.uniqueByIdentity(cached)
        hasMore = false
        nextStartIndex = 0
        hasLoaded = false
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil
    }

    func load(
        scope requestedScope: ArtistFeatureScope,
        loadPage: (Int) async throws -> ArtistPage
    ) async {
        generation += 1
        let requestGeneration = generation
        scope = requestedScope
        artists = []
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
        scope requestedScope: ArtistFeatureScope,
        loadPage: (Int) async throws -> ArtistPage
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

    /// Pages in the rest of the library after the first page has painted, so
    /// the alphabet index can jump anywhere without waiting on scroll-driven
    /// pagination. Stops on scope change, pagination error, or a page that
    /// fails to advance the cursor.
    func loadAllRemaining(
        scope requestedScope: ArtistFeatureScope,
        loadPage: (Int) async throws -> ArtistPage
    ) async {
        while scope == requestedScope, canLoadMore, !Task.isCancelled {
            let cursor = nextStartIndex
            await loadMore(scope: requestedScope, loadPage: loadPage)
            if paginationError != nil { return }
            if hasMore && nextStartIndex == cursor { return }
        }
    }

    func loadMore(
        scope requestedScope: ArtistFeatureScope,
        loadPage: (Int) async throws -> ArtistPage
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
            artists = Self.uniqueByIdentity(artists + page.artists)
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
        requestedScope: ArtistFeatureScope,
        requestGeneration: Int,
        loadPage: (Int) async throws -> ArtistPage
    ) async {
        do {
            let page = try await loadPage(0)
            try Task.checkCancellation()
            guard owns(requestGeneration, requestedScope) else { return }
            artists = Self.uniqueByIdentity(page.artists)
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

    private func owns(_ requestGeneration: Int, _ requestedScope: ArtistFeatureScope) -> Bool {
        generation == requestGeneration && scope == requestedScope
    }

    private static func uniqueByIdentity(_ values: [Artist]) -> [Artist] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

/// Section model for the Apple Music-style alphabet rail: A–Z with a trailing
/// "#" bucket for names that don't start with a Latin letter. Sections key off
/// the server's SortName (falling back to the display name) so jump targets
/// stay aligned with the list's server-side ordering.
enum ArtistAlphabetIndex {
    static let numberSection = "#"
    static let letters: [String] = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
        + [numberSection]

    static func sectionLetter(for artist: Artist) -> String {
        let trimmedSortName = artist.sortName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmedSortName.flatMap { $0.isEmpty ? nil : $0 } ?? artist.name
        let folded = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
        guard let first = folded.first, first.isASCII, first.isLetter else { return numberSection }
        return String(first)
    }

    /// The artist the rail should scroll to for a selected letter: the first
    /// artist in that section, or the nearest following section when the
    /// letter has no artists (Apple's nearest-neighbour scrub behaviour).
    /// Jellyfin collates non-letter names to the top of the list, so the "#"
    /// bucket matches exactly rather than by position.
    static func target(for letter: String, in artists: [Artist]) -> Artist? {
        guard !artists.isEmpty else { return nil }
        if letter == numberSection {
            return artists.first { sectionLetter(for: $0) == numberSection } ?? artists.last
        }
        guard let wanted = letters.firstIndex(of: letter) else { return nil }
        for artist in artists {
            let section = sectionLetter(for: artist)
            guard section != numberSection, let index = letters.firstIndex(of: section) else { continue }
            if index >= wanted { return artist }
        }
        return artists.last
    }
}
