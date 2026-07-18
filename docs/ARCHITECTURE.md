# Architecture

Status: boundary and invariant authority
Last updated: 2026-07-18

## Goals

- One trustworthy playback and queue state across app and system surfaces.
- Fast cache-first browsing without confusing stale account/library data.
- Jellyfin and persistence details isolated behind application-owned models.
- Fail-closed connection security and redacted diagnostics.
- Small native iPhone/iPad application with deterministic agent-operated proof.

The deployment target is iOS/iPadOS 18.4. `project.yml` is authoritative for
project generation and GRDB is the only application package dependency.

## Modules

### App

Owns lifecycle, dependency composition, active session/library, navigation,
restoration entry points, and cross-feature intents. It may coordinate domain
services but does not construct Jellyfin requests or own AVFoundation state.

### Domain

Owns stable models and pure rules: server/account/library scope, music metadata,
paged occurrences, queue entries, shuffle/repeat, cache merge, validation, and
mutation reconciliation. Domain models expose no SwiftUI, GRDB, AVFoundation,
or Jellyfin wire types.

### JellyfinGateway

Owns authentication/token injection, public server identity, music-only queries,
mapping, artwork, playback planning/reporting, and the bounded write endpoints
that are actually shipped. All request tasks are cancellable; wire models remain
private. Authenticated redirects or alternate endpoints require proven server
identity and must not leak credentials across origins.

### LibraryStore

Owns the GRDB database, migrations, server/account/library-scoped metadata,
cache replacement, search, Home/track snapshots, and durable pending mutations.
Secrets and downloaded audio never belong in this database. Invalid rows are
ignored or rejected without crossing scopes.

### Playback

Owns the only queue and player state machine: ordering, current occurrence,
shuffle/repeat, restoration, source planning, AVPlayer lifecycle, seeking,
interruptions, route changes, reporting, Now Playing snapshots, and remote
commands. Views send intents and observe state; they never reconstruct a queue.

### Features

Owns SwiftUI presentation and feature-scoped cancellable loading state. A state
scope includes server, account, selected library, and stable destination ID as
applicable. Generation checks discard late responses after navigation or scope
changes. Occurrence identity remains separate from logical track identity.

### Design system

Owns semantic colour and materials, typography, spacing, shape, artwork
presentation, feedback, motion, loading/empty/error patterns, accessibility
helpers, preview fixtures, and screenshot hosts. Feature screens compose these
shared primitives; they do not invent unrelated local styling. Reduce Motion,
Dynamic Type, contrast, and missing artwork are first-class variants.

### Diagnostics

Owns allowlisted structured events, failure classification, signposts, and
redaction before persistence. Event fields never contain tokens, credentials,
server addresses, usernames, item IDs/titles, library content, or authenticated
URLs.

Deferred modules such as Downloads, OfflineSync, CarPlay, widgets, and intents
must not be scaffolded merely to imply product completeness. Add them only with
an approved product slice and an ADR defining their boundary.

## State ownership

There are four state classes:

1. Secret: access token in Keychain.
2. Durable metadata: cached library values, queue/restoration, and shipped
   pending mutations in GRDB/UserDefaults as defined by their ADR.
3. Durable media: future verified managed downloads; none exist in 1.0.
4. Live: active player, navigation, network work, and feature presentation.

`AppModel` owns the active session, selected library, and application-level
presentation. Feature states own their requests. `LibraryStore` owns durable
rows. `PlaybackController` owns all queue/player state. Views own no independent
server truth.

## Primary flows

### Connect and restore

```text
manual URL -> normalize -> public identity -> authenticate -> Keychain token
           -> active session -> music libraries -> cached/server presentation
```

On launch, restore non-secret profile metadata and fetch the token from
Keychain. An invalid/missing token returns to sign-in. Sign-out stops active
work/playback, invalidates the server token when possible, deletes Keychain and
profile state, and prevents stale responses from repopulating the session.

HTTP is allowed only through the narrowly documented local/Tailscale policy.
Certificate validation is never bypassed and HTTPS is never silently downgraded.

### Browse and cache

```text
feature scope -> bounded cache read -> immediate domain values
              -> cancellable Jellyfin page -> validate/map
              -> generation check -> present and atomically persist
```

First-page replacement and later-page append use a generation identity. Server,
account, and library form the minimum persistence scope. Server pagination
offsets advance by raw rows so rejected records do not stall paging. Duplicate
track/playlist occurrences are preserved while stable artist/album identities
may be deduplicated by server ID.

### Playback

```text
selected occurrence -> authoritative QueueEntry list -> source plan
                    -> prepare AVPlayer -> audio session -> playback
                    -> UI + Now Playing + reports + durable snapshot
```

The controller prepares before changing visible playback state, serializes
reporting around lifecycle transitions, and uses generation guards so an old
preparation/report cannot mutate a replacement session. Restoration prepares at
the saved position but never auto-plays. Queue edits preserve per-occurrence
identity, including duplicate tracks.

Direct Play is preferred when compatible; a single-stream AAC-in-MP4 transcode
is the current safe fallback. Unsupported gapless/crossfade behavior is an
ordinary diagnosable hard cut, not a release claim.

### Durable writes

```text
validate intent -> optimistic overlay -> scoped/coalescing outbox
                -> read/compare/write -> complete, retry, auth pause, or conflict
```

A write surface may ship only if pending work resumes after launch/authentication,
success clears optimistic state, retries are bounded and deterministic, conflicts
have an explicit user-visible resolution, and logs contain no private values.
If those conditions are not met, remove or hide the write UI for the release.

## Security and privacy invariants

- Passwords are request-local and never persisted.
- Tokens live only in Keychain and authenticated headers, never URLs or logs.
- Alternative endpoints receive no authenticated request before server identity
  matches the saved public identity.
- TLS failures are explained but never bypassed.
- Fixtures are synthetic and deterministic.
- Cache and mutations are isolated by server/account/library as applicable.
- Diagnostics redact before storage/export, not only at presentation.

## Testing architecture

- Pure unit/property tests for domain, queue, restoration, reconciliation, and
  failure classification.
- Synthetic mapping/persistence fixtures for malformed and adversarial metadata.
- Disposable Jellyfin 10.10.7 and 10.11.11 contracts for real request behavior.
- UI/accessibility tests for primary destinations and failure recovery.
- Simulator tests for representative app integration.
- Physical-device evidence for audible/background/route behavior.

The stable gate scripts are listed in `AGENTS.md`. A test-runner crash is a gate
failure even when the app compiles. Hardware-only behavior remains blocked until
an agent can execute and capture it.

## Durable decisions

ADRs in `docs/decisions/` remain authoritative for platform/server baselines,
project generation, persistence, playback, connectivity, caching, offline
design, diagnostics, extension boundaries, release automation, dependencies,
minimum-app sequencing, and track catalogue ordering. Update or supersede the
relevant ADR whenever one of those choices changes.
