import SwiftUI

/// Cache-first Home presentation. `AppModel` owns the scoped snapshot and every
/// playback transition; this view never creates a competing queue.
///
/// Listen Now layout (AGENTS.md priority 2, docs/design/design-system.md):
/// a time-of-day masthead, a compact quick-access grid, then artwork shelves.
/// Colour, type, spacing, and radii stay on `JellytoneTheme` / `jt*` tokens so
/// light and dark are both first-class.
struct HomeLibraryView: View {
    @EnvironmentObject private var model: AppModel

    /// 0 at the top (status-bar wash clear), 1 once content has scrolled under
    /// the status bar and the blur has fully materialised.
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

    /// Hue source when nothing is playing: the first shelf item, so the wash
    /// complements whatever the page is about to feature.
    private var fallbackFeaturedID: String? {
        let snapshot = model.homeSnapshot
        return snapshot?.recentlyPlayedTracks.first?.id
            ?? snapshot?.recentlyAddedAlbums.first?.id
            ?? snapshot?.frequentlyPlayedAlbums.first?.id
            ?? snapshot?.discoveryMixes.first?.artworkItemID
            ?? snapshot?.favouriteArtists.first?.id
    }

    @ViewBuilder private var content: some View {
        if !hasContent, let error = model.homeRefreshError {
            HomeStateCard(title: "Couldn’t load Home", detail: error) {
                Task { await model.refreshHomeShelves() }
            }
            .background(alignment: .top) { restingWash }
        } else if !hasContent, !model.isRefreshingHome, model.homeSnapshot != nil {
            HomeStateCard(
                title: "Nothing recent yet",
                detail: "Top albums, mixes, and recently played music from this library will appear here."
            )
            .background(alignment: .top) { restingWash }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JellytoneTheme.Space.xxl) {
                    HomeMasthead(playback: model.playback) { showingSettings = true }
                    recentlyPlayedSection
                    recentlyAddedSection
                    favouriteArtistsSection
                    madeForYouSection
                    topAlbumsSection
                    rediscoverSection
                    playlistsSection
                    genresSection
                    if hasContent, let error = model.homeRefreshError { partialFailure(message: error) }
                }
                .padding(.bottom, JellytoneTheme.Space.screenTop)
            }
            // On the ScrollView itself, not the outer branch group — an
            // identifier on a plain container cascades onto descendant
            // elements and would override their own identifiers.
            .accessibilityIdentifier("home-screen")
            .onScrollGeometryChange(for: Double.self) { geo in
                let offset = Double(geo.contentOffset.y + geo.contentInsets.top)
                return min(1, max(0, offset / Double(HomeMetrics.headerFadeDistance)))
            } action: { _, progress in
                headerProgress = progress
            }
            .background(alignment: .top) {
                HomeAmbientBackdrop(playback: model.playback, fallbackID: fallbackFeaturedID)
                    .ignoresSafeArea(edges: .top)
            }
            .overlay {
                HomeTopChromeFade(opacity: headerProgress)
            }
        }
    }

    private var restingWash: some View {
        JellytoneAmbientWash(hue: JellytoneTheme.placeholderHues[0], height: HomeMetrics.washHeight)
            .ignoresSafeArea(edges: .top)
    }

    // MARK: Recently Played (quick access)

    private var recentlyPlayedTracks: [Track] {
        model.homeSnapshot?.recentlyPlayedTracks ?? []
    }

    /// Spotify-style jump-back grid. Capped so the shelves below stay in
    /// reach; anything past the cap stays on the horizontal shelf.
    private var quickAccessTracks: [Track] {
        Array(recentlyPlayedTracks.prefix(HomeMetrics.quickAccessCount))
    }

    private var recentlyPlayedOverflow: [Track] {
        Array(recentlyPlayedTracks.dropFirst(HomeMetrics.quickAccessCount))
    }

    private var quickAccessRows: [[Track]] {
        stride(from: 0, to: quickAccessTracks.count, by: 2).map { index in
            Array(quickAccessTracks[index..<min(index + 2, quickAccessTracks.count)])
        }
    }

    @ViewBuilder private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
            HomeSectionHeader(title: "Recently Played")
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            if model.isRefreshingHome && recentlyPlayedTracks.isEmpty {
                HomeSkeleton(layout: .quickGrid, label: "Loading recently played music")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            } else if recentlyPlayedTracks.isEmpty {
                empty("No recently played music",
                      detail: "Music you play in Jellyfin will appear here.")
            } else {
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                    VStack(spacing: JellytoneTheme.Space.md) {
                        ForEach(quickAccessRows, id: \.self) { row in
                            HStack(alignment: .top, spacing: JellytoneTheme.Space.md) {
                                ForEach(row) { track in
                                    recentlyPlayedButton(track)
                                }
                                if row.count == 1 {
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    if !recentlyPlayedOverflow.isEmpty {
                        HomeCarousel(spacing: JellytoneTheme.Space.lg) {
                            ForEach(recentlyPlayedOverflow) { track in
                                recentlyPlayedCover(track)
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentlyPlayedButton(_ track: Track) -> some View {
        Button { model.play(track, in: recentlyPlayedTracks) } label: {
            HomeQuickAccessCell(
                itemID: trackArtworkID(track),
                imageTag: trackArtworkTag(track),
                title: track.name
            )
        }
        .buttonStyle(.jtPressScale())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home-recently-played-track-\(track.id)")
        .accessibilityLabel("\(track.name), \(track.artist)")
        .accessibilityHint("Starts playback from this recently played track")
    }

    private func recentlyPlayedCover(_ track: Track) -> some View {
        Button { model.play(track, in: recentlyPlayedTracks) } label: {
            HomeCoverCard(
                itemID: trackArtworkID(track),
                imageTag: trackArtworkTag(track),
                title: track.name,
                subtitle: track.artist,
                accessibilityLabel: "\(track.name), \(track.artist)"
            )
        }
        .buttonStyle(.jtPressScale())
        .accessibilityIdentifier("home-recently-played-track-\(track.id)")
        .accessibilityLabel("\(track.name), \(track.artist)")
        .accessibilityHint("Starts playback from this recently played track")
    }

    /// Fall back to album artwork — most tracks carry no image of their own.
    private func trackArtworkID(_ track: Track) -> String {
        track.artworkItemID ?? track.id
    }

    private func trackArtworkTag(_ track: Track) -> String? {
        track.artworkItemID == nil ? nil : (track.imageTag ?? "album")
    }

    // MARK: Recently Added

    @ViewBuilder private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
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
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.lg) {
                    if let hero = albums.first {
                        NavigationLink(value: hero) { HomeHeroAlbumCard(album: hero) }
                            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
                            .accessibilityIdentifier("home-recently-added-album-\(hero.id)")
                            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                    }
                    if albums.count > 1 {
                        HomeCarousel(spacing: JellytoneTheme.Space.lg) {
                            ForEach(albums.dropFirst()) { album in
                                NavigationLink(value: album) {
                                    HomeCoverCard(
                                        itemID: album.id,
                                        imageTag: album.imageTag,
                                        title: album.name,
                                        subtitle: album.artist,
                                        accessibilityLabel: "\(album.name), \(album.artist), recently added album",
                                        accessibilityHint: "Opens album"
                                    )
                                }
                                .buttonStyle(.jtPressScale())
                                .accessibilityIdentifier("home-recently-added-album-\(album.id)")
                            }
                        }
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
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                HomeSectionHeader(title: "Favourite Artists")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                HomeCarousel(spacing: JellytoneTheme.Space.lg) {
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
            }
        }
    }

    // MARK: Made For You (Instant Mixes)

    private var discoveryMixes: [DiscoveryMix] {
        model.homeSnapshot?.discoveryMixes ?? []
    }

    @ViewBuilder private var madeForYouSection: some View {
        if !discoveryMixes.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                HomeSectionHeader(title: "Made for You")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                HomeCarousel(spacing: JellytoneTheme.Space.lg) {
                    ForEach(discoveryMixes) { mix in
                        Button {
                            model.playDiscoveryMix(mix)
                        } label: {
                            HomeCoverCard(
                                itemID: mix.artworkItemID,
                                imageTag: mix.imageTag,
                                title: mix.title,
                                subtitle: mix.subtitle,
                                accessibilityLabel: "\(mix.title), \(mix.subtitle)",
                                accessibilityHint: "Starts an Instant Mix"
                            )
                        }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("home-discovery-mix-\(mix.id)")
                    }
                }
            }
        }
    }

    // MARK: Top Albums

    private var frequentlyPlayedAlbums: [Album] {
        model.homeSnapshot?.frequentlyPlayedAlbums ?? []
    }

    @ViewBuilder private var topAlbumsSection: some View {
        if !frequentlyPlayedAlbums.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                HomeSectionHeader(title: "Top Albums")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                HomeCarousel(spacing: JellytoneTheme.Space.lg) {
                    ForEach(frequentlyPlayedAlbums) { album in
                        NavigationLink(value: album) {
                            HomeCoverCard(
                                itemID: album.id,
                                imageTag: album.imageTag,
                                title: album.name,
                                subtitle: album.artist,
                                accessibilityLabel: "\(album.name), \(album.artist), album",
                                accessibilityHint: "Opens album"
                            )
                        }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("home-top-album-\(album.id)")
                    }
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
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
                    HomeSectionHeader(title: "Rediscover")
                    Text("Albums from your library you might have forgotten.")
                        .font(.jtScaledBody)
                        .foregroundStyle(Color.jtTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                HomeCarousel(spacing: JellytoneTheme.Space.lg) {
                    ForEach(rediscoverAlbums) { album in
                        NavigationLink(value: album) {
                            HomeCoverCard(
                                itemID: album.id,
                                imageTag: album.imageTag,
                                title: album.name,
                                subtitle: album.artist,
                                accessibilityLabel: "\(album.name), \(album.artist), album",
                                accessibilityHint: "Opens album"
                            )
                        }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("home-rediscover-album-\(album.id)")
                    }
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
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                HomeSectionHeader(title: "Your Playlists")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                HomeCarousel(spacing: JellytoneTheme.Space.lg) {
                    ForEach(homePlaylists) { playlist in
                        NavigationLink(value: playlist) {
                            HomeCoverCard(
                                itemID: playlist.id,
                                imageTag: playlist.imageTag,
                                title: playlist.name,
                                subtitle: playlist.itemCount.map { "\($0) songs" },
                                accessibilityLabel: "\(playlist.name), playlist",
                                accessibilityHint: "Opens playlist"
                            )
                        }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("home-playlist-\(playlist.id)")
                    }
                }
            }
        }
    }

    // MARK: Genres

    // Fixed tile row (no infinite scroll). Snapshot holds a server-random
    // sample so each Home refresh surfaces different genres without the lag
    // of paging mid-shelf; Library owns the full alphabetical catalogue.
    private var homeGenres: [Genre] {
        model.homeSnapshot?.homeGenres ?? []
    }

    @ViewBuilder private var genresSection: some View {
        if !homeGenres.isEmpty {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
                HomeSectionHeader(title: "Genres")
                    .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                HomeCarousel(spacing: JellytoneTheme.Space.md) {
                    ForEach(homeGenres) { genre in
                        NavigationLink(value: genre) {
                            HomeGenreTile(genre: genre)
                        }
                        .buttonStyle(.jtPressScale())
                        .accessibilityIdentifier("home-genre-\(genre.id)")
                        .accessibilityLabel("\(genre.name), genre")
                        .accessibilityHint("Opens genre")
                    }
                }
            }
        }
    }

    // MARK: Section state helpers

    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
            Text(title)
                .font(.jtScaledRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text(detail)
                .font(.jtScaledRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
                .strokeBorder(Color.jtBorder, lineWidth: 1)
        }
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .accessibilityElement(children: .combine)
    }

    private func partialFailure(message: String) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            Text("Some recent music couldn’t be refreshed")
                .font(.jtScaledSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.jtScaledBody)
                .foregroundStyle(Color.jtTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { Task { await model.refreshHomeShelves() } }
                .buttonStyle(.jtCapsule(.secondaryFlat))
                .accessibilityIdentifier("home-retry")
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous)
                .strokeBorder(Color.jtBorder, lineWidth: 1)
        }
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-partial-failure")
    }
}

// MARK: - Greeting

private enum HomeGreeting {
    /// "Good evening · Wednesday". The eyebrow style uppercases it.
    static func line(at date: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let hello: String
        switch hour {
        case 5..<12: hello = "Good morning"
        case 12..<18: hello = "Good afternoon"
        default: hello = "Good evening"
        }
        let weekday = date.formatted(.dateTime.weekday(.wide))
        return "\(hello) · \(weekday)"
    }
}

// MARK: - Layout metrics (content sizes, not spacing tokens)

private enum HomeMetrics {
    static let continueHeight: CGFloat = 220
    static let heroPlayDiameter: CGFloat = 54
    static let recentlyAddedHeroHeight: CGFloat = 188
    /// Primary shelf artwork. Larger than the old 112pt small card so covers
    /// lead the page; width is fixed (scroll geometry must not drive it — that
    /// made artwork zoom as Home scrolled).
    static let shelfArt: CGFloat = 156
    static let artistCircleDiameter: CGFloat = 120
    static let quickAccessSide: CGFloat = 56
    static let quickAccessCount = 6
    static let genreTileWidth: CGFloat = 156
    static let genreTileHeight: CGFloat = 96
    /// Apple's canonical 44pt control size — the account avatar's tap target.
    static let avatarDiameter: CGFloat = 44
    /// Scroll distance over which the top blur fades in.
    static let headerFadeDistance: CGFloat = 140
    /// How far the featured-hue wash reaches down the page.
    static let washHeight: CGFloat = 420
    /// Low point of the skeleton pulse.
    static let skeletonDimOpacity: Double = 0.55
}

// MARK: - Masthead & wash

/// Greeting, account avatar, and the Continue Listening card. Observes the
/// playback controller directly — the coordinator does not republish nested
/// controller changes — so the card appears as soon as a track is current.
private struct HomeMasthead: View {
    @ObservedObject var playback: PlaybackController
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
            HomeGreetingHeader(onOpenSettings: onOpenSettings)
            if playback.currentTrack != nil {
                HomeContinueCard(playback: playback)
            }
        }
    }
}

