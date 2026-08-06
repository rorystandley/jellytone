import SwiftUI

/// Shared transition identity for MiniPlayer → Now Playing expansion.
/// Used with `matchedTransitionSource` / `navigationTransition(.zoom)` so the
/// full player morphs from the tab accessory (or legacy mini player) instead of
/// appearing as a disconnected sheet.
enum PlayerExpansion {
    static let sourceID = "now-playing"
}

struct MusicShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPlayer = false
    @Namespace private var playerExpansion

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Apple Music-style chrome: the tab bar collapses to the active
                // tab on scroll-down and the mini player morphs into the inline
                // slot beside it; tapping the collapsed tab expands it back.
                // The system draws the glass capsule around the accessory.
                tabs
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        MiniPlayerAccessoryView(
                            playback: model.playback,
                            expansionNamespace: playerExpansion
                        ) {
                            showingPlayer = true
                        }
                    }
            } else {
                tabs.safeAreaInset(edge: .bottom, spacing: 0) { legacyMiniPlayer }
            }
        }
        .tint(Color.jtAccent)
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(playback: model.playback)
                .environmentObject(model)
                // Continuous expand/collapse with the mini player source.
                .navigationTransition(.zoom(sourceID: PlayerExpansion.sourceID, in: playerExpansion))
        }
    }

    private var tabs: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    HomeLibraryView()
                        // All Home navigation is value-based and resolves through
                        // the destinations registered here at the stack root, so a
                        // value-based link inside a pushed screen (ArtistView's
                        // album grid) resolves cleanly — mixing view-based
                        // NavigationLinks in the shelves re-pushed the artist when
                        // the lazy shelves re-rendered on a child push.
                        .navigationDestination(for: Album.self) { AlbumView(album: $0) }
                        .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
                        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
                }
            }
            Tab("Library", systemImage: "square.stack.fill") {
                LibraryView()
            }
            Tab("Downloads", systemImage: "arrow.down.circle") {
                DownloadsView()
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
    }

    @ViewBuilder
    private var legacyMiniPlayer: some View {
        if model.playback.currentTrack != nil {
            MiniPlayerView(
                playback: model.playback,
                expansionNamespace: playerExpansion
            ) {
                showingPlayer = true
            }
        }
    }
}

/// Content of the tab bar's bottom accessory. Mirrors Apple Music: artwork
/// thumb + title ("Not Playing" when idle) + play/pause + skip. In the inline
/// (minimized tab bar) placement the skip button is dropped to fit.
/// Preparing is silent: transport stays available; a mini activity indicator
/// sits beside play without replacing it (AGENTS.md Priority 2).
@available(iOS 26.0, *)
private struct MiniPlayerAccessoryView: View {
    @ObservedObject var playback: PlaybackController
    var expansionNamespace: Namespace.ID
    let showPlayer: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.smPlus) {
            Button {
                if playback.currentTrack != nil { showPlayer() }
            } label: {
                HStack(spacing: JellytoneTheme.Space.smPlus) {
                    artworkThumb
                    Text(playback.currentTrack?.name ?? "Not Playing")
                        .font(.jtRowTitle)
                        .foregroundStyle(playback.currentTrack == nil ? Color.jtTextSecondary : Color.jtTextPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mini-player-details")
            .accessibilityLabel(
                playback.currentTrack.map { "Now playing \($0.name) by \($0.artist)" } ?? "Not playing"
            )
            .accessibilityHint(playback.currentTrack == nil ? "" : "Opens Now Playing")
            .matchedTransitionSource(id: PlayerExpansion.sourceID, in: expansionNamespace)

            if playback.isPreparing {
                PlayerPreparingIndicator(style: .mini)
            }

            transportButton(
                systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                label: playback.isPlaying ? "Pause" : "Play",
                action: playback.toggle
            )
            .disabled(playback.currentTrack == nil)
            .accessibilityHint(playback.isPreparing ? "Preparing playback" : "")

            if placement != .inline {
                transportButton(systemImage: "forward.fill", label: "Next track", action: playback.next)
                    .disabled(playback.currentTrack == nil || (!playback.canGoNext && playback.repeatMode != .all))
            }
        }
        .padding(.horizontal, JellytoneTheme.Space.mdPlus)
        .animation(JellytoneTheme.Motion.quick, value: playback.isPreparing)
    }

    @ViewBuilder private var artworkThumb: some View {
        Group {
            if let image = playback.artwork {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.jtSurface
                    Image(systemName: "music.note")
                        .font(.jtRowTitle)
                        .foregroundStyle(Color.jtTextSecondary)
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.rowArtwork, style: .continuous))
        .accessibilityHidden(true)
    }

    private func transportButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: JellytoneTheme.Player.accessoryTransportIcon, weight: .semibold))
                .foregroundStyle(Color.jtTextPrimary)
                .frame(width: JellytoneTheme.Player.miniTransport, height: JellytoneTheme.Player.miniTransport)
                .contentShape(Rectangle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
        .accessibilityLabel(label)
    }
}

/// Shared artwork for Mini Player and Now Playing. Uses the themed local
/// artwork component (gradient placeholder, never grey).
struct NowPlayingArtwork: View {
    @ObservedObject var playback: PlaybackController
    var cornerRadius: CGFloat = JellytoneTheme.Radius.largeArtwork

    var body: some View {
        JellytoneLocalArtwork(
            image: playback.artwork,
            label: playback.currentTrack?.name ?? "current track",
            itemID: playback.currentTrack?.id,
            cornerRadius: cornerRadius
        )
    }
}

/// Subtle preparing/buffering chrome. Never replaces transport — keeps
/// artwork, title, and controls fully interactive (Priority 2 silent prep).
struct PlayerPreparingIndicator: View {
    enum Style {
        /// Compact spinner for mini player / accessory.
        case mini
        /// Inline with quality footer on Now Playing.
        case footer
    }

    var style: Style = .footer

    var body: some View {
        ProgressView()
            .controlSize(style == .mini ? .mini : .small)
            .tint(Color.jtTextTertiary)
            // Explicit element so VoiceOver / UI tests can find preparing state
            // without a blocking “Preparing playback” spinner takeover.
            .accessibilityElement()
            .accessibilityLabel("Preparing playback")
            .accessibilityIdentifier("preparing-playback")
            .accessibilityAddTraits(.updatesFrequently)
    }
}
