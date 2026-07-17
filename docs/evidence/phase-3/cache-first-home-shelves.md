# Cache-first recent Home shelves

## Scope

This bounded brought-forward Phase 3 slice adds Recently Added albums and
Recently Played tracks. Continue Listening remains the active playback-session
card. It does not implement downloads, offline playback, recommendations, or
playback-engine changes.

## Executable evidence

- `HomeGatewayTests` use synthetic fixtures with duplicate names, Unicode,
  missing art and optional metadata, malformed records, bounded request limits,
  reverse-proxy paths, cancellation, and authenticated music-only queries.
- `HomeShelfPersistenceTests` prove migration, repeat-launch cache, atomic
  replacement, malformed cache containment, server/account/library isolation,
  cache retention after failure, and stale-refresh suppression.
- `HomeFeatureStateTests` prove cache-first presentation and scope race
  rejection; `HomeUITests` cover compact/regular, dark, large type, Reduce
  Motion, VoiceOver labels, loading, empty, error, retry, cached partial error,
  missing artwork, Album navigation, and authoritative track action.
- `ProductionGatewayHarness` exercises the two Home queries in disposable
  Jellyfin 10.11.11 and 10.10.7 lanes through `test-integration.sh`.

No production diagnostics, fixtures, or Home accessibility text contain private
library data, usernames, URLs, headers, or tokens. Device testing is not needed:
this slice changes no device-only audio lifecycle or hardware integration.
