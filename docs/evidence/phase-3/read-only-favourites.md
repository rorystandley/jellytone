# Phase 3 read-only favourites evidence

Status: Bounded destination slice complete; Phase 3 is not complete

Last updated: 2026-07-17

## Implemented boundary

- Library exposes an adaptive, read-only Favourites destination with separately
  paged Artists, Albums, and Tracks sections.
- Jellyfin requests are authenticated and scope `IsFavorite=true`, exact music
  item types, and the selected music-library parent. Results are mapped through
  app-owned domain models: malformed, unsupported, and explicitly contradictory
  favourite rows are excluded; absent optional user data remains compatible.
- Artist and album navigation reuse `ArtistView` and `AlbumView`. Track
  selections, Play All, and Shuffle delegate to AppModel and the authoritative
  PlaybackController queue; response-position occurrence IDs preserve duplicate
  tracks and selected displayed occurrence semantics.
- Per-section generations, cursors, errors, and snapshots keep paging,
  cancellation, refresh, retry, and server/account/library scope replacement
  independent. No favourite mutation, caching, download, offline sync, or
  playback-engine work was added.
- Diagnostics only allowlist `favourite_artists`, `favourite_albums`, and
  `favourite_tracks`; private identities, names, endpoints, libraries, and
  credentials are rejected.

## Deterministic coverage

`favourites.json` covers duplicate display names with distinct IDs, Unicode,
missing artwork and optional metadata, empty results, compilation and multi-disc
albums, no-playable-track sections, duplicate track occurrences, malformed and
unsupported siblings, contradictory and absent favourite flags, raw-row paging,
and server/account/library isolation. Focused mapping, state, playback, and
privacy tests add cancellation, expired authentication, partial failure, retry,
refresh, and stale-response checks.

## Executable evidence

The focused iPhone 17 Pro iOS 26.5 simulator unit command selected
`FavouritesGatewayTests`, `FavouritesFeatureStateTests`,
`FavouritesPlaybackIntegrationTests`, and `FavouritesDiagnosticsPrivacyTests`:
11 passed, zero failed.

`./scripts/bootstrap.sh`, `./scripts/test.sh`, `./scripts/test-integration.sh`,
`./scripts/build-release.sh`, and `git diff --check` completed for this batch.
The disposable Jellyfin 10.11.11 and 10.10.7 integration lanes exercised the
production gateway support suite. The Favourites UI test target builds, but
`./scripts/test-ui.sh` cannot start runtime tests in the current Xcode
environment: `DebuggerLLDB.DebuggerVersionStore.StoreError` leaves corrupt
xcresult bundles before test execution. This is an external local runner blocker,
not UI-pass evidence.

No physical-device run was required: this change does not alter audio engine,
background execution, Bluetooth, AirPlay, CarPlay, or system Now Playing. The
separate Phase 2 audible real-device blocker remains open.
