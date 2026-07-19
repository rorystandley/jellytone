import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = PlaylistDetailState()

    let playlist: Playlist

    var body: some View {
        Group {
            if state.isLoading && state.entries.isEmpty {
                AudioStateView(kind: .loading, title: "Loading playlist", detail: "Preparing its saved track order…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else if let message = state.errorMessage, state.entries.isEmpty {
                unavailable(message)
            } else if state.hasLoaded && state.entries.isEmpty {
                emptyState
            } else {
                detailList
            }
        }
        .accessibilityIdentifier("playlist-detail-screen")
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .audioCanvas()
        .task(id: requestIdentity) { await load() }
    }

    private var scope: PlaylistFeatureScope {
        PlaylistFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var requestIdentity: String {
        "\(scope.serverID)|\(scope.accountID)|\(scope.libraryID ?? "")|\(playlist.id)"
    }

    private var detailList: some View {
        List {
            Section { header.padding(.vertical, 8) }
                .listRowSeparator(.hidden)

            Section {
                ForEach(Array(state.entries.enumerated()), id: \.element.id) { offset, entry in
                    Button { model.play(entry, in: state.entries) } label: {
                        PlaylistEntryRow(position: offset + 1, entry: entry)
                    }
                    .accessibilityIdentifier("playlist-track-\(entry.id)")
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel(trackAccessibilityLabel(entry, position: offset + 1))
                    .accessibilityHint("Starts playback from this playlist occurrence")
                    .task {
                        if entry.id == state.entries.last?.id { await loadMore() }
                    }
                }
            } header: {
                Text("Tracks")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            if state.isLoadingMore || state.paginationError != nil || state.errorMessage != nil {
                Section { paginationStatus }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .refreshable { await refresh() }
        .overlay(alignment: .top) {
            if state.isLoading && !state.entries.isEmpty {
                ProgressView("Refreshing playlist…")
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                artwork.frame(width: horizontalSizeClass == .regular ? 180 : 132,
                              height: horizontalSizeClass == .regular ? 180 : 132)
                identityAndActions
                Spacer(minLength: 0)
            }
            VStack(spacing: 16) {
                artwork.frame(width: 180, height: 180)
                identityAndActions
            }
        }
    }

    private var artwork: some View {
        PlaylistArtwork(playlist: playlist)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var identityAndActions: some View {
        VStack(alignment: horizontalSizeClass == .regular ? .leading : .center, spacing: 10) {
            VStack(alignment: horizontalSizeClass == .regular ? .leading : .center, spacing: 4) {
                Text("Playlist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(playlist.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(horizontalSizeClass == .regular ? .leading : .center)
                Text(state.entries.count == 1 ? "1 playable track" : "\(state.entries.count) playable tracks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            AudioPlayActions(isDisabled: state.entries.isEmpty,
                             play: { model.playAll(state.entries) },
                             shuffle: { model.shuffle(state.entries) },
                             playIdentifier: "playlist-play-all", shuffleIdentifier: "playlist-shuffle")
        }
        .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .regular ? .leading : .center)
    }

    private var emptyState: some View {
        AudioStateView(kind: .empty, title: emptyTitle, detail: emptyDescription,
                       actionTitle: "Refresh") { Task { await refresh() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private var emptyTitle: String {
        (playlist.itemCount ?? 0) > 0 ? "No playable audio" : "Empty playlist"
    }

    private var emptyDescription: String {
        if (playlist.itemCount ?? 0) > 0 {
            return "This playlist contains items, but Jellyfin returned no playable audio tracks."
        }
        return "This playlist does not contain any tracks."
    }

    @ViewBuilder
    private var paginationStatus: some View {
        HStack {
            Spacer()
            if state.isLoadingMore {
                ProgressView("Loading more tracks…")
            } else if let message = state.paginationError ?? state.errorMessage {
                VStack(spacing: 8) {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button(state.paginationError == nil ? "Retry Refresh" : "Retry More Tracks") {
                        Task {
                            if state.paginationError == nil { await refresh() } else { await loadMore() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
            }
            Spacer()
        }
    }

    private func unavailable(_ message: String) -> some View {
        AudioStateView(kind: .error, title: "Playlist unavailable", detail: message,
                       actionTitle: "Try Again") { Task { await load() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func trackAccessibilityLabel(_ entry: PlaylistEntry, position: Int) -> String {
        let identity = "Track \(position), \(entry.track.name), by \(entry.track.artist)"
        guard entry.track.durationTicks != nil else { return "\(identity), duration unavailable" }
        return "\(identity), \(entry.track.durationLabel)"
    }

    private func load() async {
        let requestScope = scope
        await state.load(playlist: playlist, scope: requestScope) { startIndex in
            try await model.playlistEntries(for: playlist, startIndex: startIndex)
        }
    }

    private func refresh() async {
        let requestScope = scope
        await state.refresh(playlist: playlist, scope: requestScope) { startIndex in
            try await model.playlistEntries(for: playlist, startIndex: startIndex)
        }
    }

    private func loadMore() async {
        let requestScope = scope
        await state.loadMore(playlist: playlist, scope: requestScope) { startIndex in
            try await model.playlistEntries(for: playlist, startIndex: startIndex)
        }
    }
}

private struct PlaylistEntryRow: View {
    let position: Int
    let entry: PlaylistEntry

    var body: some View {
        AudioTrackRow(position: position, title: entry.track.name, artist: entry.track.artist,
                      album: entry.track.album,
                      duration: entry.track.durationTicks == nil ? nil : entry.track.durationLabel)
    }
}