private struct HomeGreetingHeader: View {
    @EnvironmentObject private var model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: JellytoneTheme.Space.md) {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
                Text(HomeGreeting.line())
                    .jtScaledEyebrowStyle()
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(2)
                Text("For You")
                    .jtLargeTitleStyle(scaled: true)
                    .foregroundStyle(Color.jtTextPrimary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { onOpenSettings() } label: {
                HomeAvatarBadge(username: model.session?.username)
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home-settings")
        }
        .padding(.horizontal, JellytoneTheme.Space.screenMargin)
        .padding(.top, JellytoneTheme.Space.md)
    }
}

/// Fixed wash behind the scroll view, tinted from the current track when one
/// is playing and otherwise from the first shelf item.
private struct HomeAmbientBackdrop: View {
    @ObservedObject var playback: PlaybackController
    var fallbackID: String?

    var body: some View {
        let id = playback.currentTrack?.id ?? fallbackID
        let hue = id.map { JellytoneTheme.placeholderHue(forID: $0) } ?? JellytoneTheme.placeholderHues[0]
        JellytoneAmbientWash(hue: hue, height: HomeMetrics.washHeight)
    }
}

/// Blur that fades in over the status bar once shelves scroll beneath it.
/// Hit testing stays off so it never steals the avatar or the first row.
private struct HomeTopChromeFade: View {
    var opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.safeAreaInsets.top, JellytoneTheme.Space.xl)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(opacity)
                .frame(height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Header avatar

private struct HomeAvatarBadge: View {
    let username: String?

    var body: some View {
        Circle()
            .fill(Color.jtAccent)
            .frame(width: HomeMetrics.avatarDiameter, height: HomeMetrics.avatarDiameter)
            // Top-down sheen: gives the disc a lit edge so it reads as a raised
            // control rather than a flat cutout pasted on the wash.
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
                        .font(.jtScaledSubsectionHeader)
                        .foregroundStyle(.white)
                } else {
                    Text(initials)
                        .font(.jtScaledSubsectionHeader)
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle().strokeBorder(Color.jtGlassBorderOverArtwork, lineWidth: 1)
            }
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

// MARK: - Section header

private struct HomeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .jtSectionHeaderStyle(scaled: true)
            .foregroundStyle(Color.jtTextPrimary)
            .lineLimit(2)
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

// MARK: - Continue Listening

private struct HomeContinueCard: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        if let current = playback.currentTrack {
            Button {
                JellytoneHaptics.primaryAction()
                playback.toggle()
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .overlay {
                            GeometryReader { geo in
                                continueArtwork(for: current)
                                    // Pin the fill to the card's laid-out size so
                                    // ScrollView passes cannot retarget scaledToFill.
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            }
                        }
                        .jtArtworkScrim()
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
                        Text("Continue Listening")
                            .jtScaledEyebrowStyle()
                            .foregroundStyle(.white.opacity(0.85))
                        HStack(alignment: .center, spacing: JellytoneTheme.Space.md) {
                            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                                Text(current.name)
                                    .font(.jtScaledDetailTitle)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(current.artist)
                                    .font(.jtScaledBody.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: JellytoneTheme.Space.sm)
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.jtScaledSubsectionHeader)
                                .foregroundStyle(.black)
                                .frame(width: HomeMetrics.heroPlayDiameter, height: HomeMetrics.heroPlayDiameter)
                                .background(Circle().fill(.white))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(JellytoneTheme.Space.lg)
                }
                .frame(height: HomeMetrics.continueHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.heroCard, style: .continuous))
                .jtFloatingCardShadow()
                .contentShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.heroCard, style: .continuous))
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .accessibilityIdentifier("home-continue-listening")
            .accessibilityLabel("Continue listening to \(current.name) by \(current.artist)")
            .accessibilityHint(playback.isPlaying ? "Pauses playback" : "Resumes playback")
        }
    }

    @ViewBuilder private func continueArtwork(for track: Track) -> some View {
        if let image = playback.artwork {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            JellytoneTheme.placeholderGradient(hue: JellytoneTheme.placeholderHue(forID: track.id))
        }
    }
}

