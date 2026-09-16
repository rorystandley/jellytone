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
            await model.refreshFavouriteStatus(ids: [album.id] + tracks.map(\.id))
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
            albumArtistLabel
            Text(metaLine)
                .font(.jtCaption)
                .foregroundStyle(Color.jtTextTertiary)
            // Secondary bare-glyph actions grouped tightly; the filled play
            // circle sits apart. The tighter inner gap compensates for the
            // glyphs' frame padding so every optical gap reads even.
            HStack(spacing: JellytoneTheme.Space.xl) {
                // The album like persists independently of playback, so it stays
                // enabled while tracks are still loading.
                FavouriteHeartButton(itemID: album.id, identifierPrefix: "album")
                Spacer()
                Group {
                    HStack(spacing: JellytoneTheme.Space.md) {
                        DownloadStatusButton(
                            downloads: model.downloads,
                            tracks: tracks,
                            container: albumContainer,
                            identifierPrefix: "album"
                        )
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
                    }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prefer the album's own artist ID; if the album came from a name-only
    /// path (older cache / track→album), fall back once tracks load.
    private var resolvedArtistDestination: Artist? {
        album.artistDestination
            ?? tracks.first(where: { $0.artist == album.artist })?.artistDestination
            ?? tracks.compactMap(\.artistDestination).first
    }

    @ViewBuilder private var albumArtistLabel: some View {
        if let artist = resolvedArtistDestination {
            NavigationLink(value: artist) {
                Text(artist.name)
                    .font(.jtBody.weight(.medium))
                    .foregroundStyle(Color.jtTextSecondary)
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("album-artist")
            .accessibilityHint("Opens this artist")
        } else {
            Text(album.artist)
                .font(.jtBody.weight(.medium))
                .foregroundStyle(Color.jtTextSecondary)
        }
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
                            AlbumTrackRow(track: track, isLast: track.id == discTracks.last?.id,
                                          downloads: model.downloads)
                        }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("album-track-\(track.id)")
                        .accessibilityLabel("Track \(track.index.map(String.init) ?? "unknown"), \(track.name), by \(track.artist)")
                        .accessibilityHint("Starts playback from this album track")
                        .contextMenu {
                            let liked = model.isFavourite(track.id)
                            Button(liked ? "Unfavourite" : "Favourite",
                                   systemImage: liked ? "heart.slash" : "heart") {
                                model.toggleFavourite(id: track.id)
                            }
                            Button("Play Next", systemImage: "text.insert") { model.playNext(track) }
                                .disabled(model.playback.currentTrack == nil)
                            Button("Add to Queue", systemImage: "text.badge.plus") { model.addToQueue(track) }
                                .disabled(model.playback.currentTrack == nil)
                            if model.downloads.isDownloaded(track.id) {
                                Button("Remove Download", systemImage: "trash") {
                                    Task { await model.downloads.remove(track.id) }
                                }
                            } else {
                                Button("Download", systemImage: "arrow.down.circle") {
                                    model.downloads.download([track], container: albumContainer)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var albumContainer: DownloadContainer {
        DownloadContainer(kind: .album, id: album.id, name: album.name)
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
    @ObservedObject var downloads: DownloadManager

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
            TrackDownloadIndicator(downloads: downloads, trackID: track.id)
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

/// Pre-iOS 26 fallback mini player (design-system.md §4.4). iOS 26 uses
/// Pre-iOS 26 fallback mini player. On iOS 26+ the system accessory in
/// `MusicShellView` is used instead. Preparing is silent — play stays tappable.
struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController
    var expansionNamespace: Namespace.ID
    let showPlayer: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: playback.elapsed, total: max(playback.duration, 1))
                .progressViewStyle(.linear)
                .tint(Color.jtAccent)
                .frame(height: JellytoneTheme.Player.miniProgressHeight)
            HStack(spacing: JellytoneTheme.Space.smPlus) {
                Button(action: showPlayer) {
                    HStack(spacing: JellytoneTheme.Space.smPlus) {
                        NowPlayingArtwork(playback: playback, cornerRadius: JellytoneTheme.Radius.rowArtwork)
                            .frame(width: JellytoneTheme.Player.miniArtwork, height: JellytoneTheme.Player.miniArtwork)
                        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                            Text(playback.currentTrack?.name ?? "")
                                .font(.jtRowTitle)
                                .foregroundStyle(Color.jtTextPrimary)
                                .lineLimit(1)
                            Text(playback.currentTrack?.artist ?? "")
                                .font(.jtCaption)
                                .foregroundStyle(Color.jtTextSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-details")
                .accessibilityLabel("Now playing \(playback.currentTrack?.name ?? "") by \(playback.currentTrack?.artist ?? "")")
                .accessibilityHint("Opens Now Playing")
                .matchedTransitionSource(id: PlayerExpansion.sourceID, in: expansionNamespace)

                if playback.isPreparing {
                    PlayerPreparingIndicator(style: .mini)
                }

                JellytoneTransportButton(
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                    label: playback.isPlaying ? "Pause" : "Play",
                    kind: .compact,
                    action: playback.toggle
                )
                .accessibilityHint(playback.isPreparing ? "Preparing playback" : "")

                JellytoneTransportButton(
                    systemImage: "forward.end.fill",
                    label: "Next track",
                    kind: .compact,
                    action: playback.next
                )
                .disabled(!playback.canGoNext && playback.repeatMode != .all)
                .opacity((!playback.canGoNext && playback.repeatMode != .all) ? 0.4 : 1)
            }
            .padding(.horizontal, JellytoneTheme.Space.lg)
            .padding(.vertical, JellytoneTheme.Space.xs)
        }
        .jtGlassMiniPlayer()
        .padding(.horizontal, JellytoneTheme.Player.miniHorizontalInset)
        .padding(.bottom, JellytoneTheme.Player.miniBottomInset)
        .animation(reduceMotion ? nil : JellytoneTheme.Motion.quick, value: playback.isPlaying)
        .animation(reduceMotion ? nil : JellytoneTheme.Motion.quick, value: playback.isPreparing)
    }
}

/// Full-screen Now Playing — continuous expansion target for the mini player
/// (zoom transition + shared materials family). Silent buffering: transport and
/// chrome stay usable while a track prepares (AGENTS.md Priority 2). Album and
/// artist names push the specific library items when Jellyfin gave us their IDs.
struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingQueue = false
    @State private var lyrics: TrackLyrics?
    @State private var showingLyrics = false
    @State private var isScrubbing = false
    @State private var lastScrubTick = -1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? JellytoneTheme.Space.md : JellytoneTheme.Space.xl) {
                        let artSide = artworkSize(for: proxy.size.width)
                        if artSide > 0 {
                            if showingLyrics, let lyrics {
                                LyricsView(lyrics: lyrics, playback: playback)
                                    .frame(height: artSide)
                                    .frame(maxWidth: .infinity)
                            } else {
                                NowPlayingArtwork(playback: playback)
                                    .frame(width: artSide, height: artSide)
                                    .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
                            }
                        }

                        HStack(alignment: .top, spacing: JellytoneTheme.Space.md) {
                            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
                                Text(playback.currentTrack?.name ?? "Nothing playing")
                                    .font(dynamicTypeSize.isAccessibilitySize ? .jtDetailTitle : .jtNowPlayingTitle)
                                    .foregroundStyle(Color.jtTextPrimary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                nowPlayingArtistLabel
                                nowPlayingAlbumLabel
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let trackID = playback.currentTrack?.id {
                                FavouriteHeartButton(itemID: trackID, font: .jtSubsectionHeader, identifierPrefix: "now-playing")
                            }
                        }

                        VStack(spacing: JellytoneTheme.Space.xxs) {
                            Slider(
                                value: Binding(get: { playback.elapsed }, set: { playback.seek(to: $0) }),
                                in: 0...max(playback.duration, 1),
                                onEditingChanged: { editing in
                                    if editing {
                                        JellytoneHaptics.prepare(.selection)
                                        isScrubbing = true
                                        lastScrubTick = Int(playback.elapsed)
                                        JellytoneHaptics.scrubTick()
                                    } else {
                                        isScrubbing = false
                                        lastScrubTick = -1
                                    }
                                }
                            )
                            // Scrub fill is white on the dark NP canvas (design-system.md §4.5).
                            .tint(Color.jtTextPrimary)
                            .accessibilityLabel("Playback position")
                            .onChange(of: playback.elapsed) { _, elapsed in
                                guard isScrubbing else { return }
                                let tick = Int(elapsed)
                                guard tick != lastScrubTick else { return }
                                lastScrubTick = tick
                                JellytoneHaptics.scrubTick()
                            }
                            HStack {
                                Text(time(playback.elapsed))
                                Spacer()
                                Text("−\(time(max(playback.duration - playback.elapsed, 0)))")
                            }
                            .font(.jtCaption.monospacedDigit())
                            .foregroundStyle(Color.jtTextTertiary)
                        }

                        // Transport always remains interactive during prepare/buffer —
                        // no spinner takeover of the primary control.
                        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? JellytoneTheme.Space.sm : JellytoneTheme.Space.lg) {
                            JellytoneTransportButton(
                                systemImage: "shuffle",
                                label: playback.isShuffled ? "Disable shuffle" : "Enable shuffle",
                                value: playback.isShuffled ? "On" : "Off",
                                kind: .secondary,
                                isActive: playback.isShuffled,
                                action: playback.toggleShuffle
                            )
                            JellytoneTransportButton(
                                systemImage: "backward.end.fill",
                                label: "Previous track",
                                kind: .secondary,
                                action: playback.previous
                            )
                            .disabled(!playback.canGoPrevious)
                            .opacity(playback.canGoPrevious ? 1 : 0.4)
                            JellytoneTransportButton(
                                systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                                label: playback.isPlaying ? "Pause" : "Play",
                                kind: .primary,
                                action: playback.toggle
                            )
                            .accessibilityHint(playback.isPreparing ? "Preparing playback" : "")
                            .opacity(playback.isPreparing ? 0.92 : 1)
                            JellytoneTransportButton(
                                systemImage: "forward.end.fill",
                                label: "Next track",
                                kind: .secondary,
                                action: playback.next
                            )
                            .disabled(!playback.canGoNext && playback.repeatMode != .all)
                            .opacity((!playback.canGoNext && playback.repeatMode != .all) ? 0.4 : 1)
                            JellytoneTransportButton(
                                systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat",
                                label: repeatAccessibilityLabel,
                                value: repeatAccessibilityLabel,
                                kind: .secondary,
                                isActive: playback.repeatMode != .off,
                                action: playback.cycleRepeatMode
                            )
                        }
                        .frame(maxWidth: .infinity)

                        // Footer: quality (+ silent prep) · lyrics · queue — one chrome family.
                        HStack(spacing: JellytoneTheme.Space.md) {
                            HStack(spacing: JellytoneTheme.Space.sm) {
                                if playback.isPreparing {
                                    PlayerPreparingIndicator(style: .footer)
                                }
                                if !footerQualityLabel.isEmpty {
                                    Label(footerQualityLabel, systemImage: "waveform")
                                        .font(.jtCaption)
                                        .foregroundStyle(Color.jtTextTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .accessibilityElement(children: .combine)

                            Spacer(minLength: JellytoneTheme.Space.sm)

                            if lyrics != nil {
                                Button {
                                    JellytoneHaptics.play(.light)
                                    withAnimation(reduceMotion ? nil : JellytoneTheme.Motion.crossfade) {
                                        showingLyrics.toggle()
                                    }
                                } label: {
                                    Text("Lyrics")
                                        .font(.jtCaption.weight(.bold))
                                        .foregroundStyle(showingLyrics ? Color.jtAccent : Color.jtTextSecondary)
                                }
                                .accessibilityIdentifier("now-playing-lyrics-toggle")
                                .accessibilityLabel(showingLyrics ? "Hide lyrics" : "Show lyrics")
                            }

                            Button {
                                JellytoneHaptics.play(.light)
                                showingQueue = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: JellytoneTheme.Player.transportIcon, weight: .semibold))
                                    .foregroundStyle(Color.jtTextSecondary)
                                    .frame(width: JellytoneTheme.Player.miniTransport, height: JellytoneTheme.Player.miniTransport)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                            .accessibilityIdentifier("show-queue")
                            .accessibilityLabel("Queue")
                            .accessibilityHint("Shows the current queue")
                        }
                    }
                    .frame(maxWidth: min(proxy.size.width - (JellytoneTheme.Space.screenMargin * 2), 620))
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    .padding(.vertical, JellytoneTheme.Space.lg)
                    .animation(reduceMotion ? nil : JellytoneTheme.Motion.standard, value: playback.currentTrack?.id)
                    .animation(reduceMotion ? nil : JellytoneTheme.Motion.quick, value: playback.isPreparing)
                }
            }
            .task(id: playback.currentTrack?.id) {
                // New track: drop the previous track's lyrics view, then fetch.
                showingLyrics = false
                lyrics = nil
                guard let track = playback.currentTrack else { return }
                await model.refreshFavouriteStatus(ids: [track.id])
                lyrics = await model.lyrics(for: track)
            }
            // Artwork-derived wash, kept dark always (design-system.md §4.5).
            .background(JellytoneDetailBackdrop(tint: .black) { backdropArtwork })
            .tint(Color.jtAccent)
            .toolbarBackground(.hidden, for: .navigationBar)
            // Keep a stable "Now Playing" title for a11y / UI tests; album sits in the metadata block.
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Chevron-down close matches Apple Music / design-system §4.5.
                // Queue lives in the footer with lyrics/quality (same component family).
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        JellytoneHaptics.play(.soft)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.jtCaption.weight(.semibold))
                            .foregroundStyle(Color.jtTextPrimary)
                            .frame(width: JellytoneTheme.Player.miniTransport, height: JellytoneTheme.Player.miniTransport)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
                    .accessibilityLabel("Close")
                    .accessibilityHint("Dismisses Now Playing")
                }
            }
            // Queue and album/artist destinations live at this stack root so
            // ArtistView's album grid resolves instead of re-pushing Now Playing
            // (same pattern as Library / Search — AGENTS.md).
            .navigationDestination(isPresented: $showingQueue) {
                PlaybackQueueView(playback: playback)
            }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
        }
        // Now Playing is dark regardless of the app's light/dark setting, so
        // its adaptive text/controls resolve to their dark (light-coloured)
        // variants over the artwork wash.
        .preferredColorScheme(.dark)
        // Full-height sheet that still supports interactive swipe-to-dismiss back
        // to the mini player; drag indicator reinforces the continuous surface.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(false)
    }

    /// Prefer real quality tags; de-emphasize loud preparing copy in the footer
    /// (spinner carries the state). Empty string hides the label while preparing
    /// if the controller still says "Preparing…".
    private var footerQualityLabel: String {
        let label = playback.qualityLabel
        if playback.isPreparing, label == "Preparing…" || label == "Buffering…" {
            return ""
        }
        return label
    }

    @ViewBuilder private var backdropArtwork: some View {
        if let image = playback.artwork {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let track = playback.currentTrack {
            JellytoneTheme.placeholderGradient(hue: JellytoneTheme.placeholderHue(forID: track.id))
        } else {
            Color.black
        }
    }

    @ViewBuilder private var nowPlayingArtistLabel: some View {
        let name = playback.currentTrack?.artist ?? ""
        if let artist = playback.currentTrack?.artistDestination {
            NowPlayingLibraryLink(
                value: artist,
                title: artist.name,
                font: .jtBody.weight(.medium),
                color: Color.jtTextSecondary,
                identifier: "now-playing-artist",
                hint: "Opens this artist"
            )
        } else {
            Text(name)
                .font(.jtBody.weight(.medium))
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder private var nowPlayingAlbumLabel: some View {
        let name = playback.currentTrack?.album ?? ""
        if let album = playback.currentTrack?.albumDestination {
            NowPlayingLibraryLink(
                value: album,
                title: album.name,
                font: .jtRowSubtitle,
                color: Color.jtTextTertiary,
                identifier: "now-playing-album",
                hint: "Opens this album"
            )
        } else {
            Text(name)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextTertiary)
                .lineLimit(2)
        }
    }

    private var repeatAccessibilityLabel: String {
        switch playback.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat queue"
        case .one: "Repeat one"
        }
    }

    private func artworkSize(for availableWidth: CGFloat) -> CGFloat {
        // GeometryReader can report 0 during the zoom expand; avoid negative frames.
        guard availableWidth.isFinite, availableWidth > 1 else { return 0 }
        if availableWidth > 700 {
            return min(availableWidth * 0.38, JellytoneTheme.Player.nowPlayingArtworkMax + 10)
        }
        return max(0, min(availableWidth - JellytoneTheme.Space.xxxl * 1.5, 560))
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Tappable album/artist name on Now Playing. Keeps the metadata type colour
/// (never an accent "link") and uses press-scale as the only affordance.
private struct NowPlayingLibraryLink<Value: Hashable>: View {
    let value: Value
    let title: String
    let font: Font
    let color: Color
    let identifier: String
    let hint: String

    var body: some View {
        NavigationLink(value: value) {
            Text(title)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
        .accessibilityIdentifier(identifier)
        .accessibilityHint(hint)
    }
}

/// Lyrics panel shown in place of the artwork. Synced lyrics highlight the
/// active line (accent) and dim the rest, auto-scrolling to keep it centred;
/// unsynced lyrics are a plain scroll. Jellyfin provides at most per-line
/// timing, so the design spec's word-by-word karaoke isn't achievable — line
/// level is the honest equivalent.
private struct LyricsView: View {
    let lyrics: TrackLyrics
    @ObservedObject var playback: PlaybackController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeIndex: Int? {
        lyrics.activeIndex(at: playback.elapsed)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.md) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.jtSubsectionHeader)
                            .foregroundStyle(color(for: line.index))
                            .scaleEffect(scale(for: line.index))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.index)
                    }
                }
                .padding(.vertical, JellytoneTheme.Space.lg)
            }
            .onChange(of: activeIndex) { _, index in
                guard let index else { return }
                withAnimation(reduceMotion ? nil : JellytoneTheme.Motion.crossfade) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .accessibilityLabel("Lyrics")
    }

    private func color(for index: Int) -> Color {
        guard lyrics.isSynced, let activeIndex else { return Color.jtTextPrimary.opacity(0.85) }
        if index == activeIndex { return .jtAccent }
        return index < activeIndex ? Color.jtTextPrimary.opacity(0.7) : Color.jtTextPrimary.opacity(0.4)
    }

    private func scale(for index: Int) -> CGFloat {
        guard lyrics.isSynced, let activeIndex, index == activeIndex else { return 1 }
        return 1.04
    }
}

