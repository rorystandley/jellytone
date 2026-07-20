import SwiftUI

/// Downloads tab: everything stored for offline listening, grouped by the
/// album/playlist it was downloaded from. Rows play through the normal
/// queue (playback prefers the verified local file automatically); removal
/// is per-track via the context menu. Themed per design-system.md.
struct DownloadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DownloadsContent(downloads: model.downloads)
    }
}

private struct DownloadsContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var downloads: DownloadManager

    private struct ContainerGroup: Identifiable {
        let id: String
        let name: String
        let records: [DownloadedTrack]
    }

    private var groups: [ContainerGroup] {
        var order: [String] = []
        var byID: [String: [DownloadedTrack]] = [:]
        for record in downloads.records {
            if byID[record.containerID] == nil { order.append(record.containerID) }
            byID[record.containerID, default: []].append(record)
        }
        return order.compactMap { id in
            guard let records = byID[id], let first = records.first else { return nil }
            return ContainerGroup(id: id, name: first.containerName, records: records)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                header
                if downloads.records.isEmpty {
                    detailStateCard(
                        title: "No downloads yet",
                        detail: "Download albums, playlists, or songs to keep them for offline listening."
                    )
                } else {
                    ForEach(groups) { group in
                        section(for: group)
                    }
                }
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.md)
            .padding(.bottom, JellytoneTheme.Space.xxxl)
        }
        .background(Color.jtBackground.ignoresSafeArea())
        .accessibilityIdentifier("downloads-screen")
        .task { await downloads.refreshRecords() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
            Text("Downloads")
                .font(.jtLargeTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if !downloads.records.isEmpty {
                Text(summary)
                    .font(.jtCaption)
                    .foregroundStyle(Color.jtTextTertiary)
            }
        }
    }

    private var summary: String {
        let count = downloads.records.count
        let size = ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file)
        return "\(count == 1 ? "1 song" : "\(count) songs") · \(size)"
    }

    private func section(for group: ContainerGroup) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text(group.name)
                .font(.jtSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVStack(spacing: 0) {
                ForEach(group.records) { record in
                    Button {
                        model.play(record.track, in: group.records.map(\.track))
                    } label: {
                        DownloadedTrackRow(record: record, isLast: record.id == group.records.last?.id)
                    }
                    .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("download-track-\(record.track.id)")
                    .accessibilityLabel("\(record.track.name), \(record.track.artist), downloaded")
                    .accessibilityHint("Plays from the downloaded copy")
                    .contextMenu {
                        Button("Remove Download", systemImage: "trash") {
                            Task { await downloads.remove(record.track.id) }
                        }
                    }
                }
            }
        }
    }
}

private struct DownloadedTrackRow: View {
    let record: DownloadedTrack
    let isLast: Bool

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            JellytoneTrackArtwork(track: record.track)
                .frame(width: DetailMetrics.rowArtworkSide, height: DetailMetrics.rowArtworkSide)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.smallArtwork, style: .continuous))
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(record.track.name)
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(1)
                Text(record.track.artist)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: JellytoneTheme.Space.sm)
            Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                .font(.jtCaption)
                .foregroundStyle(Color.jtTextTertiary)
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

/// Spotify-style per-row download state, shown beside a track row's duration:
/// a small coral filled arrow when downloaded, a spinner while that track is
/// queued or downloading, nothing otherwise.
struct TrackDownloadIndicator: View {
    @ObservedObject var downloads: DownloadManager
    let trackID: String

    var body: some View {
        switch downloads.state(of: trackID) {
        case .waiting, .downloading:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Downloading")
        default:
            if downloads.isDownloaded(trackID) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.jtCaption)
                    .foregroundStyle(Color.jtAccent)
                    .accessibilityLabel("Downloaded")
            }
        }
    }
}

/// Detail-header download action shared by album and playlist screens.
/// Idle → arrow; anything queued/downloading → spinner; everything present →
/// filled accent check (disabled — removal lives on the Downloads screen and
/// per-track menus).
struct DownloadStatusButton: View {
    @ObservedObject var downloads: DownloadManager
    let tracks: [Track]
    let container: DownloadContainer
    let identifierPrefix: String

    private var allDownloaded: Bool {
        !tracks.isEmpty && tracks.allSatisfy { downloads.isDownloaded($0.id) }
    }

    private var anyActive: Bool {
        tracks.contains { track in
            switch downloads.state(of: track.id) {
            case .waiting, .downloading: return true
            default: return false
            }
        }
    }

    var body: some View {
        Button {
            downloads.download(tracks, container: container)
        } label: {
            Group {
                if anyActive {
                    ProgressView()
                } else if allDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.jtAccent)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.jtTextPrimary)
                }
            }
            // Circled glyphs render optically smaller than bare ones — a size
            // up keeps this level with the shuffle icon beside it.
            .font(.jtSectionHeader.weight(.medium))
            .frame(width: DetailMetrics.secondaryActionSide, height: DetailMetrics.secondaryActionSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
        .disabled(tracks.isEmpty || allDownloaded || anyActive)
        .accessibilityLabel(allDownloaded ? "Downloaded" : "Download")
        .accessibilityIdentifier("\(identifierPrefix)-download")
    }
}
