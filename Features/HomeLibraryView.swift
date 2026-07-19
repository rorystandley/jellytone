import SwiftUI

/// Cache-first Home presentation. `AppModel` owns the scoped snapshot and every
/// playback transition; this view never creates a competing queue.
///
/// First screen migrated to `JellytoneTheme` (docs/design/design-system.md);
/// no raw colours, system-default fonts, or magic spacing belong here.
struct HomeLibraryView<AlbumDestination: View>: View {
    @EnvironmentObject private var model: AppModel

    let albumDestination: (Album) -> AlbumDestination

    var body: some View {
        content
            .background(Color.jtBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.refreshHomeShelves() }
            .refreshable { await model.refreshHomeShelves() }
            // Background refreshes are silent (Apple Music-style): the system
            // pull spinner is the only refresh indicator, and fresh content
            // cross-fades in over the cached shelves.
            .animation(JellytoneTheme.Motion.crossfade, value: model.homeSnapshot)
    }

    private var hasContent: Bool {
        model.playback.currentTrack != nil
            || !(model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true)
            || !(model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true)
    }

    @ViewBuilder private var content: some View {
        if !hasContent, let error = model.homeRefreshError {
            HomeStateCard(title: "Couldn’t load Home", detail: error) {
                Task { await model.refreshHomeShelves() }
            }
        } else if !hasContent, !model.isRefreshingHome, model.homeSnapshot != nil {
            HomeStateCard(title: "Nothing recent yet",
                          detail: "Recently added albums and recently played music will appear here.")
        } else {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                        HomeHeroSection(playback: model.playback, topInset: proxy.safeAreaInsets.top)
                        recentlyAddedSection
                        madeForYouSection
                        recentlyPlayedSection
                        if hasContent, let error = model.homeRefreshError { partialFailure(message: error) }
                    }
                    .padding(.bottom, JellytoneTheme.Space.xxxl)
                }
                // On the ScrollView itself, not the outer branch group — an
                // identifier on a plain container cascades onto descendant
                // elements and would override their own identifiers.
                .accessibilityIdentifier("home-screen")
                // The hero artwork bleeds under the status bar; sections
                // below re-inset themselves via the measured topInset.
                .ignoresSafeArea(edges: .top)
            }
        }
    }

    // MARK: Recently Added

    @ViewBuilder private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
            HomeSectionHeader(title: "Recently Added")
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            if model.isRefreshingHome && (model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true) {
                HomeSkeleton(layout: .heroAndCards, label: "Loading recently added albums")
                    .accessibilityIdentifier("home-loading-skeleton")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            } else if model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true {
                empty("No recently added albums",
                      detail: "New albums in this music library will appear here.")
            } else {
                let albums = model.homeSnapshot?.recentlyAddedAlbums ?? []
                if let hero = albums.first {
                    NavigationLink { albumDestination(hero) } label: { HomeHeroAlbumCard(album: hero) }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                        .accessibilityIdentifier("home-recently-added-album-\(hero.id)")
                        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                }
                if albums.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.lg) {
                            ForEach(albums.dropFirst()) { album in
                                NavigationLink { albumDestination(album) } label: { HomeAlbumCard(album: album) }
                                    .buttonStyle(.jtPressScale())
                                    .accessibilityIdentifier("home-recently-added-album-\(album.id)")
                            }
                        }
                        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                        .padding(.vertical, JellytoneTheme.Space.sm)
                    }
                }
            }
        }
    }

    // MARK: Made For You

    // Cached with the rest of the Home snapshot — paints from the last
    // persisted shelf and silently updates when the refresh lands.
    private var madeForYouPlaylists: [Playlist] {
        model.homeSnapshot?.madeForYouPlaylists ?? []
    }

    @ViewBuilder private var madeForYouSection: some View {
        if !madeForYouPlaylists.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Made For You")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: JellytoneTheme.Space.md) {
                        ForEach(madeForYouPlaylists) { playlist in
                            NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
                                HomeShelfTile(
                                    itemID: playlist.id,
                                    imageTag: playlist.imageTag,
                                    title: playlist.name,
                                    subtitle: playlist.itemCount.map { "\($0) songs" }
                                )
                            }
                            .buttonStyle(.jtPressScale())
                            .accessibilityIdentifier("home-made-for-you-playlist-\(playlist.id)")
                            .accessibilityLabel("\(playlist.name), playlist")
                            .accessibilityHint("Opens playlist")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: Recently Played

    @ViewBuilder private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
            HomeSectionHeader(title: "Recently Played")
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            if model.isRefreshingHome && (model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true) {
                HomeSkeleton(layout: .shelf, label: "Loading recently played music")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            } else if model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true {
                empty("No recently played music",
                      detail: "Music you play in Jellyfin will appear here.")
            } else {
                let tracks = model.homeSnapshot?.recentlyPlayedTracks ?? []
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: JellytoneTheme.Space.md) {
                        ForEach(tracks) { track in
                            Button { model.play(track, in: tracks) } label: {
                                HomeShelfTile(
                                    itemID: track.id,
                                    imageTag: track.imageTag,
                                    title: track.name,
                                    subtitle: track.artist
                                )
                            }
                            .buttonStyle(.jtPressScale())
                            .accessibilityIdentifier("home-recently-played-track-\(track.id)")
                            .accessibilityLabel("\(track.name), \(track.artist)")
                            .accessibilityHint("Starts playback from this recently played track")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: Section state helpers

    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
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
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .accessibilityElement(children: .combine)
    }

    private func partialFailure(message: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text("Some recent music couldn’t be refreshed")
                .font(.jtSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
            Text(message)
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
            Button("Try Again") { Task { await model.refreshHomeShelves() } }
                .buttonStyle(.jtCapsule(.secondaryFlat))
                .accessibilityIdentifier("home-retry")
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-partial-failure")
    }
}

// MARK: - Layout metrics (content sizes from the spec, not spacing tokens)

private enum HomeMetrics {
    /// Hero height excluding the status-bar inset it also covers.
    static let heroHeight: CGFloat = 360
    static let heroPlayDiameter: CGFloat = 54
    static let recentlyAddedHeroHeight: CGFloat = 170
    static let smallCardSide: CGFloat = 112
    static let shelfTileHeight: CGFloat = 140
    // Mockup grid is 1.5fr/1fr inside a 390pt frame with 20pt margins/12pt gap.
    static let shelfHeroTileWidth: CGFloat = 202
    static let shelfTileWidth: CGFloat = 134
    /// Apple's canonical 44pt control size — tap-target ready for when the
    /// avatar gains its Settings action.
    static let avatarDiameter: CGFloat = 44
    /// Low point of the skeleton pulse.
    static let skeletonDimOpacity: Double = 0.55
}

/// Placeholder blocks shown only on a cold start with nothing cached.
/// Background refreshes never show these — they stay silent behind the
/// cached shelves, and pull-to-refresh uses the system spinner alone.
private struct HomeSkeleton: View {
    enum Layout {
        /// Recently Added: full-width hero card + a row of small squares.
        case heroAndCards
        /// Made For You / Recently Played: hero tile + standard tiles.
        case shelf
    }

    let layout: Layout
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Group {
            switch layout {
            case .heroAndCards:
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                    block(height: HomeMetrics.recentlyAddedHeroHeight, radius: JellytoneTheme.Radius.heroCard)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: JellytoneTheme.Space.lg) {
                        ForEach(0..<3, id: \.self) { _ in
                            block(width: HomeMetrics.smallCardSide,
                                  height: HomeMetrics.smallCardSide,
                                  radius: JellytoneTheme.Radius.compactArtwork)
                        }
                    }
                }
            case .shelf:
                HStack(spacing: JellytoneTheme.Space.md) {
                    block(width: HomeMetrics.shelfHeroTileWidth,
                          height: HomeMetrics.shelfTileHeight,
                          radius: JellytoneTheme.Radius.card)
                    ForEach(0..<2, id: \.self) { _ in
                        block(width: HomeMetrics.shelfTileWidth,
                              height: HomeMetrics.shelfTileHeight,
                              radius: JellytoneTheme.Radius.card)
                    }
                }
            }
        }
        .opacity(dimmed ? HomeMetrics.skeletonDimOpacity : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(JellytoneTheme.Motion.skeletonPulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func block(width: CGFloat? = nil, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.jtSurface)
            .frame(width: width, height: height)
    }
}

// MARK: - Header avatar (accent circle with the signed-in user's initials)

private struct HomeAvatarBadge: View {
    let username: String?

    var body: some View {
        Circle()
            .fill(Color.jtAccent)
            .frame(width: HomeMetrics.avatarDiameter, height: HomeMetrics.avatarDiameter)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.jtSubsectionHeader)
                        .foregroundStyle(.white)
                } else {
                    Text(initials)
                        .font(.jtSubsectionHeader.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
    }

    private var initials: String {
        guard let username else { return "" }
        let letters = username
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap(\.first)
        return String(letters).uppercased()
    }
}

// MARK: - Section header (plain 22pt/heavy title, no rule, no icons)

private struct HomeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.jtSectionHeader)
            .foregroundStyle(Color.jtTextPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Artwork helper

@MainActor @ViewBuilder
private func homeArtwork(itemID: String, imageTag: String?, name: String) -> some View {
    if imageTag != nil {
        AuthenticatedArtworkView(itemID: itemID, accessibilityLabel: "Artwork for \(name)")
    } else {
        JellytoneTheme.placeholderGradient(hue: JellytoneTheme.placeholderHue(forID: itemID))
            .accessibilityLabel("No artwork for \(name)")
    }
}

// MARK: - Header & full-bleed hero

/// Just the account avatar, top-trailing — no title, no greeting. Opens the
/// Settings sheet.
private struct HomeHeader: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        HStack {
            Spacer()
            Button { showingSettings = true } label: {
                HomeAvatarBadge(username: model.session?.username)
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home-settings")
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

/// Full-bleed Continue Listening hero: the current track's artwork fills to
/// the physical top of the screen with the header overlaid on its dark upper
/// wash, and dissolves into the page background at the bottom, where the
/// title/artist sit in standard text tokens (legible in light and dark).
/// Falls back to the plain header when nothing is playing. Observes the
/// playback controller directly (the coordinator does not republish nested
/// controller changes).
private struct HomeHeroSection: View {
    @ObservedObject var playback: PlaybackController
    let topInset: CGFloat

    var body: some View {
        if let current = playback.currentTrack {
            ZStack(alignment: .top) {
                Button { playback.toggle() } label: {
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .overlay {
                                if let image = playback.artwork {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    JellytoneTheme.placeholderGradient(
                                        hue: JellytoneTheme.placeholderHue(forID: current.id)
                                    )
                                }
                            }
                            .jtHeroVignette()
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                            Text("Continue Listening")
                                .jtEyebrowStyle()
                                .foregroundStyle(Color.jtTextTertiary)
                            HStack(alignment: .center, spacing: JellytoneTheme.Space.md) {
                                VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                                    Text(current.name)
                                        .font(.jtOnboardingHero)
                                        .foregroundStyle(Color.jtTextPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(current.artist)
                                        .font(.jtBody.weight(.medium))
                                        .foregroundStyle(Color.jtTextSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: JellytoneTheme.Space.sm)
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: HomeMetrics.heroPlayDiameter / 3, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: HomeMetrics.heroPlayDiameter, height: HomeMetrics.heroPlayDiameter)
                                    .background(Circle().fill(Color.jtAccent))
                            }
                        }
                        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                        .padding(.bottom, JellytoneTheme.Space.sm)
                    }
                    .frame(height: HomeMetrics.heroHeight + topInset)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                .accessibilityIdentifier("home-continue-listening")
                .accessibilityLabel("Continue listening to \(current.name) by \(current.artist)")
                .accessibilityHint(playback.isPlaying ? "Pauses playback" : "Resumes playback")

                HomeHeader()
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    .padding(.top, topInset + JellytoneTheme.Space.sm)
            }
        } else {
            HomeHeader()
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, topInset + JellytoneTheme.Space.md)
        }
    }
}

private struct HomeHeroAlbumCard: View {
    let album: Album

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay { homeArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name) }
                .jtArtworkScrim()
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(album.name)
                    .font(.jtHeroCardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.jtRowSubtitle)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(JellytoneTheme.Space.lg)
        }
        .frame(height: HomeMetrics.recentlyAddedHeroHeight)
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.heroCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.heroCard, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), \(album.artist), recently added album")
        .accessibilityHint("Opens album")
    }
}

