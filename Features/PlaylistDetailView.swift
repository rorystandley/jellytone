import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = PlaylistDetailState()
    @State private var showRename = false
    @State private var renameText = ""

    let playlist: Playlist

    var body: some View {
        Group {
            if state.isLoading && state.entries.isEmpty {
                ProgressView("Loading playlist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = state.errorMessage, state.entries.isEmpty {
                unavailable(message)
            } else if state.hasLoaded && state.entries.isEmpty {
                emptyState
            } else {
                detailList
            }
        }
        .accessibilityIdentifier("playlist-detail-screen")
        .navigationTitle(model.effectivePlaylist(playlist).name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestIdentity) { await load() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Rename", systemImage: "pencil") { renameText = model.effectivePlaylist(playlist).name; showRename = true }.accessibilityLabel("Rename playlist") } }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Rename") { model.renamePlaylist(playlist, to: renameText) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The new name will be synced with Jellyfin.") }
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
                Text(model.effectivePlaylist(playlist).name)
                    .font(.title2.bold())
                    .multilineTextAlignment(horizontalSizeClass == .regular ? .leading : .center)
                Text(state.entries.count == 1 ? "1 playable track" : "\(state.entries.count) playable tracks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                Button { model.playAll(state.entries) } label: {
                    Label("Play All", systemImage: "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("playlist-play-all")
                .keyboardShortcut(.return, modifiers: [.command])

                Button { model.shuffle(state.entries) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("playlist-shuffle")
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .regular ? .leading : .center)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "music.note.slash")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("Refresh") { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
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
        ContentUnavailableView {
            Label("Playlist unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(position))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.track.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(entry.track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.track.durationTicks != nil {
                Text(entry.track.durationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
