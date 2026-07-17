import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NavigationLink {
                    PlaylistLibraryView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Playlists").font(.headline)
                            Text("Browse this account's playlists")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-playlists-link")
                .accessibilityLabel("Browse playlists")

                Divider()

                Group {
                    if model.isLoading && model.albums.isEmpty {
                        ProgressView("Loading music…")
                    } else if model.albums.isEmpty {
                        ContentUnavailableView(
                            "No albums found",
                            systemImage: "music.note.house",
                            description: Text("Pull to refresh or check this user's Jellyfin library access.")
                        )
                    } else {
                        albumGrid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                ForEach(model.albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 8) {
                            AuthenticatedArtworkView(itemID: album.id)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(album.name).font(.headline).lineLimit(2)
                            Text(album.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreAlbumsIfNeeded(after: album) }
                }
            }
            .padding()
            if model.isLoadingMoreAlbums {
                ProgressView("Loading more albums…").padding(.bottom, 24)
            }
        }
        .refreshable {
            try? await model.refreshAlbums(libraryID: model.selectedLibraryID)
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
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: itemID) {
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
}
