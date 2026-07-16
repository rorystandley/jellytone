import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.albums.isEmpty {
                    ProgressView("Loading music…")
                } else if model.libraries.isEmpty {
                    ContentUnavailableView("No music libraries", systemImage: "music.note.house")
                } else {
                    albumGrid
                }
            }
            .navigationTitle(model.session?.serverName ?? "Music")
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
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") { model.logout() }
                }
            }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .safeAreaInset(edge: .bottom) {
                if model.playback.currentTrack != nil { MiniPlayerView(playback: model.playback) }
            }
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
                }
            }
            .padding()
        }
        .refreshable {
            if let id = model.selectedLibraryID { try? await model.refreshAlbums(libraryID: id) }
        }
    }
}

struct AuthenticatedArtworkView: View {
    @EnvironmentObject private var model: AppModel
    let itemID: String
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
        .accessibilityLabel("Album artwork")
    }
}
