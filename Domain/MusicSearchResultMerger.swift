import Foundation

/// Combines cache-first search results with a server refresh without exposing
/// persistence or transport types to callers.
enum MusicSearchResultMerger {
    /// Cached positions are stable so an on-screen cache-first result does not
    /// jump when the refresh arrives. A matching server result replaces the
    /// cached value in place, then server-only values are appended in server
    /// order. IDs are compared exactly because they are domain identities;
    /// display-name case and Unicode normalization never affect identity.
    ///
    /// Pagination metadata is always copied from `server`. Cached rows do not
    /// consume server offsets, so subsequent pages can use the server-provided
    /// `nextStartIndex` without compensating for cache contents.
    static func merge(cached: MusicSearchPage, server: MusicSearchPage) -> MusicSearchPage {
        MusicSearchPage(
            artists: merge(cached: cached.artists, server: server.artists),
            albums: merge(cached: cached.albums, server: server.albums),
            hasMore: server.hasMore,
            nextStartIndex: server.nextStartIndex
        )
    }

    private static func merge<Value: Identifiable>(cached: [Value], server: [Value]) -> [Value]
    where Value.ID: Hashable {
        var values: [Value] = []
        var positions: [Value.ID: Int] = [:]

        for value in cached where positions[value.id] == nil {
            positions[value.id] = values.count
            values.append(value)
        }

        var serverIDs = Set<Value.ID>()
        for value in server where serverIDs.insert(value.id).inserted {
            if let position = positions[value.id] {
                values[position] = value
            } else {
                positions[value.id] = values.count
                values.append(value)
            }
        }

        return values
    }
}
