import SwiftUI

struct MusicShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPlayer = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.playback.currentTrack != nil {
                MiniPlayerView(playback: model.playback) { showingPlayer = true }
            }
        }
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(playback: model.playback)
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your music")
                            .font(.largeTitle.bold())
                        Text(model.session.map { "Listening as \($0.username)" } ?? "")
                            .foregroundStyle(.secondary)
                    }

                    if let current = model.playback.currentTrack {
                        Button { model.playback.toggle() } label: {
                            HStack(spacing: 16) {
                                NowPlayingArtwork(playback: model.playback)
                                    .frame(width: 72, height: 72)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue listening")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(current.name).font(.headline).lineLimit(1)
                                    Text(current.artist).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: model.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 38))
                            }
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Albums").font(.title2.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(model.albums.prefix(12)) { album in
                                    NavigationLink(value: album) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            AuthenticatedArtworkView(itemID: album.id)
                                                .frame(width: 156, height: 156)
                                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                            Text(album.name).font(.headline).lineLimit(1)
                                            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .frame(width: 156, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .refreshable { try? await model.refreshAlbums(libraryID: model.selectedLibraryID) }
        }
    }
}

private struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search your library",
                        systemImage: "magnifyingglass",
                        description: Text("Find an album or artist from the music already loaded.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { album in
                        NavigationLink(value: album) {
                            HStack(spacing: 12) {
                                AuthenticatedArtworkView(itemID: album.id)
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(album.name).font(.headline)
                                    Text(album.artist).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .searchable(text: $query, prompt: "Albums and artists")
        }
    }

    private var results: [Album] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return model.albums.filter {
            $0.name.localizedCaseInsensitiveContains(value)
                || $0.artist.localizedCaseInsensitiveContains(value)
        }
    }
}

struct NowPlayingArtwork: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Group {
            if let artwork = playback.artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.indigo, .purple, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
