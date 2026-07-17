# ADR 0014: Minimum Working App sequencing

Status: Accepted

Date: 2026-07-16

## Context

Phase 0 accumulated useful device and protocol evidence before the repository
had a usable product surface. The immediate priority is now a small connected
path: server URL, password authentication, music browsing, and track playback.
Pulling the complete generated Jellyfin SDK surface into that first slice would
expand dependency and mapping work before this flow could be exercised.

Security constraints still apply. Tokens remain in Keychain, credentials and
server details must not enter logs or fixtures, HTTPS must not be weakened, and
API details must stay behind the gateway boundary.

## Alternatives

1. Finish every Phase 0 hardware proof before app work.
2. Integrate the full official SDK before exposing product UI.
3. Implement the minimum endpoints with `URLSession` behind the owned gateway,
   then replace the transport incrementally with the pinned official SDK.

## Decision

Use alternative 3 for the Minimum Working App. The interim adapter covers only
public server info, password authentication, music views, albums, tracks,
artwork, and direct audio streaming. Feature views consume domain models and do
not construct Jellyfin requests.

The delivery override lets remaining Phase 0 device gates run after the first
working slice; it does not mark them complete or waive later acceptance gates.

## Consequences

- A real app can be installed and exercised sooner.
- Reverse-proxy paths and authentication behavior remain owned and tested.
- The adapter creates migration work and lacks broad SDK model/version coverage.
- The gateway boundary confines that migration to one module.

## Validation

- Unit tests intercept authentication and library responses and validate domain
  mapping without private data.
- URL tests prove reverse-proxy paths are preserved and artwork tokens stay out
  of query strings.
- UI automation proves the connection surface launches in the simulator.
- Release and signed-device builds prove the project compiles for both targets.

## Rollback and migration

Replace individual `JellyfinAPI` operations with the pinned official SDK while
keeping gateway method signatures and domain models stable. Remove temporary
wire types after equivalent contract tests pass. No database migration is
needed because this slice persists only a Keychain token and non-secret
connection preferences.

Clarification (2026-07-17): that statement describes the original Minimum
Working App slice. The subsequent cache-backed library/search slice activates
ADR 0004's SQLite migration while keeping this ADR's gateway and domain
boundaries stable.
