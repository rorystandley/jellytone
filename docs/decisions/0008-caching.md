# ADR 0008: Metadata, artwork, and lyrics caching

- Status: Accepted for implementation
- Date: 2026-07-16

## Context

Warm launch must be cache-first without allowing unbounded artwork/media growth
or mixing accounts. Offline-authoritative assets must not be evicted as cache.

## Alternatives

- One database/blob cache: simple addressing but large migrations and poor file
  lifecycle behavior.
- SQLite metadata plus content-addressed files: transactional references with
  efficient filesystem storage.
- URLCache only: insufficient ownership, offline policy, and diagnostics.

## Decision

Store metadata, shelf snapshots, search index, and asset references in SQLite.
Store artwork and lyrics as content-addressed files with verified byte count,
digest, media type, source version, last access, and account scope. Use separate
cache and offline namespaces. Evict cache assets by budgeted LRU while pinning
active queue, visible/restoration, favourite, and download dependencies.

## Consequences

UI reads a consistent cached snapshot immediately and refreshes quietly.
Missing/corrupt files invalidate their references and are fetched or represented
by deterministic fallbacks. Logout removes the account namespace.

## Validation

Tests must cover warm launch, account isolation, budget pressure, missing and
corrupt assets, concurrent reads during eviction, logout, and missing artwork.

## Rollback and migration

Cache files can be discarded and rebuilt. Schema changes migrate references
transactionally; offline assets are never deleted by cache recovery.

## Implementation status (2026-07-19)

Shipped first slice: `ArtworkCache` (NSCache + files in the system Caches
directory, keys scoped `serverID_itemID`), read-through from
`AuthenticatedArtworkView`, size reporting and manual purge in Settings, and a
full clear on logout. The OS may evict the directory under storage pressure.
Not yet implemented from the decision above: budgeted LRU eviction, digests and
byte-count verification, SQLite asset references, per-account (rather than
per-server) namespaces, offline pinning, and lyrics assets. Detail metadata
snapshots (album tracks, playlist entries — `detail_track_snapshots`, migration
007) and ordered album pages (`sort_index`, migration 006) landed in SQLite per
the decision.