// MARK: - Cards

/// Compact quick-access row: artwork flush to a raised surface, title beside it.
private struct HomeQuickAccessCell: View {
    let itemID: String
    let imageTag: String?
    let title: String

    var body: some View {
        HStack(spacing: JellytoneTheme.Space.sm) {
            homeArtwork(itemID: itemID, imageTag: imageTag, name: title)
                .frame(width: HomeMetrics.quickAccessSide, height: HomeMetrics.quickAccessSide)
                .clipped()
            Text(title)
                .font(.jtScaledRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.trailing, JellytoneTheme.Space.sm)
        .frame(maxWidth: .infinity, minHeight: HomeMetrics.quickAccessSide, alignment: .leading)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.compactArtwork, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.compactArtwork, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.compactArtwork, style: .continuous)
                .strokeBorder(Color.jtBorder, lineWidth: 1)
        }
    }
}

private struct HomeHeroAlbumCard: View {
    let album: Album

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay {
                    GeometryReader { geo in
                        homeArtwork(itemID: album.id, imageTag: album.imageTag, name: album.name)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }
                .jtArtworkScrim()
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                Text(album.name)
                    .font(.jtScaledHeroCardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(album.artist)
                    .font(.jtScaledRowSubtitle)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(JellytoneTheme.Space.lg)
        }
        .frame(height: HomeMetrics.recentlyAddedHeroHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.heroCard, style: .continuous))
        .jtFloatingCardShadow()
        .contentShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.heroCard, style: .continuous))
        // `.contain` keeps the artwork's "No artwork for …" / "Artwork for …"
        // label in the tree (Home UI tests query it) while the card itself
        // still announces the album.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(album.name), \(album.artist), recently added album")
        .accessibilityHint("Opens album")
    }
}

