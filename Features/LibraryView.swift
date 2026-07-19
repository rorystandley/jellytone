import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            AudioBrowseContainer(spacing: AudioDesign.Space.xl) {
                AudioSectionHeading(title: "Browse", detail: "Your music, organised for quick access")
                LazyVGrid(columns: destinationColumns, spacing: AudioDesign.Space.sm) {
                    NavigationLink { PlaylistLibraryView() } label: {
                        LibraryDestinationCard(title: "Playlists", detail: "Your mixes and saved sequences", systemImage: "music.note.list")
                    }
                    .accessibilityIdentifier("library-playlists-link")
                    NavigationLink { TrackCatalogView() } label: {
                        LibraryDestinationCard(title: "Tracks", detail: "Every playable song", systemImage: "music.note")
                    }
                    .accessibilityIdentifier("library-tracks-link")
                    NavigationLink { GenreLibraryView() } label: {
                        LibraryDestinationCard(title: "Genres", detail: "Explore by sound", systemImage: "guitars")
                    }
                    .accessibilityIdentifier("library-genres-link")
                    NavigationLink { favouritesDestination } label: {
                        LibraryDestinationCard(title: "Favourites", detail: "Artists, albums, and tracks", systemImage: "heart.fill")
                    }
                    .accessibilityIdentifier("library-favourites-link")
                }
                .buttonStyle(.plain)

                AudioSectionHeading(title: "Albums", detail: "Covers from your selected music library")
                albumContent
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.libraries.count > 1 {
                        Picker("Library", selection: Binding(
                            get: { model.selectedLibraryID ?? "" },
                            set: { id in Task { await model.selectLibrary(id) } }
                        )) {
                            ForEach(model.libraries) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await model.logout() }
                    }
                }
            }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .refreshable { try? await model.refreshAlbums(libraryID: model.selectedLibraryID) }
        }
    }

    private var destinationColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: AudioDesign.Space.sm)]
        } else {
            [GridItem(.flexible(), spacing: AudioDesign.Space.sm)]
        }
    }

    @ViewBuilder private var albumContent: some View {
        if model.isLoading && model.albums.isEmpty {
            AudioStateView(kind: .loading, title: "Loading albums", detail: "Fetching this music library…")
                .frame(maxWidth: .infinity)
        } else if model.albums.isEmpty {
            AudioStateView(kind: .empty, title: "No albums found",
                           detail: "Pull to refresh or check this account’s Jellyfin library access.")
                .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 180 : 145,
                                                   maximum: 240), spacing: AudioDesign.Space.md)], spacing: AudioDesign.Space.lg) {
                ForEach(model.albums) { album in
                    NavigationLink(value: album) {
                        AudioMusicCard(title: album.name, subtitle: album.artist,
                                       detail: album.productionYear.map(String.init)) {
                            if album.imageTag != nil {
                                AuthenticatedArtworkView(itemID: album.id, accessibilityLabel: "Artwork for \(album.name)")
                            } else {
                                AudioMissingArtwork(label: album.name)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-album-\(album.id)")
                    .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                    .accessibilityHint("Opens album")
                    .task { await model.loadMoreAlbumsIfNeeded(after: album) }
                }
            }
            if model.isLoadingMoreAlbums {
                ProgressView("Loading more albums…").frame(maxWidth: .infinity).padding(.bottom, AudioDesign.Space.lg)
            }
        }
    }

    private var favouritesDestination: some View {
        FavouritesLibraryView(
            scope: FavouritesFeatureScope(serverID: model.session?.serverID ?? "", accountID: model.session?.userID ?? "", libraryID: model.selectedLibraryID),
            loadArtists: { try await model.favouriteArtistsPage(startIndex: $0) },
            loadAlbums: { try await model.favouriteAlbumsPage(startIndex: $0) },
            loadTracks: { try await model.favouriteTracksPage(startIndex: $0) },
            artistDestination: { ArtistView(artist: $0) }, albumDestination: { AlbumView(album: $0) },
            play: { model.play($0, in: $1) }, playAll: { model.playAll($0) }, shuffle: { model.shuffle($0) }
        )
    }
}

private struct LibraryDestinationCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AudioDesign.Space.md) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AudioDesign.accent)
                .frame(width: 52, height: 52)
                .background(AudioDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AudioDesign.Radius.compact, style: .continuous))
            VStack(alignment: .leading, spacing: AudioDesign.Space.xxs) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote.bold()).foregroundStyle(.tertiary)
        }
        .padding(AudioDesign.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .audioElevatedSurface(cornerRadius: AudioDesign.Radius.compact)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Browse \(title.lowercased()), \(detail)")
    }
}

struct AuthenticatedArtworkView: View {
    @EnvironmentObject private var model: AppModel
    let itemID: String
    var accessibilityLabel = "Album artwork"
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
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
            guard let api = model.api, let token = model.session?.accessToken,
                  var request = try? api.artworkRequest(itemID: itemID) else { return }
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) == true {
                image = UIImage(data: data)
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
