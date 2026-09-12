import SwiftUI

/// Cache-first Home presentation. `AppModel` owns the scoped snapshot and every
/// playback transition; this view never creates a competing queue.
///
/// First screen migrated to `JellytoneTheme` (docs/design/design-system.md);
/// no raw colours, system-default fonts, or magic spacing belong here.
struct HomeLibraryView: View {
    @EnvironmentObject private var model: AppModel

    /// 0 at the top (header bar transparent over the hero), 1 once scrolled past
    /// the fade window (header bar's blur fully materialised, Spotify-style).
    @State private var headerProgress: Double = 0

    /// Owned here (not in the header) so the Settings sheet is presented above
    /// the `.refreshable` and never inherits its pull-to-refresh action.
    @State private var showingSettings = false

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
            // Present Settings here, OUTSIDE the `.refreshable` above, so the
            // sheet does not inherit Home's RefreshAction — otherwise pulling
            // the sheet down would run a Home refresh instead of dismissing it.
            .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    private var hasContent: Bool {
        model.playback.currentTrack != nil
            || !(model.homeSnapshot?.recentlyAddedAlbums.isEmpty ?? true)
            || !(model.homeSnapshot?.recentlyPlayedTracks.isEmpty ?? true)
            || !(model.homeSnapshot?.favouriteArtists.isEmpty ?? true)
            || !(model.homeSnapshot?.discoveryMixes.isEmpty ?? true)
            || !(model.homeSnapshot?.frequentlyPlayedAlbums.isEmpty ?? true)
            || !(model.homeSnapshot?.rediscoverAlbums.isEmpty ?? true)
            || !(model.homeSnapshot?.homeGenres.isEmpty ?? true)
            || !(model.homeSnapshot?.madeForYouPlaylists.isEmpty ?? true)
    }

