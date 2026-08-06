import SwiftUI

/// Full-library Albums destination (Apple Music Library → Albums).
/// Reuses the cache-first album list already owned by `AppModel` (same pages as
/// the Library hub’s Recently Added shelf) so we avoid a second network path.
/// Themed per docs/design/design-system.md and AGENTS.md Priority 4.
struct AlbumLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if model.isLoading && model.albums.isEmpty {
                skeleton
            } else if model.albums.isEmpty {
                emptyState
            } else {
                albumGrid
            }
        }
        .background(Color.jtBackground.ignoresSafeArea())
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("albums-screen")
        .refreshable {
            try? await model.refreshAlbums(libraryID: model.selectedLibraryID)
        }
        .task(id: model.selectedLibraryID) {
            // Cache is already painted by AppModel session restore; only fetch
            // when the selected library has no albums yet.
            if model.albums.isEmpty {
                try? await model.refreshAlbums(libraryID: model.selectedLibraryID)
            }
        }
    }

    private var skeleton: some View {
        ScrollView {
            JellytoneSkeletonGrid(columns: columnCount, label: "Loading albums")
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, JellytoneTheme.Space.md)
                .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        .accessibilityIdentifier("albums-loading-skeleton")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text("No albums found")
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text("Pull to refresh or check this account’s Jellyfin library access.")
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
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

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: JellytoneTheme.Space.mdPlus) {
                ForEach(model.albums) { album in
                    NavigationLink(value: album) {
                        LibraryGridAlbumCard(album: album)
                    }
                    .buttonStyle(.jtPressScale())
                    .accessibilityIdentifier("albums-grid-\(album.id)")
                    .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                    .accessibilityHint("Opens album")
                    .task { await model.loadMoreAlbumsIfNeeded(after: album) }
                }
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.sm)
            .padding(.bottom, JellytoneTheme.Space.xxxl)

            if model.isLoadingMoreAlbums {
                ProgressView("Loading more albums…")
                    .font(.jtBody)
                    .foregroundStyle(Color.jtTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, JellytoneTheme.Space.xl)
            }
        }
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
}

/// Shared dense album tile used by the Library hub shelf and the Albums grid.
struct LibraryGridAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            JellytoneItemArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.gridArtwork, style: .continuous)
                )
            Text(album.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
            Text(album.artist)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