/// Queue as a push destination inside Now Playing's stack — same design language,
/// back-chevron return (no nested sheet-on-sheet).
private struct PlaybackQueueView: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        List {
            if let current = playback.currentTrack {
                Section {
                    QueueTrackRow(track: current, isCurrent: true)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.compactArtwork, style: .continuous)
                                .fill(Color.jtAccentDim)
                                .padding(.vertical, JellytoneTheme.Space.xxs)
                        )
                        .accessibilityHint("Currently playing. This track cannot be removed.")
                } header: {
                    Text("Now Playing")
                        .font(.jtCaption)
                        .foregroundStyle(Color.jtTextTertiary)
                        .textCase(.uppercase)
                }
            }
            Section {
                if playback.upcomingEntries.isEmpty {
                    JellytoneStateCard(
                        kind: .empty,
                        title: "Nothing Up Next",
                        detail: "The current track will keep playing."
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: JellytoneTheme.Space.sm,
                        leading: JellytoneTheme.Space.screenMargin,
                        bottom: JellytoneTheme.Space.sm,
                        trailing: JellytoneTheme.Space.screenMargin
                    ))
                } else {
                    ForEach(playback.upcomingEntries) { entry in
                        Button {
                            JellytoneHaptics.transport()
                            playback.jump(to: entry.id)
                        } label: {
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
                            JellytoneHaptics.destructive()
                            playback.removeUpcoming(entryIDs: [entry.id])
                        }
                    }
                    .onMove(perform: playback.moveUpcoming)
                    .onDelete { offsets in
                        JellytoneHaptics.destructive()
                        playback.removeUpcoming(atOffsets: offsets)
                    }
                }
            } header: {
                Text("Up Next")
                    .font(.jtCaption)
                    .foregroundStyle(Color.jtTextTertiary)
                    .textCase(.uppercase)
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.jtBackground)
        .tint(Color.jtAccent)
        .toolbar {
            if !playback.upcomingEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear Up Next") {
                        JellytoneHaptics.destructive()
                        playback.clearUpNext()
                    }
                        .accessibilityHint("Keeps the current track playing")
                }
            }
        }
    }
}

private struct QueueTrackRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .center, spacing: JellytoneTheme.Space.md) {
            Image(systemName: isCurrent ? "waveform" : "music.note")
                .font(.jtRowTitle)
                .frame(width: 24)
                .foregroundStyle(isCurrent ? Color.jtAccent : Color.jtTextSecondary)
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.durationLabel)
                .font(.jtCaption.monospacedDigit())
                .foregroundStyle(Color.jtTextTertiary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
