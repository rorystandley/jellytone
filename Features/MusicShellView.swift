import SwiftUI

struct MusicShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPlayer = false

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabs
                    .tabBarMinimizeBehavior(.never)
                    .tabViewBottomAccessory { miniPlayer }
            } else {
                tabs.safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            }
        }
        .tint(AudioDesign.accent)
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(playback: model.playback)
        }
    }

    private var tabs: some View {
        TabView {
            NavigationStack {
                HomeLibraryView { AlbumView(album: $0) }
            }
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if model.playback.currentTrack != nil {
            MiniPlayerView(playback: model.playback) { showingPlayer = true }
        }
    }
}

struct NowPlayingArtwork: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Group {
            if let artwork = playback.artwork {
                AudioArtwork(image: artwork, label: playback.currentTrack?.name ?? "current track")
            } else {
                AudioArtwork(image: nil, label: playback.currentTrack?.name ?? "current track")
            }
        }
    }
}
