import SwiftUI
import UIKit

/// Apple Music-style Library: large title, plain category rows with hairline
/// separators (Playlists, Artists, Albums, Songs, Genres, Favourites, Downloads),
/// then a newest-first "Recently Added" album grid that paginates (and caches
/// each page) as the user scrolls. Themed per docs/design/design-system.md and
/// AGENTS.md Priority 4.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                    header
                    categoryRows
                    recentlyAddedSection
                }
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, JellytoneTheme.Space.md)
                .padding(.bottom, JellytoneTheme.Space.xxxl)
            }
            .background(Color.jtBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // Every push in this stack is value-based and resolves through the
            // destinations registered here at the root. The category rows and the
            // Artists/Genres lists all live inside lazy containers, where a
            // view-based NavigationLink re-activates whenever the path changes —
            // e.g. opening an album from an artist re-pushed the artist, and then
            // the Artists list, on top of it. Value-based links don't self-fire.
            .navigationDestination(for: LibrarySection.self) { section in
                sectionDestination(section)
            }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
            .navigationDestination(for: Genre.self) { GenreDetailView(genre: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
            .refreshable { try? await model.refreshAlbums(libraryID: model.selectedLibraryID) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            Text("Library")
                .font(.jtLargeTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: JellytoneTheme.Space.sm)
            Menu {
                if model.libraries.count > 1 {
                    Picker("Library", selection: Binding(
                        get: { model.selectedLibraryID ?? "" },
                        set: { id in Task { await model.selectLibrary(id) } }
                    )) {
                        ForEach(model.libraries) { Text($0.name).tag($0.id) }
                    }
                }
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task { await model.logout() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.jtRowTitle.weight(.bold))
                    .foregroundStyle(Color.jtTextPrimary)
                    .frame(width: LibraryMetrics.optionsButtonDiameter,
                           height: LibraryMetrics.optionsButtonDiameter)
                    .background(Circle().fill(Color.jtSurface))
            }
            .accessibilityLabel("Library options")
        }
    }

    // MARK: Category rows

    private var categoryRows: some View {
        VStack(spacing: 0) {
            categoryRow("Playlists", systemImage: "music.note.list",
                        identifier: "library-playlists-link", section: .playlists)
            rowDivider
            categoryRow("Artists", systemImage: "music.mic",
                        identifier: "library-artists-link", section: .artists)
            rowDivider
            categoryRow("Albums", systemImage: "square.stack",
                        identifier: "library-albums-link", section: .albums)
            rowDivider
            categoryRow("Songs", systemImage: "music.note",
                        identifier: "library-tracks-link", section: .songs)
            rowDivider
            categoryRow("Genres", systemImage: "guitars",
                        identifier: "library-genres-link", section: .genres)
            rowDivider
            categoryRow("Favourites", systemImage: "heart.fill",
                        identifier: "library-favourites-link", section: .favourites)
            rowDivider
            categoryRow("Downloads", systemImage: "arrow.down.circle",
                        identifier: "library-downloads-link", section: .downloads)
        }
    }

    @ViewBuilder
    private func sectionDestination(_ section: LibrarySection) -> some View {
        switch section {
        case .playlists: PlaylistLibraryView()
        case .artists: ArtistLibraryView()
        case .albums: AlbumLibraryView()
        case .songs: TrackCatalogView()
        case .genres: GenreLibraryView()
        case .favourites: favouritesDestination
        case .downloads: DownloadsView()
        }
    }

    private func categoryRow(
        _ title: String,
        systemImage: String,
        identifier: String,
        section: LibrarySection
    ) -> some View {
        NavigationLink(value: section) {
            HStack(spacing: JellytoneTheme.Space.mdPlus) {
                Image(systemName: systemImage)
                    .font(.jtSubsectionHeader.weight(.medium))
                    .foregroundStyle(Color.jtAccent)
                    .frame(width: LibraryMetrics.categoryIconWidth)
                Text(title)
                    .font(.jtSubsectionHeader.weight(.medium))
                    .foregroundStyle(Color.jtTextPrimary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.jtCaption.weight(.bold))
                    .foregroundStyle(Color.jtTextTertiary)
            }
            .padding(.vertical, JellytoneTheme.Space.mdPlus)
            .contentShape(Rectangle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Browse \(title.lowercased())")
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.jtBorder).frame(height: 1)
    }

    // MARK: Recently Added

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
            Text("Recently Added")
                .font(.jtSectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            albumContent
        }
    }

    @ViewBuilder private var albumContent: some View {
        if model.isLoading && model.albums.isEmpty {
            JellytoneSkeletonGrid(
                columns: horizontalSizeClass == .regular ? 4 : 2,
                rows: 2,
                label: "Loading albums"
            )
            .accessibilityIdentifier("library-albums-skeleton")
        } else if model.albums.isEmpty {
            detailStateCard(
                title: "No albums found",
                detail: "Pull to refresh or check this account’s Jellyfin library access."
            )
        } else {
            LazyVGrid(columns: albumColumns, spacing: JellytoneTheme.Space.mdPlus) {
                ForEach(model.albums) { album in
                    NavigationLink(value: album) {
                        LibraryGridAlbumCard(album: album)
                    }
                    .buttonStyle(.jtPressScale())
                    .accessibilityIdentifier("library-album-\(album.id)")
                    .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                    .accessibilityHint("Opens album")
                    .task { await model.loadMoreAlbumsIfNeeded(after: album) }
                }
            }
            if model.isLoadingMoreAlbums {
                HStack {
                    Spacer()
                    ProgressView("Loading more albums…")
                        .font(.jtBody)
                        .foregroundStyle(Color.jtTextSecondary)
                    Spacer()
                }
            }
        }
    }

    private var albumColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: JellytoneTheme.Space.mdPlus)]
        } else {
            [
                GridItem(.flexible(), spacing: JellytoneTheme.Space.mdPlus),
                GridItem(.flexible()),
            ]
        }
    }

    private var favouritesDestination: some View {
        FavouritesLibraryView(
            scope: FavouritesFeatureScope(
                serverID: model.session?.serverID ?? "",
                accountID: model.session?.userID ?? "",
                libraryID: model.selectedLibraryID
            ),
            loadArtists: { try await model.favouriteArtistsPage(startIndex: $0) },
            loadAlbums: { try await model.favouriteAlbumsPage(startIndex: $0) },
            loadTracks: { try await model.favouriteTracksPage(startIndex: $0) },
            play: { model.play($0, in: $1) },
            playAll: { model.playAll($0) },
            shuffle: { model.shuffle($0) }
        )
    }
}