private struct HomeArtistCircle: View {
    let artist: Artist

    var body: some View {
        VStack(spacing: JellytoneTheme.Space.sm) {
            homeArtwork(itemID: artist.id, imageTag: artist.imageTag, name: artist.name)
                .frame(width: HomeMetrics.artistCircleDiameter, height: HomeMetrics.artistCircleDiameter)
                .clipShape(Circle())
                .jtFloatingCardShadow()
            Text(artist.name)
                .font(.jtScaledRowSubtitle.weight(.semibold))
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: HomeMetrics.artistCircleDiameter)
        .accessibilityElement(children: .combine)
    }
}

/// Square cover with the title under the art, in semantic text colours, so the
/// same card reads in light and dark without white-on-artwork type.
private struct HomeCoverCard: View {
    let itemID: String
    let imageTag: String?
    let title: String
    let subtitle: String?
    var accessibilityLabel: String
    var accessibilityHint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
            homeArtwork(itemID: itemID, imageTag: imageTag, name: title)
                .frame(width: HomeMetrics.shelfArt, height: HomeMetrics.shelfArt)
                .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
                .jtFloatingCardShadow()
            Text(title)
                .font(.jtScaledRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.jtScaledRowSubtitle)
                    .foregroundStyle(Color.jtTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: HomeMetrics.shelfArt, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .modifier(HomeAccessibilityHint(hint: accessibilityHint))
    }
}

