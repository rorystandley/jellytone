import Foundation

/// Builds Listen Now Instant Mix tiles. Favourite artists first; fill from
/// distinct recently played artists/tracks so an empty favourites list
/// still yields a useful Made for You shelf.
enum DiscoveryMixCatalog {
    static let shelfLimit = 8

    static func make(
        favouriteArtists: [Artist],
        recentlyPlayedTracks: [Track],
        limit: Int = shelfLimit
    ) -> [DiscoveryMix] {
        var mixes: [DiscoveryMix] = []
        var seenSeeds = Set<String>()

        for artist in favouriteArtists {
            guard mixes.count < limit else { break }
            guard seenSeeds.insert(artist.id).inserted else { continue }
            mixes.append(
                DiscoveryMix(
                    id: "mix-artist-\(artist.id)",
                    seedItemID: artist.id,
                    seedKind: .artist,
                    title: "\(artist.name) Mix",
                    subtitle: "Made for You",
                    artworkItemID: artist.id,
                    imageTag: artist.imageTag
                )
            )
        }

        for track in recentlyPlayedTracks {
            guard mixes.count < limit else { break }
            if let artistID = track.artistID {
                // A track whose artist is already a tile is the same seed.
                // Only tracks with no artist id become their own mix.
                guard seenSeeds.insert(artistID).inserted else { continue }
                mixes.append(
                    DiscoveryMix(
                        id: "mix-artist-\(artistID)",
                        seedItemID: artistID,
                        seedKind: .artist,
                        title: "\(track.artist) Mix",
                        subtitle: "Because You Listened",
                        artworkItemID: track.artworkItemID ?? track.albumID ?? artistID,
                        imageTag: track.imageTag
                    )
                )
                continue
            }
            guard seenSeeds.insert(track.id).inserted else { continue }
            mixes.append(
                DiscoveryMix(
                    id: "mix-track-\(track.id)",
                    seedItemID: track.id,
                    seedKind: .track,
                    title: "\(track.name) Mix",
                    subtitle: "Because You Listened",
                    artworkItemID: track.artworkItemID ?? track.albumID ?? track.id,
                    imageTag: track.imageTag
                )
            )
        }
        return mixes
    }
}

/// Jellyfin Instant Mix from a MusicArtist uses the artist's own `Genres`,
/// which are often empty even when the artist's tracks are tagged. Mixing
/// from a playable Audio seed (and starting that seed immediately) is the
/// reliable path — see AGENTS.md: PlaybackController remains the sole queue owner.
enum DiscoveryMixQueue {
    /// Mix tracks that should follow the song already playing. Drops the
    /// current item so expanding a mix never restarts or duplicates it.
    static func upcoming(from mixTracks: [Track], playing current: Track) -> [Track] {
        mixTracks.filter { $0.id != current.id }
    }
}
