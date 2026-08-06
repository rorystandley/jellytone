import SwiftUI

/// Library → Playlists. Dense artwork grid, cache-first seed, silent refresh.
/// Themed per design-system.md and AGENTS.md Priority 4.
struct PlaylistLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = PlaylistLibraryState()

    var body: some View {
        Group {
            if state.isLoading && state.playlists.isEmpty {
                skeleton
            } else if let message = state.errorMessage, state.playlists.isEmpty {
                stateCard(
                    title: "Couldn’t load playlists",
                    detail: message,
                    actionTitle: "Try Again"
                ) {
                    Task { await load() }
                }
            } else if state.hasLoaded && state.playlists.isEmpty {
                stateCard(
                    title: "No playlists found",
                    detail: "This user has no music playlists available in Jellyfin."
                )
            } else {
                playlistGrid
            }
        }
        .background(Color.jtBackground.ignoresSafeArea())
        .accessibilityIdentifier("playlists-screen")
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.large)
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

    private var skeleton: some View {
        ScrollView {
            JellytoneSkeletonGrid(columns: columnCount, label: "Loading playlists")
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, JellytoneTheme.Space.md)
                .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
    }

    private var playlistGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                ForEach(state.playlists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.jtPressScale())
                    .accessibilityIdentifier("playlist-row-\(playlist.id)")
                    .task {
                        if playlist.id == state.playlists.last?.id { await loadMore() }
                    }
                }
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.sm)
            .padding(.bottom, JellytoneTheme.Space.xxxl)

            paginationStatus
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.bottom, JellytoneTheme.Space.xl)
        }
        .refreshable { await refresh() }
    }

    private var columnCount: Int {
        horizontalSizeClass == .regular ? 4 : 2
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: JellytoneTheme.Space.mdPlus)]
        } else {
            [
                GridItem(.flexible(), spacing: JellytoneTheme.Space.mdPlus),
                GridItem(.flexible()),
            ]
        }
    }

    @ViewBuilder
    private var paginationStatus: some View {
        if state.isLoadingMore {
            ProgressView("Loading more playlists…")
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
                .frame(maxWidth: .infinity)
        } else if let message = state.paginationError {
            VStack(spacing: JellytoneTheme.Space.sm) {
                Text("Couldn’t load more playlists")
                    .font(.jtSubsectionHeader)
                    .foregroundStyle(Color.jtTextPrimary)
                Text(message)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                Button("Retry More Playlists") { Task { await loadMore() } }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
            }
            .frame(maxWidth: .infinity)
        } else if let message = state.errorMessage {
            VStack(spacing: JellytoneTheme.Space.sm) {
                Text(message)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                Button("Retry Refresh") { Task { await refresh() } }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stateCard(
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text(title)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text(detail)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.jtCapsule(.secondaryFlat))
                    .padding(.top, JellytoneTheme.Space.xxs)
            }
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.jtSurface,
            in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
        )
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, JellytoneTheme.Space.md)
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
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            PlaylistArtwork(playlist: playlist)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.gridArtwork, style: .continuous)
                )
            Text(playlist.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
            if let countLabel {
                Text(countLabel)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