private struct HomeGenreTile: View {
    let genre: Genre

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            homeArtwork(itemID: genre.id, imageTag: genre.imageTag, name: genre.name)
                .frame(width: HomeMetrics.genreTileWidth, height: HomeMetrics.genreTileHeight)
                .clipped()
                .jtArtworkScrim(strength: 0.66)
            Text(genre.name)
                .font(.jtScaledRowTitle)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(JellytoneTheme.Space.md)
        }
        .frame(width: HomeMetrics.genreTileWidth, height: HomeMetrics.genreTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct HomeAccessibilityHint: ViewModifier {
    var hint: String?

    func body(content: Content) -> some View {
        content.accessibilityHint(hint ?? "")
    }
}

private struct HomeCarousel<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                content()
            }
            .scrollTargetLayout()
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            // Room for the floating-card shadow so the scroll view does not clip it.
            .padding(.vertical, JellytoneTheme.Space.sm)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

// MARK: - Skeletons

/// Placeholder blocks shown only on a cold start with nothing cached.
/// Background refreshes never show these — they stay silent behind the
/// cached shelves, and pull-to-refresh uses the system spinner alone.
private struct HomeSkeleton: View {
    enum Layout {
        /// Recently Added: full-width hero card + a row of covers.
        case heroAndCards
        /// Recently Played: the quick-access grid.
        case quickGrid
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
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous)
                                .fill(Color.jtSurface)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            case .quickGrid:
                VStack(spacing: JellytoneTheme.Space.md) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: JellytoneTheme.Space.md) {
                            ForEach(0..<2, id: \.self) { _ in
                                block(height: HomeMetrics.quickAccessSide, radius: JellytoneTheme.Radius.compactArtwork)
                                    .frame(maxWidth: .infinity)
                            }
                        }
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

// MARK: - Full-screen load/empty/error state

private struct HomeStateCard: View {
    let title: String
    let detail: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: JellytoneTheme.Space.md) {
            Text(title)
                .font(.jtScaledSubsectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.jtScaledBody)
                .foregroundStyle(Color.jtTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.jtCapsule(.primaryFlat))
                    .accessibilityIdentifier("home-retry")
            }
        }
        .padding(JellytoneTheme.Space.xl)
        .frame(maxWidth: 420)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous)
                .strokeBorder(Color.jtBorder, lineWidth: 1)
        }
        .padding(JellytoneTheme.Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
