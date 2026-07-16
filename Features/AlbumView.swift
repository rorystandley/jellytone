import SwiftUI

struct AlbumView: View {
    @EnvironmentObject private var model: AppModel
    let album: Album
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    AuthenticatedArtworkView(itemID: album.id)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.name).font(.title2.bold())
                        Text(album.artist).foregroundStyle(.secondary)
                        if let year = album.productionYear { Text(String(year)).foregroundStyle(.tertiary) }
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Tracks") {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ForEach(tracks) { track in
                        Button { model.play(track) } label: {
                            HStack(spacing: 12) {
                                Text(track.index.map(String.init) ?? "–")
                                    .foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                                VStack(alignment: .leading) {
                                    Text(track.name).foregroundStyle(.primary)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tracks = await model.tracks(for: album)
            isLoading = false
        }
        .safeAreaInset(edge: .bottom) {
            if model.playback.currentTrack != nil { MiniPlayerView(playback: model.playback) }
        }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note").frame(width: 36, height: 36).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading) {
                Text(playback.currentTrack?.name ?? "").font(.headline).lineLimit(1)
                Text(playback.currentTrack?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