    @ViewBuilder private var content: some View {
        if !hasContent, let error = model.homeRefreshError {
            HomeStateCard(title: "Couldn’t load Home", detail: error) {
                Task { await model.refreshHomeShelves() }
            }
        } else if !hasContent, !model.isRefreshingHome, model.homeSnapshot != nil {
            HomeStateCard(title: "Nothing recent yet",
                          detail: "Top albums, mixes, and recently played music from this library will appear here.")
        } else {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                        HomeHeroSection(playback: model.playback, topInset: proxy.safeAreaInsets.top)
                        madeForYouSection
                        topAlbumsSection
                        favouriteArtistsSection
                        recentlyPlayedSection
                        rediscoverSection
                        recentlyAddedSection
                        playlistsSection
                        genresSection
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
                // Drive the header bar's backdrop from the scroll position.
                .onScrollGeometryChange(for: Double.self) { geo in
                    let offset = Double(geo.contentOffset.y + geo.contentInsets.top)
                    return min(1, max(0, offset / Double(HomeMetrics.headerFadeDistance)))
                } action: { _, progress in
                    headerProgress = progress
                }
                // Fixed header pinned to the top-leading chrome (Spotify
                // placement): the avatar stays put while the shelves scroll
                // underneath, and the bar's blur fades in as content passes
                // beneath it so the avatar never floats free of any surface.
                .overlay(alignment: .top) {
                    HomePinnedHeader(backgroundOpacity: headerProgress) { showingSettings = true }
                }
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
                    NavigationLink(value: hero) { HomeHeroAlbumCard(album: hero) }
                        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                        .accessibilityIdentifier("home-recently-added-album-\(hero.id)")
                        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                }
                if albums.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.lg) {
                            ForEach(albums.dropFirst()) { album in
                                NavigationLink(value: album) { HomeAlbumCard(album: album) }
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

    // MARK: Favourite Artists

    // Cached with the rest of the Home snapshot — paints from the last
    // persisted shelf and silently updates when the refresh lands. Hidden
    // entirely when the user has no favourite artists (no empty chrome).
    private var favouriteArtists: [Artist] {
        model.homeSnapshot?.favouriteArtists ?? []
    }

    @ViewBuilder private var favouriteArtistsSection: some View {
        if !favouriteArtists.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Favourite Artists")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.lg) {
                        ForEach(favouriteArtists) { artist in
                            NavigationLink(value: artist) {
                                HomeArtistCircle(artist: artist)
                            }
                            .buttonStyle(.jtPressScale())
                            .accessibilityIdentifier("home-favourite-artist-\(artist.id)")
                            .accessibilityLabel("\(artist.name), favourite artist")
                            .accessibilityHint("Opens artist")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    .padding(.vertical, JellytoneTheme.Space.sm)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: Made For You (Instant Mixes)

    private var discoveryMixes: [DiscoveryMix] {
        model.homeSnapshot?.discoveryMixes ?? []
    }

    @ViewBuilder private var madeForYouSection: some View {
        if !discoveryMixes.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Made for You")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: JellytoneTheme.Space.md) {
                        ForEach(Array(discoveryMixes.enumerated()), id: \.element.id) { index, mix in
                            Button {
                                Task { await model.playDiscoveryMix(mix) }
                            } label: {
                                HomeShelfTile(
                                    itemID: mix.artworkItemID,
                                    imageTag: mix.imageTag,
                                    title: mix.title,
                                    subtitle: mix.subtitle,
                                    isHero: index == 0
                                )
                            }
                            .buttonStyle(.jtPressScale())
                            .accessibilityIdentifier("home-discovery-mix-\(mix.id)")
                            .accessibilityLabel("\(mix.title), \(mix.subtitle)")
                            .accessibilityHint("Starts an Instant Mix")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: Top Albums

    private var frequentlyPlayedAlbums: [Album] {
        model.homeSnapshot?.frequentlyPlayedAlbums ?? []
    }

    @ViewBuilder private var topAlbumsSection: some View {
        if !frequentlyPlayedAlbums.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Top Albums")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.lg) {
                        ForEach(frequentlyPlayedAlbums) { album in
                            NavigationLink(value: album) { HomeAlbumCard(album: album) }
                                .buttonStyle(.jtPressScale())
                                .accessibilityIdentifier("home-top-album-\(album.id)")
                        }
                    }
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    .padding(.vertical, JellytoneTheme.Space.sm)
                }
            }
        }
    }

    // MARK: Rediscover

    private var rediscoverAlbums: [Album] {
        model.homeSnapshot?.rediscoverAlbums ?? []
    }

    @ViewBuilder private var rediscoverSection: some View {
        if !rediscoverAlbums.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Rediscover")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                Text("Albums from your library you might have forgotten.")
                    .font(.jtCaption)
                    .foregroundStyle(Color.jtTextSecondary)
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: JellytoneTheme.Space.lg) {
                        ForEach(rediscoverAlbums) { album in
                            NavigationLink(value: album) { HomeAlbumCard(album: album) }
                                .buttonStyle(.jtPressScale())
                                .accessibilityIdentifier("home-rediscover-album-\(album.id)")
                        }
                    }
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    .padding(.vertical, JellytoneTheme.Space.sm)
                }
            }
        }
    }

    // MARK: Your Playlists

    private var homePlaylists: [Playlist] {
        model.homeSnapshot?.madeForYouPlaylists ?? []
    }

    @ViewBuilder private var playlistsSection: some View {
        if !homePlaylists.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Your Playlists")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: JellytoneTheme.Space.md) {
                        ForEach(Array(homePlaylists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink(value: playlist) {
                                HomeShelfTile(
                                    itemID: playlist.id,
                                    imageTag: playlist.imageTag,
                                    title: playlist.name,
                                    subtitle: playlist.itemCount.map { "\($0) songs" },
                                    isHero: index == 0
                                )
                            }
                            .buttonStyle(.jtPressScale())
                            .accessibilityIdentifier("home-playlist-\(playlist.id)")
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

    // MARK: Genres

    private var homeGenres: [Genre] {
        model.homeSnapshot?.homeGenres ?? []
    }

    @ViewBuilder private var genresSection: some View {
        if !homeGenres.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                HomeSectionHeader(title: "Genres")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JellytoneTheme.Space.sm) {
                        ForEach(homeGenres) { genre in
                            NavigationLink(value: genre) {
                                Text(genre.name)
                                    .font(.jtRowTitle)
                                    .foregroundStyle(Color.jtTextPrimary)
                                    .padding(.horizontal, JellytoneTheme.Space.md)
                                    .padding(.vertical, JellytoneTheme.Space.sm)
                                    .background(Capsule().fill(Color.jtSurface))
                            }
                            .buttonStyle(.jtPressScale())
                            .accessibilityIdentifier("home-genre-\(genre.id)")
                            .accessibilityLabel("\(genre.name), genre")
                            .accessibilityHint("Opens genre")
                        }
                    }
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                }
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
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button { model.play(track, in: tracks) } label: {
                                HomeShelfTile(
                                    // Fall back to album artwork — most tracks
                                    // carry no image of their own. The tag is
                                    // only nil-checked downstream.
                                    itemID: track.artworkItemID ?? track.id,
                                    imageTag: track.artworkItemID == nil ? nil : (track.imageTag ?? "album"),
                                    title: track.name,
                                    subtitle: track.artist,
                                    isHero: index == 0
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
    /// Favourite Artists shelf — circular artwork, same footprint as the
    /// small album cards so the shelves share a rhythm.
    static let artistCircleDiameter: CGFloat = 112
    static let shelfTileHeight: CGFloat = 140
    // Mockup grid is 1.5fr/1fr inside a 390pt frame with 20pt margins/12pt gap.
    static let shelfHeroTileWidth: CGFloat = 202
    static let shelfTileWidth: CGFloat = 134
    /// Apple's canonical 44pt control size — the account avatar's tap target.
    static let avatarDiameter: CGFloat = 44
    /// Scroll distance over which the pinned header's blur backdrop fades in.
    static let headerFadeDistance: CGFloat = 140
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
            // Top-down sheen: gives the disc a lit edge so it reads as a raised
            // control rather than a flat cutout pasted on the artwork.
            .overlay {
                Circle().fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
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
            // Hairline ring separates the avatar from whatever sits behind it —
            // dark artwork at the top of the scroll, the page background below.
            .overlay {
                Circle().strokeBorder(Color.jtGlassBorderOverArtwork, lineWidth: 1)
            }
            // Soft ambient shadow lifts it off the surface (the missing depth
            // that made it look like a sticker).
            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
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

/// Fixed top bar: the account avatar at the leading edge (Spotify placement)
/// over a blur backdrop that fades in with the scroll. Transparent at the top
/// so it reads as part of the hero; opaque once shelves scroll beneath it.
private struct HomePinnedHeader: View {
    let backgroundOpacity: Double
    let onOpenSettings: () -> Void

    var body: some View {
        HomeHeader(onOpenSettings: onOpenSettings)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            // The overlay already sits below the status bar (safe area), so a
            // single small inset keeps the avatar snug to the top — adding the
            // safe-area inset again here is what made the bar look oversized.
            .padding(.vertical, JellytoneTheme.Space.sm)
            .background {
                // Blur extends up through the status bar so scrolled content
                // reads cleanly behind it, without inflating the bar's height.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea(edges: .top)
            }
    }
}

/// Just the account avatar. Asks the owner (HomeLibraryView) to open Settings;
/// the sheet is presented there, above the `.refreshable`, so pulling it down
/// dismisses rather than triggering a Home refresh.
private struct HomeHeader: View {
    @EnvironmentObject private var model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        Button { onOpenSettings() } label: {
            HomeAvatarBadge(username: model.session?.username)
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("home-settings")
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
            Button { playback.toggle() } label: {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .overlay {
                            GeometryReader { geo in
                                Group {
                                    if let image = playback.artwork {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else {
                                        JellytoneTheme.placeholderGradient(
                                            hue: JellytoneTheme.placeholderHue(forID: current.id)
                                        )
                                    }
                                }
                                // Pin the fill to the hero's laid-out size so
                                // ScrollView geometry passes cannot retarget
                                // scaledToFill and make the artwork zoom.
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
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
            // Plain, not press-scale: scaling the full-bleed artwork on
            // touch-down fights the home ScrollView and looks like the
            // image zooming in and out as you start to scroll.
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-continue-listening")
            .accessibilityLabel("Continue listening to \(current.name) by \(current.artist)")
            .accessibilityHint(playback.isPlaying ? "Pauses playback" : "Resumes playback")
        } else {
            // No hero artwork to bleed under the pinned avatar, so reserve the
            // space it occupies; otherwise the first shelf collides with it.
            Color.clear
                .frame(height: topInset + HomeMetrics.avatarDiameter + JellytoneTheme.Space.md)
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

/// Favourite Artists tile: circular artwork with the artist's name centred
/// beneath (Apple Music-style artist presentation).
private struct HomeArtistCircle: View {
    let artist: Artist

    var body: some View {
        VStack(spacing: JellytoneTheme.Space.sm) {
            homeArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name)
                .frame(width: HomeMetrics.artistCircleDiameter, height: HomeMetrics.artistCircleDiameter)
                .clipShape(Circle())
                .jtFloatingCardShadow()
            Text(artist.name)
                .font(.jtRowSubtitle.weight(.bold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(width: HomeMetrics.artistCircleDiameter)
        .accessibilityElement(children: .combine)
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
/// bottom-anchored text over artwork. The leading tile is a static hero
/// (mockup 1.5fr column); the rest stay at the standard width. Width is not
/// driven from scroll geometry — interpolating it made artwork appear to
/// zoom as the home page scrolled (AGENTS.md: Home Listen Now surfaces).
private struct HomeShelfTile: View {
    let itemID: String
    let imageTag: String?
    let title: String
    let subtitle: String?
    var isHero: Bool = false

    private var width: CGFloat {
        isHero ? HomeMetrics.shelfHeroTileWidth : HomeMetrics.shelfTileWidth
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay {
                    homeArtwork(itemID: itemID, imageTag: imageTag, name: title)
                        .frame(width: width, height: HomeMetrics.shelfTileHeight)
                        .clipped()
                }
                .jtArtworkScrim()
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(title)
                    .font(isHero ? .jtHeroCardTitle : .jtRowTitle.weight(.heavy))
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
            .padding(isHero ? JellytoneTheme.Space.lgPlus : JellytoneTheme.Space.mdPlus)
        }
        .frame(width: width, height: HomeMetrics.shelfTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
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
