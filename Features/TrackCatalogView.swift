import SwiftUI

struct TrackCatalogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        content
            .navigationTitle("Tracks")
            .audioCanvas()
            .accessibilityIdentifier("library-tracks-screen")
            .refreshable { await model.refreshTrackCatalog() }
            .task(id: model.selectedLibraryID) { await model.refreshTrackCatalog() }
    }

    @ViewBuilder private var content: some View {
        let state = model.trackCatalogState
        if state.isLoading && state.occurrences.isEmpty {
            AudioStateView(kind: .loading, title: "Loading tracks", detail: "Fetching the playable catalogue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else if let error = state.errorMessage, state.occurrences.isEmpty {
            AudioStateView(kind: .error, title: "Couldn’t load tracks", detail: error,
                           actionTitle: "Try Again") { Task { await model.refreshTrackCatalog() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else if state.hasLoaded && state.occurrences.isEmpty {
            AudioStateView(kind: .empty, title: "No tracks found",
                           detail: "This music library has no playable audio tracks.")
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else {
            AudioBrowseContainer(spacing: AudioDesign.Space.md) {
                AudioSectionHeading(title: "All Tracks", detail: "\(state.occurrences.count) loaded · Jellyfin catalogue order")
                if state.isLoading { ProgressView("Refreshing tracks…").frame(maxWidth: .infinity) }
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                        trackRow(occurrence, position: index + 1, total: state.occurrences.count)
                            .task {
                                if index == state.occurrences.indices.last { await model.loadMoreTrackCatalog() }
                            }
                        Divider()
                    }
                }
                .padding(.horizontal, AudioDesign.Space.sm)
                .audioElevatedSurface(cornerRadius: AudioDesign.Radius.compact)
                AudioPaginationView(isLoading: state.isLoadingMore, message: state.paginationError,
                                    loadingTitle: "Loading more tracks…", retryTitle: "Retry More Tracks",
                                    identifier: "track-catalog-retry-more") {
                    Task { await model.loadMoreTrackCatalog() }
                }
            }
        }
    }

    private func trackRow(_ occurrence: TrackCatalogOccurrence, position: Int, total: Int) -> some View {
        let track = occurrence.track
        return Button { model.play(occurrence, in: model.trackCatalogState.occurrences) } label: {
            AudioTrackRow(position: nil, title: track.name, artist: track.artist, album: track.album,
                          duration: track.durationTicks == nil ? nil : track.durationLabel,
                          showsArtwork: true, artworkItemID: track.id, artworkImageTag: track.imageTag)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("track-catalog-row-\(occurrence.id)")
        .accessibilityLabel("\(track.name), by \(track.artist)\(track.album.isEmpty ? "" : ", album \(track.album)")")
        .accessibilityValue("Track \(position) of \(total)")
        .accessibilityHint("Starts playback at this displayed track")
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") { model.playNext(track) }
            Button("Add to Queue", systemImage: "text.badge.plus") { model.addToQueue(track) }
            if let albumID = track.albumID, !track.album.isEmpty {
                NavigationLink("Go to Album", destination: AlbumView(album: Album(id: albumID, name: track.album, artist: track.artist, productionYear: nil, imageTag: track.imageTag)))
            }
            if let artistID = track.artistID, !track.artist.isEmpty {
                NavigationLink("Go to Artist", destination: ArtistView(artist: Artist(id: artistID, name: track.artist, imageTag: nil)))
            }
        }
    }
}
