import SwiftUI

struct TrackCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            .navigationTitle("Tracks")
            .accessibilityIdentifier("library-tracks-screen")
            .refreshable { await model.refreshTrackCatalog() }
            .task(id: model.selectedLibraryID) { await model.refreshTrackCatalog() }
    }

    @ViewBuilder private var content: some View {
        let state = model.trackCatalogState
        if state.isLoading && state.occurrences.isEmpty {
            ProgressView("Loading tracks…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.errorMessage, state.occurrences.isEmpty {
            ContentUnavailableView {
                Label("Couldn’t load tracks", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("Try Again") { Task { await model.refreshTrackCatalog() } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
        } else if state.hasLoaded && state.occurrences.isEmpty {
            ContentUnavailableView("No tracks found", systemImage: "music.note.slash",
                                   description: Text("This music library has no playable audio tracks."))
        } else {
            List {
                if state.isLoading { Section { ProgressView("Refreshing tracks…") } }
                ForEach(Array(state.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                    trackRow(occurrence, position: index + 1, total: state.occurrences.count)
                        .task {
                            if index == state.occurrences.indices.last { await model.loadMoreTrackCatalog() }
                        }
                }
                if state.isLoadingMore {
                    ProgressView("Loading more tracks…").frame(maxWidth: .infinity).listRowSeparator(.hidden)
                } else if let error = state.paginationError {
                    HStack { Text(error).foregroundStyle(.secondary); Spacer(); Button("Retry") { Task { await model.loadMoreTrackCatalog() } } }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func trackRow(_ occurrence: TrackCatalogOccurrence, position: Int, total: Int) -> some View {
        let track = occurrence.track
        return Button { model.play(occurrence, in: model.trackCatalogState.occurrences) } label: {
            HStack(spacing: 12) {
                AuthenticatedArtworkView(itemID: track.id, accessibilityLabel: "Artwork for \(track.name)")
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name).font(.body.weight(.medium)).lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if !track.album.isEmpty {
                        Text(track.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if track.durationTicks != nil { Text(track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
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
