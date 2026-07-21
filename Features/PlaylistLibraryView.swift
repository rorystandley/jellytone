import SwiftUI

struct PlaylistLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = PlaylistLibraryState()

    var body: some View {
        Group {
            if state.isLoading && state.playlists.isEmpty {
                AudioStateView(kind: .loading, title: "Loading playlists", detail: "Fetching your saved sequences…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else if let message = state.errorMessage, state.playlists.isEmpty {
                unavailable(message)
            } else if state.hasLoaded && state.playlists.isEmpty {
                AudioStateView(kind: .empty, title: "No playlists found",
                               detail: "This user has no music playlists available in Jellyfin.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                playlistGrid
            }
        }
        .accessibilityIdentifier("playlists-screen")
        .navigationTitle("Playlists")
        .audioCanvas()
        .task(id: scope) {
            // Cache-first: paint the persisted snapshot, then refresh silently.
            state.seed(await model.cachedPlaylists(), scope: scope)
            if state.playlists.isEmpty { await load() } else { await refresh() }
        }
    }

    private var scope: PlaylistFeatureScope {
        PlaylistFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var playlistGrid: some View {
        AudioBrowseContainer(spacing: AudioDesign.Space.lg) {
            AudioSectionHeading(title: "Your Playlists", detail: "Saved mixes in Jellyfin order")
            LazyVGrid(columns: columns, alignment: .leading, spacing: AudioDesign.Space.lg) {
                ForEach(state.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        PlaylistCard(playlist: playlist)
                    }
                    .accessibilityIdentifier("playlist-row-\(playlist.id)")
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .task {
                        if playlist.id == state.playlists.last?.id { await loadMore() }
                    }
                }
            }
            paginationStatus
        }
        .refreshable { await refresh() }
        .overlay(alignment: .top) {
            if state.isLoading && !state.playlists.isEmpty {
                ProgressView("Refreshing playlists…")
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
            ProgressView("Loading more playlists…")
                .frame(maxWidth: .infinity)
        } else if let message = state.paginationError {
            AudioPaginationView(isLoading: false, message: message, loadingTitle: "",
                                retryTitle: "Retry More Playlists") { Task { await loadMore() } }
        } else if let message = state.errorMessage {
            AudioPaginationView(isLoading: false, message: message, loadingTitle: "",
                                retryTitle: "Retry Refresh") { Task { await refresh() } }
        }
    }

    private func unavailable(_ message: String) -> some View {
        AudioStateView(kind: .error, title: "Couldn’t load playlists", detail: message,
                       actionTitle: "Try Again") { Task { await load() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func load() async {
        let requestScope = scope
        await state.load(scope: requestScope) { startIndex in
            try await model.playlistPage(startIndex: startIndex)
        }
    }

    private func refresh() async {
        let requestScope = scope
        await state.refresh(scope: requestScope) { startIndex in
            try await model.playlistPage(startIndex: startIndex)
        }
    }

    private func loadMore() async {
        let requestScope = scope
        await state.loadMore(scope: requestScope) { startIndex in
            try await model.playlistPage(startIndex: startIndex)
        }
    }
}

private struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        AudioMusicCard(title: playlist.name, subtitle: countLabel) {
            PlaylistArtwork(playlist: playlist)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens playlist")
    }

    private var accessibilityLabel: String {
        guard let count = playlist.itemCount else { return playlist.name }
        return "\(playlist.name), \(count == 1 ? "1 item" : "\(count) items")"
    }

    private var countLabel: String? {
        guard let itemCount = playlist.itemCount else { return nil }
        return itemCount == 1 ? "1 item" : "\(itemCount) items"
    }
}

struct PlaylistArtwork: View {
    let playlist: Playlist

    var body: some View {
        JellytoneItemArtwork(itemID: playlist.id, imageTag: playlist.imageTag, name: playlist.name)
    }
}