/// Value-based routing for the Library category rows, so their links resolve
/// through a `navigationDestination` at the stack root rather than a view-based
/// `NavigationLink` that re-activates inside the lazy list.
enum LibrarySection: Hashable {
    case playlists, artists, albums, songs, genres, favourites, downloads
}

private enum LibraryMetrics {
    static let optionsButtonDiameter: CGFloat = 34
    static let categoryIconWidth: CGFloat = 30
}

/// Full-screen blurred-artwork backdrop for detail screens (album/playlist):
/// the item's artwork blown up, blurred, and washed with a tint so foreground
/// text stays legible. Defaults to the adaptive background token; Now Playing
/// passes a fixed dark tint since that screen is always dark (design-system.md
/// §4.5).
struct JellytoneDetailBackdrop<Artwork: View>: View {
    var tint: Color = .jtBackground
    @ViewBuilder let artwork: () -> Artwork

    private static var blurRadius: CGFloat { 60 }
    private static var overscan: CGFloat { 1.4 }
    private static var washOpacity: Double { 0.6 }

    var body: some View {
        ZStack {
            tint
            artwork()
                .scaleEffect(Self.overscan)
                .blur(radius: Self.blurRadius)
            tint.opacity(Self.washOpacity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Track-row artwork: the track's own image when it has one, otherwise its
/// album's cover, otherwise the generated gradient placeholder.
struct JellytoneTrackArtwork: View {
    let track: Track

    var body: some View {
        if let artworkID = track.artworkItemID {
            AuthenticatedArtworkView(itemID: artworkID, accessibilityLabel: "Artwork for \(track.name)")
        } else {
            JellytoneTheme.placeholderGradient(hue: JellytoneTheme.placeholderHue(forID: track.id))
                .accessibilityLabel("No artwork for \(track.name)")
        }
    }
}

/// Item artwork with the theme's generated-gradient placeholder for missing
/// art (design-system.md §1 — never a grey box).
struct JellytoneItemArtwork: View {
    let itemID: String
    let imageTag: String?
    let name: String

    var body: some View {
        if imageTag != nil {
            AuthenticatedArtworkView(itemID: itemID, accessibilityLabel: "Artwork for \(name)")
        } else {
            JellytoneTheme.placeholderGradient(hue: JellytoneTheme.placeholderHue(forID: itemID))
                .accessibilityLabel("No artwork for \(name)")
        }
    }
}

struct AuthenticatedArtworkView: View {
    @EnvironmentObject private var model: AppModel
    let itemID: String
    var accessibilityLabel = "Album artwork"
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // Loading/missing state is the generated gradient, never a grey
            // box or broken-image glyph (design-system.md §6).
            JellytoneTheme.placeholderGradient(hue: JellytoneTheme.placeholderHue(forID: itemID))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: itemID) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), itemID.contains("artwork") {
                image = Self.syntheticArtwork()
                return
            }
#endif
            guard let api = model.api, let session = model.session else { return }
            let cacheKey = ArtworkCache.key(serverID: session.serverID, itemID: itemID)
            if let cached = await ArtworkCache.shared.image(forKey: cacheKey) {
                image = cached
                return
            }
            guard var request = try? api.artworkRequest(itemID: itemID) else { return }
            request.setValue(session.accessToken, forHTTPHeaderField: "X-Emby-Token")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) == true,
               let fetched = UIImage(data: data) {
                image = fetched
                await ArtworkCache.shared.store(data, forKey: cacheKey)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

#if DEBUG
    private static func syntheticArtwork() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        return renderer.image { context in
            let colors = [UIColor(red: 0.08, green: 0.18, blue: 0.26, alpha: 1).cgColor,
                          UIColor(red: 0.93, green: 0.34, blue: 0.27, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                      locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 600, y: 600), options: [])
            UIColor.white.withAlphaComponent(0.82).setStroke()
            context.cgContext.setLineWidth(20)
            for offset in stride(from: 100, through: 500, by: 100) {
                context.cgContext.move(to: CGPoint(x: 70, y: offset))
                context.cgContext.addCurve(to: CGPoint(x: 530, y: 600 - offset),
                                           control1: CGPoint(x: 220, y: offset - 90),
                                           control2: CGPoint(x: 380, y: 690 - offset))
                context.cgContext.strokePath()
            }
        }
    }
#endif
}