private struct HomeAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            homeArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
                .frame(width: HomeMetrics.smallCardSide, height: HomeMetrics.smallCardSide)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.compactArtwork, style: .continuous))
                .jtFloatingCardShadow()
            Text(album.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
            Text(album.artist)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(1)
        }
        .frame(width: HomeMetrics.smallCardSide, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), \(album.artist), recently added album")
        .accessibilityHint("Opens album")
    }
}

/// Shared tile for the horizontal Made For You / Recently Played shelves —
/// bottom-anchored text over artwork. The tile at the shelf's leading edge is
/// "in focus" and grows to the hero width; the size interpolates continuously
/// from the tile's own position in the scroll viewport, so focus hands over
/// smoothly as the user scrolls.
private struct HomeShelfTile: View {
    let itemID: String
    let imageTag: String?
    let title: String
    let subtitle: String?

    @State private var focusProgress: Double = 0

    private var width: CGFloat {
        HomeMetrics.shelfTileWidth
            + (HomeMetrics.shelfHeroTileWidth - HomeMetrics.shelfTileWidth) * focusProgress
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay { homeArtwork(itemID: itemID, imageTag: imageTag, name: title) }
                .jtArtworkScrim()
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(title)
                    .font(.jtRowTitle.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.jtCaption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            // Scale in place of a font swap so the type grows smoothly with
            // the tile (hero title is ~1.24× the standard tile title).
            .scaleEffect(1 + 0.24 * focusProgress, anchor: .bottomLeading)
            .padding(
                JellytoneTheme.Space.mdPlus
                    + (JellytoneTheme.Space.lgPlus - JellytoneTheme.Space.mdPlus) * focusProgress
            )
        }
        .frame(width: width, height: HomeMetrics.shelfTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .scrollView(axis: .horizontal)).minX
        } action: { minX in
            // Fully focused when the tile's leading edge sits at the content
            // margin; fully standard one slot (tile + gap) away.
            let distance = abs(minX - JellytoneTheme.Space.screenMargin)
            let slot = HomeMetrics.shelfTileWidth + JellytoneTheme.Space.md
            focusProgress = max(0, min(1, 1 - distance / slot))
        }
    }
}

// MARK: - Full-screen load/empty/error state

private struct HomeStateCard: View {
    let title: String
    let detail: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: JellytoneTheme.Space.md) {
            Text(title)
                .font(.jtSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
            Text(detail)
                .font(.jtBody)
                .foregroundStyle(Color.jtTextSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.jtCapsule(.primaryFlat))
                    .accessibilityIdentifier("home-retry")
            }
        }
        .padding(JellytoneTheme.Space.xl)
        .frame(maxWidth: 420)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
        .padding(JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
