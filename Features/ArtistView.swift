import SwiftUI

struct ArtistView: View {
    @EnvironmentObject private var model: AppModel
    let artist: Artist
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextStartIndex = 0
    @State private var errorMessage: String?

    var body: some View {
        AudioBrowseContainer(spacing: AudioDesign.Space.xl) {
            artistHeader
            albumContent
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Album.self) { AlbumView(album: $0) }
        .task(id: artist.id) { await loadAlbums(replacing: true) }
    }

    private var artistHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                artwork.frame(width: 144, height: 144)
                identity
                Spacer(minLength: 0)
            }
            VStack(spacing: 14) {
                artwork.frame(width: 160, height: 160)
                identity.multilineTextAlignment(.center)
            }
        }
    }

    private var artwork: some View {
        Group {
            if artist.imageTag != nil {
                AuthenticatedArtworkView(itemID: artist.id, accessibilityLabel: "Artwork for \(artist.name)")
            } else {
                AudioMissingArtwork(label: artist.name, systemImage: "music.mic")
            }
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Artist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(artist.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var albumContent: some View {
        if isLoading && albums.isEmpty {
            AudioStateView(kind: .loading, title: "Loading albums", detail: "Fetching this artist’s releases…")
                .frame(maxWidth: .infinity)
        } else if let errorMessage, albums.isEmpty {
            AudioStateView(kind: .error, title: "Albums unavailable", detail: errorMessage,
                           actionTitle: "Try Again") { Task { await loadAlbums(replacing: true) } }
                .frame(maxWidth: .infinity)
        } else if albums.isEmpty {
            AudioStateView(kind: .empty, title: "No albums found",
                           detail: "Jellyfin did not return music albums for this artist.")
                .frame(maxWidth: .infinity)
        } else {
            AudioSectionHeading(title: "Albums", detail: "Releases by \(artist.name)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)], spacing: 20) {
                ForEach(albums) { album in
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
                    .accessibilityIdentifier("artist-album-\(album.id)")
                    .accessibilityLabel("Album, \(album.name), by \(album.artist)")
                    .accessibilityHint("Opens album")
                    .task {
                        if album.id == albums.last?.id, hasMore { await loadAlbums(replacing: false) }
                    }
                }
            }
            AudioPaginationView(isLoading: isLoadingMore, message: isLoadingMore ? nil : errorMessage,
                                loadingTitle: "Loading more albums…", retryTitle: "Retry More Albums") {
                Task { await loadAlbums(replacing: false) }
            }
        }
    }

    private func loadAlbums(replacing: Bool) async {
        guard replacing || (hasMore && !isLoadingMore) else { return }
        if replacing {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let page = try await model.albums(for: artist, startIndex: replacing ? 0 : nextStartIndex)
            if replacing {
                albums = page.albums
            } else {
                let existing = Set(albums.map(\.id))
                albums.append(contentsOf: page.albums.filter { !existing.contains($0.id) })
            }
            hasMore = page.hasMore
            nextStartIndex = page.nextStartIndex
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
