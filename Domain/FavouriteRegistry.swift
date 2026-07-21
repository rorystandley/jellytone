import Foundation

/// Effective favourite ("like") state for the current session, merging durable
/// server truth with optimistic, not-yet-reconciled user intent.
///
/// The Jellyfin `FavoriteItems` endpoint and the favourite outbox row are both
/// keyed only by item ID, so a single registry covers songs, albums, and
/// artists alike. Pending intent always wins over server truth so an optimistic
/// toggle is never reverted by a concurrent load that lands before the outbox
/// reconciles.
struct FavouriteRegistry: Equatable, Sendable {
    private(set) var favourites: Set<String> = []
    private var pending: [String: Bool] = [:]

    func isFavourite(_ id: String) -> Bool { favourites.contains(id) }

    /// Seed unsynced desired state from the durable outbox at session start.
    mutating func applyPending(_ desired: [String: Bool]) {
        for (id, want) in desired {
            pending[id] = want
            apply(id, want)
        }
    }

    /// Merge authoritative server truth for the `observed` item IDs. IDs with
    /// pending intent keep that intent; the rest follow the server verbatim,
    /// which also lets a stale favourite fall back to false.
    mutating func applyServerTruth(favourited: Set<String>, observed: Set<String>) {
        for id in observed {
            if let want = pending[id] {
                apply(id, want)
            } else {
                apply(id, favourited.contains(id))
            }
        }
    }

    /// Record an optimistic user choice and return the desired state.
    @discardableResult
    mutating func setDesired(_ id: String, _ desired: Bool) -> Bool {
        pending[id] = desired
        apply(id, desired)
        return desired
    }

    /// Flip the current effective state and return the new desired value.
    @discardableResult
    mutating func toggle(_ id: String) -> Bool {
        setDesired(id, !favourites.contains(id))
    }

    /// Replace the pending overlay wholesale — e.g. after reconciliation, with
    /// the rows that remain unsynced. Effective favourites are left untouched
    /// because they already reflect the optimistic intent.
    mutating func replacePending(_ desired: [String: Bool]) {
        pending = desired
    }

    private mutating func apply(_ id: String, _ favourite: Bool) {
        if favourite { favourites.insert(id) } else { favourites.remove(id) }
    }
}
