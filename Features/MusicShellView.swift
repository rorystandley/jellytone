import SwiftUI

struct MusicShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPlayer = false

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
                        MiniPlayerAccessoryView(playback: model.playback) { showingPlayer = true }
                    }
            } else {
                tabs.safeAreaInset(edge: .bottom, spacing: 0) { legacyMiniPlayer }
            }
        }
        .tint(Color.jtAccent)
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(playback: model.playback)
                .environmentObject(model)
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
            MiniPlayerView(playback: model.playback) { showingPlayer = true }
        }
    }
}

/// Content of the tab bar's bottom accessory. Mirrors Apple Music: artwork
/// thumb + title ("Not Playing" when idle) + play/pause + skip. In the inline
/// (minimized tab bar) placement the skip button is dropped to fit.
@available(iOS 26.0, *)
private struct MiniPlayerAccessoryView: View {
    @ObservedObject var playback: PlaybackController
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

            if playback.isPreparing {
                ProgressView()
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("Preparing playback")
            } else {
                transportButton(
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                    label: playback.isPlaying ? "Pause" : "Play",
                    action: playback.toggle
                )
                .disabled(playback.currentTrack == nil)
            }
            if placement != .inline {
                transportButton(systemImage: "forward.fill", label: "Next track", action: playback.next)
                    .disabled(playback.currentTrack == nil || (!playback.canGoNext && playback.repeatMode != .all))
            }
        }
        .padding(.horizontal, JellytoneTheme.Space.mdPlus)
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.jtTextPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
        .accessibilityLabel(label)
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
