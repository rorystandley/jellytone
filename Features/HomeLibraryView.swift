import SwiftUI

/// Cache-first Home presentation. `AppModel` owns the scoped snapshot and every
/// playback transition; this view never creates a competing queue.
struct HomeLibraryView<AlbumDestination: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var model: AppModel

    let albumDestination: (Album) -> AlbumDestination

    var body: some View {
        content
            .navigationTitle("Home")
            .accessibilityIdentifier("home-screen")
            .task { await model.refreshHomeShelves() }
            .refreshable { await model.refreshHomeShelves() }
            .overlay(alignment: .top) {
                if model.isRefreshingHome && hasContent {
                    ProgressView("Refreshing Home…")
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .accessibilityIdentifier("home-refreshing")
                }
            }
    }

    private var hasContent: Bool {
        model.playback.currentTrack != nil
            || !(model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true)
            || !(model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true)
    }

    @ViewBuilder private var content: some View {
        if !hasContent, let error = model.homeRefreshError {
            ContentUnavailableView {
                Label("Couldn’t load Home", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: { retryButton }
        } else if !hasContent, !model.isRefreshingHome, model.homeSnapshot != nil {
            ContentUnavailableView(
                "Nothing recent yet",
                systemImage: "music.note.list",
                description: Text("Recently added albums and recently played music will appear here."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    continueListening
                    recentlyAddedSection
                    recentlyPlayedSection
                    if hasContent, let error = model.homeRefreshError { partialFailure(message: error) }
                }
                .padding()
            }
        }
    }

    @ViewBuilder private var continueListening: some View {
        if let current = model.playback.currentTrack {
            Button { model.playback.toggle() } label: {
                HStack(spacing: 16) {
                    NowPlayingArtwork(playback: model.playback)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue Listening")
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
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home-continue-listening")
            .accessibilityLabel("Continue listening to \(current.name) by \(current.artist)")
            .accessibilityHint(model.playback.isPlaying ? "Pauses playback" : "Resumes playback")
        }
    }

    @ViewBuilder private var recentlyAddedSection: some View {
        heading("Recently Added", image: "clock.arrow.circlepath")
        if model.isRefreshingHome && (model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true) {
            loading("Loading recently added albums…")
        } else if model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true {
            empty("No recently added albums", detail: "New albums in this music library will appear here.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(model.homeSnapshot?.recentlyAddedAlbums ?? []) { album in
                        NavigationLink { albumDestination(album) } label: { HomeAlbumCard(album: album) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home-recently-added-album-\(album.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private var recentlyPlayedSection: some View {
        heading("Recently Played", image: "clock")
        if model.isRefreshingHome && (model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true) {
            loading("Loading recently played music…")
        } else if model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true {
            empty("No recently played music", detail: "Music you play in Jellyfin will appear here.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array((model.homeSnapshot?.recentlyPlayedTracks ?? []).enumerated()), id: \.element.id) { index, track in
                    Button { model.play(track, in: model.homeSnapshot?.recentlyPlayedTracks ?? []) } label: {
                        HomeTrackRow(position: index + 1, track: track)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("home-recently-played-track-\(track.id)")
                    .accessibilityLabel("\(track.name), \(track.artist)")
                    .accessibilityHint("Starts playback from this recently played track")
                    Divider()
                }
            }
        }
    }

    private var retryButton: some View {
        Button("Try Again") { Task { await model.refreshHomeShelves() } }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home-retry")
    }

    private func heading(_ title: String, image: String) -> some View {
        Label(title, systemImage: image)
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private func loading(_ title: String) -> some View {
        HStack { Spacer(); ProgressView(title); Spacer() }.frame(minHeight: 72)
    }

    private func empty(_ title: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: "music.note", description: Text(detail))
            .frame(maxWidth: .infinity)
    }

    private func partialFailure(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Some recent music couldn’t be refreshed", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            retryButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-partial-failure")
    }

}

private struct HomeAlbumCard: View {
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            homeArtwork(for: album)
                .frame(width: 156, height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(album.name).font(.headline).lineLimit(2)
            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), \(album.artist), recently added album")
        .accessibilityHint("Opens album")
    }
}

@MainActor @ViewBuilder
private func homeArtwork(for album: Album) -> some View {
    if album.imageTag != nil {
        AuthenticatedArtworkView(itemID: album.id, accessibilityLabel: "Artwork for \(album.name)")
    } else {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
        }
        .accessibilityLabel("No artwork for \(album.name)")
    }
}

private struct HomeTrackRow: View {
    let position: Int
    let track: Track
    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)").foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).foregroundStyle(.primary).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
