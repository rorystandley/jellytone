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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                artistHeader
                albumContent
            }
            .padding()
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
        AuthenticatedArtworkView(itemID: artist.id, accessibilityLabel: "Artwork for \(artist.name)")
            .clipShape(Circle())
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
            HStack { Spacer(); ProgressView("Loading albums…"); Spacer() }
                .frame(minHeight: 160)
        } else if let errorMessage, albums.isEmpty {
            ContentUnavailableView {
                Label("Albums unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await loadAlbums(replacing: true) } }
                    .buttonStyle(.borderedProminent)
            }
        } else if albums.isEmpty {
            ContentUnavailableView(
                "No albums found",
                systemImage: "square.stack",
                description: Text("Jellyfin did not return music albums for this artist.")
            )
        } else {
            Text("Albums").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)], spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 8) {
                            AuthenticatedArtworkView(
                                itemID: album.id,
                                accessibilityLabel: "Artwork for \(album.name)"
                            )
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(album.name).font(.headline).lineLimit(2)
                            if let year = album.productionYear {
                                Text(String(year)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if album.id == albums.last?.id, hasMore { await loadAlbums(replacing: false) }
                    }
                }
            }
            if isLoadingMore { ProgressView("Loading more albums…").frame(maxWidth: .infinity) }
            if errorMessage != nil && !isLoadingMore {
                Button("Retry More Albums") { Task { await loadAlbums(replacing: false) } }
                    .frame(maxWidth: .infinity)
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
