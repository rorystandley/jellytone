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
                        .contextMenu {
                            Button("Play Next", systemImage: "text.insert") { model.playNext(track) }
                                .disabled(model.playback.currentTrack == nil)
                            Button("Add to Queue", systemImage: "text.badge.plus") { model.addToQueue(track) }
                                .disabled(model.playback.currentTrack == nil)
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
    }
}

struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController
    let showPlayer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: playback.elapsed, total: max(playback.duration, 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)
            HStack(spacing: 12) {
                Button(action: showPlayer) {
                    HStack(spacing: 12) {
                        NowPlayingArtwork(playback: playback)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playback.currentTrack?.name ?? "").font(.headline).lineLimit(1)
                            Text(playback.currentTrack?.artist ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-details")
                Spacer()
                Button { playback.toggle() } label: {
                    if playback.isPreparing {
                        ProgressView()
                    } else {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                Button { playback.next() } label: {
                    Image(systemName: "forward.end.fill").font(.title3)
                }
                .disabled(!playback.canGoNext && playback.repeatMode != .all)
                .accessibilityLabel("Next track")
            }
            .padding(.horizontal)
            .padding(.vertical, 9)
        }
        .background(.regularMaterial)
    }
}

struct NowPlayingView: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var showingQueue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    NowPlayingArtwork(playback: playback)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)

                    VStack(spacing: 6) {
                        Text(playback.currentTrack?.name ?? "Nothing playing")
                            .font(.title2.bold()).lineLimit(2).multilineTextAlignment(.center)
                        Text(playback.currentTrack?.artist ?? "")
                            .font(.headline).foregroundStyle(.secondary).lineLimit(1)
                        Text(playback.currentTrack?.album ?? "")
                            .font(.subheadline).foregroundStyle(.tertiary).lineLimit(1)
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

                    HStack {
                        Button { playback.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(playback.isShuffled ? Color.accentColor : .primary)
                        }
                        .accessibilityLabel(playback.isShuffled ? "Disable shuffle" : "Enable shuffle")
                        Spacer()
                        Button { playback.previous() } label: {
                            Image(systemName: "backward.end.fill").font(.title)
                        }
                        .disabled(!playback.canGoPrevious)
                        Spacer()
                        Button { playback.toggle() } label: {
                            Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                        }
                        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                        Spacer()
                        Button { playback.next() } label: {
                            Image(systemName: "forward.end.fill").font(.title)
                        }
                        .disabled(!playback.canGoNext && playback.repeatMode != .all)
                        Spacer()
                        Button { playback.cycleRepeatMode() } label: {
                            Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat")
                                .foregroundStyle(playback.repeatMode == .off ? Color.primary : Color.accentColor)
                        }
                        .accessibilityLabel(repeatAccessibilityLabel)
                    }

                    HStack {
                        Label(playback.qualityLabel, systemImage: "waveform")
                        Spacer()
                        Button("Queue", systemImage: "list.bullet") { showingQueue = true }
                            .accessibilityIdentifier("show-queue")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingQueue) { PlaybackQueueView(playback: playback) }
        }
        .presentationDetents([.large])
    }

    private var repeatAccessibilityLabel: String {
        switch playback.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat queue"
        case .one: "Repeat one"
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct PlaybackQueueView: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = playback.currentTrack {
                    Section("Now Playing") {
                        QueueTrackRow(track: current, isCurrent: true)
                            .listRowBackground(Color.accentColor.opacity(0.12))
                            .accessibilityHint("Currently playing. This track cannot be removed.")
                    }
                }
                Section("Up Next") {
                    if playback.upcomingEntries.isEmpty {
                        ContentUnavailableView(
                            "Nothing Up Next",
                            systemImage: "text.line.last.and.arrowtriangle.forward",
                            description: Text("The current track will keep playing.")
                        )
                    } else {
                        ForEach(playback.upcomingEntries) { entry in
                            Button { playback.jump(to: entry.id) } label: {
                                QueueTrackRow(track: entry.track, isCurrent: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play \(entry.track.name) by \(entry.track.artist)")
                            .accessibilityHint("Jumps to this track")
                            .accessibilityAction(named: "Move Earlier") {
                                playback.moveUpcoming(entryID: entry.id, by: -1)
                            }
                            .accessibilityAction(named: "Move Later") {
                                playback.moveUpcoming(entryID: entry.id, by: 1)
                            }
                            .accessibilityAction(named: "Remove from Up Next") {
                                playback.removeUpcoming(entryIDs: [entry.id])
                            }
                        }
                        .onMove(perform: playback.moveUpcoming)
                        .onDelete(perform: playback.removeUpcoming)
                    }
                }
                if !playback.upcomingEntries.isEmpty {
                    Section {
                        Button("Clear Up Next", systemImage: "text.badge.minus") {
                            playback.clearUpNext()
                        }
                        .accessibilityHint("Keeps the current track playing")
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !playback.upcomingEntries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct QueueTrackRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                .frame(width: 24)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.durationLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
