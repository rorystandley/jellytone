import SwiftUI
import UIKit

/// Apple Music-style Artists list reached from the Library category rows:
/// alphabetical circular-artwork rows with hairline separators, an A–Z scrub
/// rail on the trailing edge for jumping between sections, and pagination as
/// the user scrolls. Themed per docs/design/design-system.md.
struct ArtistLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = ArtistLibraryState()

    var body: some View {
        Group {
            if state.isLoading && state.artists.isEmpty {
                stateCard(title: "Loading artists", detail: "Fetching this music library’s artists…",
                          isLoading: true)
            } else if let message = state.errorMessage, state.artists.isEmpty {
                stateCard(title: "Couldn’t load artists", detail: message, retry: true)
            } else if state.hasLoaded && state.artists.isEmpty {
                stateCard(title: "No artists found",
                          detail: "Album artists in this music library will appear here.")
            } else {
                artistList
            }
        }
        .background(Color.jtBackground.ignoresSafeArea())
        .accessibilityIdentifier("artists-screen")
        .navigationTitle("Artists")
        .task(id: scope) {
            // Cache-first: paint the persisted snapshot instantly, then let
            // the network replace it silently (no loading chip over content).
            state.seed(await model.cachedArtists(), scope: scope)
            if state.artists.isEmpty {
                await load()
            } else {
                await refresh()
            }
            // Backfill the rest of the library so the alphabet rail can jump
            // to any letter without waiting on scroll-driven pagination.
            await loadAllRemaining()
        }
    }

    private var scope: ArtistFeatureScope {
        ArtistFeatureScope(
            serverID: model.session?.serverID ?? "",
            accountID: model.session?.userID ?? "",
            libraryID: model.selectedLibraryID
        )
    }

    private var showsAlphabetRail: Bool {
        state.artists.count >= ArtistLibraryMetrics.indexMinimumRowCount
    }

    private var artistList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.artists) { artist in
                        NavigationLink(value: artist) {
                            ArtistRow(artist: artist)
                        }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                        .id(artist.id)
                        .accessibilityIdentifier("artist-row-\(artist.id)")
                        .accessibilityLabel("Artist, \(artist.name)")
                        .accessibilityHint("Opens artist")
                        .task {
                            if artist.id == state.artists.last?.id { await loadMore() }
                        }
                        if artist.id != state.artists.last?.id {
                            Rectangle().fill(Color.jtBorder).frame(height: 1)
                                .padding(.leading, ArtistLibraryMetrics.artworkDiameter + JellytoneTheme.Space.mdPlus)
                        }
                    }
                    paginationStatus
                }
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.bottom, JellytoneTheme.Space.xxxl)
            }
            .refreshable {
                await refresh()
                await loadAllRemaining()
            }
            .overlay(alignment: .trailing) {
                if showsAlphabetRail {
                    ArtistAlphabetRail { letter in
                        guard let target = ArtistAlphabetIndex.target(for: letter, in: state.artists) else {
                            return
                        }
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder private var paginationStatus: some View {
        if state.isLoadingMore {
            ProgressView("Loading more artists…")
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, JellytoneTheme.Space.lg)
                .accessibilityIdentifier("artist-load-more")
        } else if let message = state.paginationError {
            VStack(spacing: JellytoneTheme.Space.sm) {
                Text("Couldn’t load more artists")
                    .font(.jtSubsectionHeader)
                    .foregroundStyle(Color.jtTextPrimary)
                Text(message)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                Button("Retry loading more artists") { Task { await loadMore() } }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
                    .accessibilityIdentifier("artist-load-more")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, JellytoneTheme.Space.lg)
        }
    }

    private func stateCard(title: String, detail: String, isLoading: Bool = false,
                           retry: Bool = false) -> some View {
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
            if retry {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.jtCapsule(.secondaryFlat))
                    .padding(.top, JellytoneTheme.Space.sm)
                    .accessibilityIdentifier("artists-retry")
            }
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, JellytoneTheme.Space.md)
    }

    private func load() async {
        let requestScope = scope
        await state.load(scope: requestScope) { startIndex in
            try await model.artistPage(startIndex: startIndex)
        }
    }

    private func refresh() async {
        let requestScope = scope
        await state.refresh(scope: requestScope) { startIndex in
            try await model.artistPage(startIndex: startIndex)
        }
    }

    private func loadMore() async {
        let requestScope = scope
        await state.loadMore(scope: requestScope) { startIndex in
            try await model.artistPage(startIndex: startIndex)
        }
    }

    private func loadAllRemaining() async {
        let requestScope = scope
        await state.loadAllRemaining(scope: requestScope) { startIndex in
            try await model.artistPage(startIndex: startIndex)
        }
    }
}

private enum ArtistLibraryMetrics {
    /// Apple Music-style circular row artwork.
    static let artworkDiameter: CGFloat = 52
    /// Fixed per-letter slot; 27 slots stay within the visible height of the
    /// smallest supported iPhone in portrait.
    static let indexLetterHeight: CGFloat = 14
    static let indexRailWidth: CGFloat = 16
    /// Below roughly a screenful of rows the whole list is visible at once and
    /// the rail is noise.
    static let indexMinimumRowCount = 12
}

/// The trailing A–Z/# scrub rail. A drag anywhere on the rail selects the
/// letter under the finger (a tap is a zero-length drag), with a selection
/// haptic on each new letter, matching the system index-bar feel.
private struct ArtistAlphabetRail: View {
    let onSelect: (String) -> Void

    @State private var activeLetter: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ArtistAlphabetIndex.letters, id: \.self) { letter in
                Text(letter)
                    .font(.jtCaption)
                    .foregroundStyle(Color.jtAccent)
                    .frame(width: ArtistLibraryMetrics.indexRailWidth,
                           height: ArtistLibraryMetrics.indexLetterHeight)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Jump to \(letter == ArtistAlphabetIndex.numberSection ? "number sign" : letter)")
                    .accessibilityAction { onSelect(letter) }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in select(at: value.location.y) }
                .onEnded { _ in activeLetter = nil }
        )
        .padding(.trailing, JellytoneTheme.Space.xxs)
        .accessibilityIdentifier("artist-alphabet-index")
        .accessibilityElement(children: .contain)
    }

    private func select(at y: CGFloat) {
        let letters = ArtistAlphabetIndex.letters
        let slot = Int(y / ArtistLibraryMetrics.indexLetterHeight)
        let letter = letters[min(max(slot, 0), letters.count - 1)]
        guard letter != activeLetter else { return }
        activeLetter = letter
        UISelectionFeedbackGenerator().selectionChanged()
        onSelect(letter)
    }
}

private struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.mdPlus) {
            JellytoneItemArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name)
                .frame(width: ArtistLibraryMetrics.artworkDiameter,
                       height: ArtistLibraryMetrics.artworkDiameter)
                .clipShape(Circle())
            Text(artist.name)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
            Spacer(minLength: JellytoneTheme.Space.sm)
            Image(systemName: "chevron.forward")
                .font(.jtCaption.weight(.bold))
                .foregroundStyle(Color.jtTextTertiary)
        }
        .padding(.vertical, JellytoneTheme.Space.sm)
        .contentShape(Rectangle())
    }
}
