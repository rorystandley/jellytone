import SwiftUI

struct AlbumView: View {
    @EnvironmentObject private var model: AppModel
    let album: Album
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var showingPlayer = false

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
                        Button {
                            if let first = tracks.first { model.play(first, in: tracks) }
                        } label: {
                            Label("Play album", systemImage: "play.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())
                        .disabled(tracks.isEmpty)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Tracks") {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ForEach(tracks) { track in
                        Button { model.play(track, in: tracks) } label: {
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
        .sheet(isPresented: $showingPlayer) { NowPlayingView(playback: model.playback) }
        .safeAreaInset(edge: .bottom) {
            if model.playback.currentTrack != nil {
                MiniPlayerView(playback: model.playback) { showingPlayer = true }
            }
        }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController
    let showPlayer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: showPlayer) {
                HStack(spacing: 12) {
                    Image(systemName: "music.note").frame(width: 40, height: 40)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text(playback.currentTrack?.name ?? "").font(.headline).lineLimit(1)
                        Text(playback.currentTrack?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            Button { playback.next() } label: {
                Image(systemName: "forward.end.fill").font(.title3)
            }
            .disabled(!playback.canGoNext)
            .accessibilityLabel("Next track")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct NowPlayingView: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 12)
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.linearGradient(colors: [.indigo, .purple, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note")
                        .font(.system(size: 92, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)

                VStack(spacing: 6) {
                    Text(playback.currentTrack?.name ?? "Nothing playing")
                        .font(.title2.bold()).lineLimit(2).multilineTextAlignment(.center)
                    Text(playback.currentTrack?.artist ?? "")
                        .font(.headline).foregroundStyle(.secondary).lineLimit(1)
                }

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { playback.elapsed }, set: { playback.seek(to: $0) }),
                        in: 0...max(playback.duration, 1)
                    )
                    HStack {
                        Text(time(playback.elapsed))
                        Spacer()
                        Text("−\(time(max(playback.duration - playback.elapsed, 0)))")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }

                HStack(spacing: 46) {
                    Button { playback.previous() } label: {
                        Image(systemName: "backward.end.fill").font(.title)
                    }
                    .disabled(!playback.canGoPrevious)
                    Button { playback.toggle() } label: {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                    }
                    Button { playback.next() } label: {
                        Image(systemName: "forward.end.fill").font(.title)
                    }
                    .disabled(!playback.canGoNext)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
