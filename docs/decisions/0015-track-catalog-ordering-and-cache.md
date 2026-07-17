# ADR 0015: Deterministic paged track catalog

- Status: Accepted for the brought-forward Phase 3 track-browsing slice
- Date: 2026-07-17

## Context

The Library needs a music-only track destination stable across Jellyfin pages,
repeat launches, malformed rows, and duplicate logical tracks. Wire rows must
not cross into SwiftUI or persistence, and later pages must not replace an
active playback queue.

## Decision

Request `Audio` items scoped by user and music-library `ParentId`, with
`SortName,Id` ascending and no total-count dependency. Map valid rows to
`TrackCatalogOccurrence` values whose ordinal occurrence identity is separate
from `Track.id`. Reapply the versioned POSIX-normalized title, artist, album,
track-ID, then ordinal comparator when merging pages. Store the first page as a
new generation and append only pages matching that generation and scope.

## Consequences and validation

Equal names and repeated logical tracks remain deterministic and selectable.
The first cached screen is bounded by SQL `LIMIT`; failed refreshes retain the
last committed page. Selection builds a new authoritative queue from displayed
occurrences. Unit tests cover ordering, tie-breaking, overlapping pages,
bounded reads, scope isolation, and migration preservation; disposable
Jellyfin 10.10.7 and 10.11.11 contracts validate the request. Migration 003 is
forward-only and its tables are isolated from existing cache data.
