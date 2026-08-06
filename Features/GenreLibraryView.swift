import SwiftUI

/// Library → Genres. Dense card grid with cache-first seed and silent refresh.
/// Themed per design-system.md and AGENTS.md Priority 4.
struct GenreLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = GenreLibraryState()

    var body: some View {
        Group {
            if state.isLoading && state.genres.isEmpty {
                skeleton
            } else if let message = state.errorMessage, state.genres.isEmpty {
                stateCard(
                    title: "Couldn’t load genres",
                    detail: message,
                    actionTitle: "Try Again"
                ) {
                    Task { await load() }
                }
            } else if state.hasLoaded && state.genres.isEmpty {
                stateCard(
                    title: "No genres found",
                    detail: "This music library has no genres available in Jellyfin."
                )
            } else {
                genreGrid
            }
        }
        .background(Color.jtBackground.ignoresSafeArea())
        .accessibilityIdentifier("genres-screen")
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.large)
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

    private var skeleton: some View {
        ScrollView {
            JellytoneSkeletonGrid(columns: columnCount, label: "Loading genres")
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, JellytoneTheme.Space.md)
                .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
    }

    private var genreGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                ForEach(state.genres) { genre in
                    NavigationLink(value: genre) {
                        GenreCard(genre: genre)
                    }
                    .buttonStyle(.jtPressScale())
                    .accessibilityIdentifier("genre-row-\(genre.id)")
                    .task {
                        if genre.id == state.genres.last?.id { await loadMore() }
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
        horizontalSizeClass == .regular ? 3 : 2
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: JellytoneTheme.Space.mdPlus)]
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
            ProgressView("Loading more genres…")
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("genre-load-more")
        } else if let message = state.paginationError {
            VStack(spacing: JellytoneTheme.Space.sm) {
                Text("Couldn’t load more genres")
                    .font(.jtSubsectionHeader)
                    .foregroundStyle(Color.jtTextPrimary)
                Text(message)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                Button("Retry loading more genres") { Task { await loadMore() } }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
                    .accessibilityIdentifier("genre-load-more")
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
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
            HStack {
                Image(systemName: "guitars")
                    .font(.jtSubsectionHeader.weight(.semibold))
                    .foregroundStyle(Color.jtAccent)
                    .frame(width: GenreMetrics.iconSide, height: GenreMetrics.iconSide)
                    .background(
                        Color.jtAccentDim,
                        in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.compactArtwork, style: .continuous)
                    )
                Spacer(minLength: JellytoneTheme.Space.sm)
                Image(systemName: "chevron.forward")
                    .font(.jtCaption.weight(.bold))
                    .foregroundStyle(Color.jtTextTertiary)
            }
            Text(genre.name)
                .font(.jtSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(2)
            if let summary {
                Text(summary)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(2)
            }
        }
        .padding(JellytoneTheme.Space.md)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            Color.jtSurface,
            in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
        )
        .contentShape(Rectangle())
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

private enum GenreMetrics {
    static let iconSide: CGFloat = 48
}

struct GenreArtwork: View {
    let genre: Genre

    var body: some View {
        JellytoneItemArtwork(itemID: genre.id, imageTag: genre.imageTag, name: genre.name)
    }
}
