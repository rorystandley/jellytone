import SwiftUI

struct PlaylistLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = PlaylistLibraryState()

    var body: some View {
        Group {
            if state.isLoading && state.playlists.isEmpty {
                ProgressView("Loading playlists…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = state.errorMessage, state.playlists.isEmpty {
                unavailable(message)
            } else if state.hasLoaded && state.playlists.isEmpty {
                ContentUnavailableView(
                    "No playlists found",
                    systemImage: "music.note.list",
                    description: Text("This user has no music playlists available in Jellyfin.")
                )
            } else {
                playlistGrid
            }
        }
        .accessibilityIdentifier("playlists-screen")
        .navigationTitle("Playlists")
        .task(id: scope) { await load() }
    }

    private var scope: PlaylistFeatureScope {
        PlaylistFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var playlistGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
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
            .padding()

            paginationStatus
                .padding(.bottom, 24)
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
            VStack(spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry More Playlists") { Task { await loadMore() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
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
        ContentUnavailableView {
            Label("Couldn’t load playlists", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            PlaylistArtwork(playlist: playlist)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(playlist.name)
                .font(.headline)
                .lineLimit(2)
            if let itemCount = playlist.itemCount {
                Text(itemCount == 1 ? "1 item" : "\(itemCount) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
}

struct PlaylistArtwork: View {
    let playlist: Playlist

    var body: some View {
        if playlist.imageTag != nil {
            AuthenticatedArtworkView(
                itemID: playlist.id,
                accessibilityLabel: "Artwork for \(playlist.name)"
            )
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note.list")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("No artwork for \(playlist.name)")
        }
    }
}
