import SwiftUI

/// Amazon Music-style album detail: blurred artwork backdrop, centred artwork
/// card, left-aligned identity block, trailing shuffle + solid accent play
/// circle, and plain track rows on the backdrop wash. Themed per
/// docs/design/design-system.md.
struct AlbumView: View {
    @EnvironmentObject private var model: AppModel
    let album: Album
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                artworkCard
                identity
                trackList
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.lg)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        .background(
            JellytoneDetailBackdrop {
                JellytoneItemArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
            }
        )
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Paint last visit's snapshot instantly, then refresh silently.
            if tracks.isEmpty, let cached = await model.cachedAlbumTracks(for: album), !cached.isEmpty {
                tracks = cached
                isLoading = false
            }
            let fresh = await model.tracks(for: album)
            if !fresh.isEmpty || tracks.isEmpty { tracks = fresh }
            isLoading = false
        }
    }

    private var artworkCard: some View {
        JellytoneItemArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
            .frame(width: DetailMetrics.artworkSide, height: DetailMetrics.artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.largeArtwork, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
            Text(album.name)
                .font(.jtDetailTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(album.artist)
                .font(.jtBody.weight(.medium))
                .foregroundStyle(Color.jtTextSecondary)
            Text(metaLine)
                .font(.jtCaption)
                .foregroundStyle(Color.jtTextTertiary)
            HStack(spacing: JellytoneTheme.Space.xl) {
                Spacer()
                Button { model.shuffle(tracks) } label: {
                    Image(systemName: "shuffle")
                        .font(.jtSubsectionHeader)
                        .foregroundStyle(Color.jtTextPrimary)
                        .frame(width: DetailMetrics.secondaryActionSide, height: DetailMetrics.secondaryActionSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                .accessibilityIdentifier("album-shuffle")
                .accessibilityLabel("Shuffle")
                Button {
                    if let first = tracks.first { model.play(first, in: tracks) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: DetailMetrics.playDiameter / 3, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: DetailMetrics.playDiameter, height: DetailMetrics.playDiameter)
                        .background(Circle().fill(Color.jtAccent))
                }
                .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                .accessibilityIdentifier("album-play-all")
                .accessibilityLabel("Play All")
            }
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.4 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var trackList: some View {
        if isLoading {
            JellytoneSkeletonRows(label: "Loading tracks")
        } else if tracks.isEmpty {
            detailStateCard(title: "No playable tracks",
                            detail: "Jellyfin did not return playable audio for this album.")
        } else {
            ForEach(discNumbers, id: \.self) { disc in
                if discNumbers.count > 1 {
                    Text("Disc \(disc)")
                        .font(.jtSubsectionHeader)
                        .foregroundStyle(Color.jtTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                let discTracks = tracksForDisc(disc)
                LazyVStack(spacing: 0) {
                    ForEach(discTracks) { track in
                        Button { model.play(track, in: tracks) } label: {
                            AlbumTrackRow(track: track, isLast: track.id == discTracks.last?.id)
                        }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("album-track-\(track.id)")
                        .accessibilityLabel("Track \(track.index.map(String.init) ?? "unknown"), \(track.name), by \(track.artist)")
                        .accessibilityHint("Starts playback from this album track")
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
    }

    private var discNumbers: [Int] {
        let values = Set(tracks.map { $0.disc ?? 1 })
        return values.sorted()
    }

    private func tracksForDisc(_ disc: Int) -> [Track] { tracks.filter { ($0.disc ?? 1) == disc } }

    private var metaLine: String {
        var parts: [String] = []
        if let year = album.productionYear { parts.append(String(year)) }
        if isLoading {
            parts.append("Loading album sequence")
        } else {
            let discs = discNumbers.count
            let trackLabel = tracks.count == 1 ? "1 track" : "\(tracks.count) tracks"
            parts.append(discs > 1 ? "\(trackLabel) across \(discs) discs" : trackLabel)
            let totalSeconds = Int(tracks.reduce(0) { $0 + $1.duration }.rounded())
            if totalSeconds > 0 {
                parts.append(DetailMetrics.durationLabel(totalSeconds: totalSeconds))
            }
        }
        return parts.joined(separator: " · ")
    }
}

enum DetailMetrics {
    static let artworkSide: CGFloat = 240
    static let playDiameter: CGFloat = 56
    static let secondaryActionSide: CGFloat = 44
    static let rowArtworkSide: CGFloat = 42
    static let trackNumberWidth: CGFloat = 22

    static func durationLabel(totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        }
        return "\(minutes) min"
    }
}

private struct AlbumTrackRow: View {
    let track: Track
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            Text(track.index.map(String.init) ?? "–")
                .font(.jtCaption.monospacedDigit())
                .foregroundStyle(Color.jtTextTertiary)
                .frame(width: DetailMetrics.trackNumberWidth)
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: JellytoneTheme.Space.sm)
            if track.durationTicks != nil {
                Text(track.durationLabel)
                    .font(.jtCaption.monospacedDigit())
                    .foregroundStyle(Color.jtTextTertiary)
            }
        }
        .padding(.vertical, JellytoneTheme.Space.smPlus)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.jtBorder).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Themed state card shared by the detail screens.
func detailStateCard(title: String, detail: String, isLoading: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
        if isLoading {
            ProgressView()
                .padding(.bottom, JellytoneTheme.Space.xxs)
        }
        Text(title)
            .font(.jtRowTitle)
            .foregroundStyle(Color.jtTextPrimary)
        Text(detail)
            .font(.jtRowSubtitle)
            .foregroundStyle(Color.jtTextSecondary)
    }
    .padding(JellytoneTheme.Space.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
}

struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController
    let showPlayer: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: playback.elapsed, total: max(playback.duration, 1))
                .progressViewStyle(.linear)
                .tint(AudioDesign.accent)
            HStack(spacing: AudioDesign.Space.sm) {
                Button(action: showPlayer) {
                    HStack(spacing: AudioDesign.Space.sm) {
                        NowPlayingArtwork(playback: playback)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playback.currentTrack?.name ?? "").font(.headline).lineLimit(1)
                            Text(playback.currentTrack?.artist ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-details")
                .accessibilityLabel("Now playing \(playback.currentTrack?.name ?? "") by \(playback.currentTrack?.artist ?? "")")
                .accessibilityHint("Opens Now Playing")
                if playback.isPreparing {
                    ProgressView("Preparing playback").frame(width: 48, height: 48)
                } else {
                    AudioIconButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill", label: playback.isPlaying ? "Pause" : "Play", action: playback.toggle)
                }
                AudioIconButton(systemImage: "forward.end.fill", label: "Next track", action: playback.next)
                    .disabled(!playback.canGoNext && playback.repeatMode != .all)
            }
            .padding(.horizontal, AudioDesign.Space.md)
            .padding(.vertical, AudioDesign.Space.xs)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AudioDesign.Radius.card, style: .continuous))
        .padding(.horizontal, AudioDesign.Space.xs)
        .padding(.bottom, AudioDesign.Space.xs)
        .animation(reduceMotion ? nil : AudioDesign.Motion.quick, value: playback.isPlaying)
    }
}

struct NowPlayingView: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingQueue = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? AudioDesign.Space.md : AudioDesign.Space.lg) {
                    NowPlayingArtwork(playback: playback)
                        .frame(width: artworkSize(for: proxy.size.width), height: artworkSize(for: proxy.size.width))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(playback.currentTrack?.name ?? "Nothing playing")
                            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .title.bold()).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text(playback.currentTrack?.artist ?? "")
                            .font(.headline).foregroundStyle(.secondary).lineLimit(2)
                        Text(playback.currentTrack?.album ?? "")
                            .font(.subheadline).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(get: { playback.elapsed }, set: { playback.seek(to: $0) }),
                            in: 0...max(playback.duration, 1)
                        )
                        .tint(AudioDesign.accent)
                        .accessibilityLabel("Playback position")
                        HStack {
                            Text(time(playback.elapsed))
                            Spacer()
                            Text("−\(time(max(playback.duration - playback.elapsed, 0)))")
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }

                    HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 16) {
                        AudioIconButton(systemImage: "shuffle", label: playback.isShuffled ? "Disable shuffle" : "Enable shuffle", value: playback.isShuffled ? "On" : "Off", isActive: playback.isShuffled, action: playback.toggleShuffle)
                        AudioIconButton(systemImage: "backward.end.fill", label: "Previous track", action: playback.previous)
                            .disabled(!playback.canGoPrevious)
                        if playback.isPreparing {
                            ProgressView("Preparing playback").frame(width: 64, height: 64)
                        } else {
                            AudioIconButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill", label: playback.isPlaying ? "Pause" : "Play", kind: .primary, action: playback.toggle)
                        }
                        AudioIconButton(systemImage: "forward.end.fill", label: "Next track", action: playback.next)
                            .disabled(!playback.canGoNext && playback.repeatMode != .all)
                        AudioIconButton(systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat", label: repeatAccessibilityLabel, value: repeatAccessibilityLabel, isActive: playback.repeatMode != .off, action: playback.cycleRepeatMode)
                    }
                    .frame(maxWidth: .infinity)

                    HStack {
                        Label(playback.qualityLabel, systemImage: "waveform")
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: min(proxy.size.width - 40, 620))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .animation(reduceMotion ? nil : AudioDesign.Motion.standard, value: playback.currentTrack?.id)
                }
            }
            .audioCanvas()
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Queue", systemImage: "list.bullet") { showingQueue = true }
                        .accessibilityIdentifier("show-queue")
                        .accessibilityHint("Shows the current queue")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
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

    private func artworkSize(for availableWidth: CGFloat) -> CGFloat {
        if availableWidth > 700 {
            return min(availableWidth * 0.38, 300)
        }
        return min(availableWidth - 48, 560)
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
                            .listRowBackground(AudioDesign.accent.opacity(0.14))
                            .accessibilityHint("Currently playing. This track cannot be removed.")
                    }
                }
                Section("Up Next") {
                    if playback.upcomingEntries.isEmpty {
                        AudioStateView(kind: .empty, title: "Nothing Up Next", detail: "The current track will keep playing.")
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
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
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                if !playback.upcomingEntries.isEmpty {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        EditButton()
                        Button("Clear Up Next") { playback.clearUpNext() }
                            .accessibilityHint("Keeps the current track playing")
                    }
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
                .foregroundStyle(isCurrent ? AudioDesign.accent : .secondary)
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
