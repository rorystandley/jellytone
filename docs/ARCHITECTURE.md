# Architecture Plan

Status: Minimum Working App implementation in progress

Last updated: 2026-07-16

This document defines the intended technical boundaries for the native Jellyfin
iOS music player. Phase 0 may refine specific technology choices through
architecture decision records, but it must preserve the product constraints and
state-ownership rules below.

## Architectural goals

- Reliable music playback in the foreground, background, offline, and across
  network changes.
- A fast cache-first interface that does not bind SwiftUI directly to the
  Jellyfin API.
- One authoritative queue and playback state shared by every platform surface.
- Deterministic persistence, migrations, tests, and project generation suitable
  for autonomous agent work.
- Minimal dependencies with pinned versions and owned abstraction boundaries.
- Privacy-preserving diagnostics capable of explaining self-hosted failures.

## Proposed platform baseline

- Swift and SwiftUI using the current stable toolchain selected in Phase 0.
- Proposed minimum iOS/iPadOS 18.4, confirmed or revised by the Phase 0 codec and
  device matrix.
- AVFoundation for remote and local playback.
- MediaPlayer for Now Playing and remote commands.
- URLSession and Network framework for APIs, streaming support, reachability,
  and background downloads.
- Keychain Services for access tokens.
- A SQLite-backed local store behind repository protocols.
- App Intents, WidgetKit, and CarPlay for platform integration.
- A declarative project specification, proposed to be XcodeGen `project.yml`,
  with generated project state treated as derived output.
- The official Jellyfin Swift SDK behind an application-owned gateway.

Versions and final persistence/project-generation choices require Phase 0
decision records. UI and domain code must not depend on those replaceable
details.

## Current vertical slice

The first runnable implementation keeps these boundaries as source folders in
one generated application target. It includes AppShell composition, stable
Domain models, a Keychain-backed JellyfinGateway, cancellable feature-owned
search state, feature views, and one Playback controller. Search and artist
browsing consume application-owned `Artist`, `Album`, and paged result models;
wire response models remain private to the gateway. Persistence, downloads,
extensions, and the full queue state machine remain future phase work.

To shorten the path to a device-runnable app, the gateway currently implements
only the required Jellyfin endpoints using `URLSession`, including music-only
artist/album search and artist-album queries. This is an interim adapter behind
the gateway boundary, not a reversal of the official SDK decision. The
replacement path is recorded in
[ADR 0014](decisions/0014-minimum-working-app-sequencing.md).

## Module boundaries

The intended package/target layout is:

### AppShell

Owns application lifecycle, dependency composition, navigation, scene handling,
server/profile selection, restoration entry points, and feature routing. It does
not contain Jellyfin request construction or playback algorithms.

### Domain

Owns stable app models and pure business rules:

- Server and account identity.
- Music libraries, artists, albums, tracks, genres, and playlists.
- Queue entries and playback policies.
- Download and offline mutation state.
- Sort, grouping, shuffle, repeat, endpoint, and source-selection rules.

Domain models must not expose generated SDK models, SwiftUI types, database rows,
or AVFoundation objects.

### JellyfinGateway

Owns:

- Official SDK configuration and generated API calls.
- Authentication, Quick Connect, sign-out, and token injection.
- Local discovery and server identity verification.
- Server-version/capability negotiation.
- API-to-domain mapping.
- Images, lyrics, library queries, playlists, favourites, playback reporting,
  and stream/transcode URL creation.
- WebSocket session support when a product feature requires it.

The gateway is protocol-driven so contract tests can exercise generated-client
changes without rewriting feature code.

### LibraryStore

Owns the SQLite-backed cache and search index:

- Server/account-scoped metadata.
- Artwork and lyric references.
- Home shelf snapshots.
- Queue and playback restoration.
- Playlist/favourite pending state.
- Schema migrations and data invalidation.

Secrets and downloaded audio never live in the metadata database.

### Playback

Owns the single authoritative playback state machine:

- Queue ordering, current index, shuffle source order, and repeat mode.
- Remote/local source planning.
- Direct Play/transcode selection.
- AVFoundation object lifecycle and next-item preloading.
- Gapless/crossfade behavior and compatibility fallback.
- Seeking, interruptions, route changes, buffering, and errors.
- Jellyfin start/progress/pause/stop reporting.
- Now Playing snapshots and remote-command routing.
- Queue and position persistence.

SwiftUI, CarPlay, widgets, and intents never own or reconstruct the queue.

### Downloads

Owns:

- Download plans for tracks, albums, artists, and playlists.
- Background URLSession identifiers and delegate restoration.
- Original/transcoded quality choice.
- Durable manifests, progress, retries, verification, and atomic completion.
- Storage accounting, eviction, orphan cleanup, and logout behavior.
- Resolution of a logical track to a verified local file.

### OfflineSync

Owns the ordered mutation outbox and reconciliation rules for favourites,
playlists, and playback events. Operations require stable idempotency identities
where supported, explicit retry classification, and deterministic conflict
behavior.

### PlatformIntegration

Owns adapters for:

- `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
- CarPlay templates and command routing.
- Siri and App Intents.
- Widget timelines and App Group communication.
- Deep links and platform restoration requests.

Extensions read small Codable snapshots and emit commands. They do not open the
main database, instantiate the Jellyfin gateway, or reach into the application
model.

### DesignSystem

Owns semantic colours, typography, spacing, controls, artwork presentation,
loading/empty/error states, motion policies, haptics, accessibility helpers,
preview fixtures, and screenshot-test hosts.

### Diagnostics

Owns structured logging, signposts, performance measurements, connection tests,
playback-decision reports, redaction, and user-exportable diagnostic bundles.
Redaction occurs before persistence, not only during export.

## State ownership

The application has four categories of state:

1. **Secret state:** Jellyfin access tokens in Keychain.
2. **Durable metadata state:** libraries, queue, restoration, and pending
   mutations in the local store.
3. **Durable media state:** downloaded audio, artwork, lyrics, and manifests in
   managed files.
4. **Live state:** active playback, network path, feature loading, and UI
   navigation in isolated observable models.

Each piece of data has one authoritative owner. Feature views observe domain
state and send intents; they do not perform API requests directly.

## Core data models

At minimum, stable domain identities are required for:

- `ServerProfile`: Jellyfin server ID plus verified endpoint candidates.
- `AccountProfile`: server-scoped user identity and Keychain token reference.
- `MusicLibrary`.
- `Artist` and `AlbumArtist`.
- `Album` with discs and ordered tracks.
- `Track` with media-source and audio-format summaries.
- `Playlist` and ordered playlist entries.
- `PlaybackQueue` and `QueueEntry` with original and shuffled order.
- `PlaybackSnapshot` for restoration and platform donation.
- `DownloadRecord` and versioned `DownloadManifest`.
- `PendingMutation` with ordering, retry, and conflict metadata.

All persisted records are scoped by server and account to prevent cross-server
identity collisions.

## Connection architecture

### Onboarding flow

1. Discover locally or receive a manual URL.
2. Normalize the URL without discarding a base path.
3. Perform an unauthenticated public-system-info request.
4. Capture Jellyfin server ID, version, product name, and canonical capabilities.
5. Validate TLS and redirects before collecting credentials.
6. Authenticate and store only the resulting token in Keychain.
7. Run a post-auth capability and music-library check.
8. Persist the endpoint as verified for that server ID.

An alternative LAN, public, or Tailscale endpoint is attached only after the
same unauthenticated server identity is proven. Credentials are never forwarded
across an unverified host redirect.

### Endpoint selection

Endpoint selection is a policy, not a single stored URL. It considers:

- Last successful endpoint.
- Current reachability and DNS result.
- TLS validity.
- User network policy and expensive/constrained path status.
- Measured connection setup, not permanent assumptions about LAN versus VPN.

An active stream is not switched between endpoints speculatively. Failover
creates a replacement source through the playback state machine and closes the
old Jellyfin session in order.

### Tailscale

The application does not embed Tailscale or authenticate a tailnet. When the
user's Tailscale VPN is connected, normal URLSession traffic reaches a Tailscale
IP or MagicDNS name. Onboarding explains that Jellyfin UDP discovery normally
does not cross subnet boundaries, so a Tailscale endpoint is entered manually.
Trusted Tailscale Serve HTTPS is preferred to certificate bypasses.

## Playback architecture

### Source planning

For each queue entry, a `PlaybackPlan` records:

- Logical track and media-source identity.
- Local verified file, if available.
- Direct Play or transcode decision.
- Stream URL/request and required authenticated headers.
- Audio format and expected duration.
- Quality policy and network constraints.
- Jellyfin play-session/reporting identifiers.
- Fallbacks and reasons suitable for redacted diagnostics.

The selection order is:

1. Verified matching offline file.
2. Direct Play source supported by the device and route policy.
3. Server transcode satisfying the active quality policy.
4. A user-facing, diagnosable failure.

### Player engine

`AVQueuePlayer` is the baseline for native local and HTTP playback. Phase 0 must
measure whether it meets gapless and preloading requirements for every advertised
format and Jellyfin delivery method.

Crossfade requires a prototype of overlapping prepared players or another
AVFoundation-native design. The decision record must cover:

- Remote and local compressed sources.
- Background behavior.
- Now Playing accuracy.
- Seeking and route changes.
- Cancellation and rapid queue replacement.
- Energy, memory, and buffering costs.
- Behavior when the next item cannot be prepared in time.

Unsupported transitions fall back predictably to non-crossfaded playback. The
UI must not claim a crossfade occurred when the engine could not perform it.

### Durable queue editing

Every occurrence in the playback queue is a `QueueEntry` with an opaque stable
UUID and a `Track`; track or Jellyfin item identity is not queue-entry identity.
This lets duplicate occurrences be jumped to, reordered, removed, shuffled, and
restored independently. Legacy track-array snapshots migrate by matching each
occurrence in order and are rewritten with entry identities on the next
authoritative persistence update.

Only `PlaybackController` mutates queue order. SwiftUI identifies an entry and
sends jump, move, remove, or clear intents. The current entry is never removable
through Up Next editing. Each mutation updates queue/index state, transport and
remote-command availability, Now Playing queue index/count, and the durable
snapshot in one main-actor transaction before another intent can run.

Shuffle has one explicit editing rule: jumping within the visible shuffled
order preserves shuffle, but any order/content mutation (reorder, remove, Clear
Up Next, Play Next, or Add to Queue) first adopts the visible order as canonical
and turns shuffle off. The app never maintains a hidden second order after an
edit. Repeat then applies to that edited canonical queue.
Enabling shuffle preserves playback history and the current index and randomizes
only upcoming entries. Clear Up Next compacts the queue to the current entry, so
repeat-all cannot unexpectedly wrap into hidden playback history.

Playback replacement tasks are serialized. A superseded preparation completes
any shielded Jellyfin start/stop cleanup before its successor negotiates a new
plan, so rapid jumps cannot cancel session closure or start an intermediate
entry after a newer intent.

### Reporting lifecycle

The reporting bridge emits ordered Jellyfin events for start, periodic progress,
pause/resume, seek, natural completion, replacement, error, and stop. Replacing a
track flushes or closes the previous play session before opening the replacement
session. A single serialized reporting tail prevents progress, closure, and a
successor start from overtaking one another. Reporting returns a bounded outcome
to the controller; failures remain diagnosable through an allowlisted local
schema without exposing endpoint or media identity. AVPlayer terminal failures
close the session, while stalls report their current paused/playing position
without falsely ending it. Offline reports enter the mutation outbox.

## Offline architecture

A download completes only after:

1. The background transfer returns successfully.
2. Expected response and content characteristics are validated.
3. The temporary file is moved atomically into managed storage.
4. The versioned manifest is committed.
5. The local source resolver can open and inspect the final file.

The manifest is the authority for whether an offline item is playable. A stray
file is not a download. A manifest pointing to a missing, partial, replaced, or
unreadable file is invalid and must be repairable or removable.

Mutations are scoped by server/account and replayed in order. Authentication
failure pauses reconciliation; permanent not-found or permission failures move
to a diagnosable terminal state; transient failures use bounded backoff. Agents
must define conflict behavior for each mutation type before implementing it.

## Platform surface architecture

The main application periodically and transactionally writes a small
`PlaybackSnapshot` and selected artwork to an App Group. Widgets and intents use
that bridge when the main process is not running. Commands are written as
versioned intents for the application or a supported background handler.

Platform surfaces share domain display models so artist, album, track, duration,
favourite, download, and quality state do not drift between SwiftUI, CarPlay,
Now Playing, offline views, and widgets.

Widgets are not a second Now Playing screen. They should provide high-value
entry points such as Resume, Favourites, or a selected playlist when WidgetKit's
update and interaction model can support the behavior honestly.

## Security architecture

- Keychain stores access tokens; the local database stores only token
  references and non-secret identity.
- Authenticated URLs and headers are redacted at construction boundaries before
  reaching logs.
- TLS trust uses platform validation. There is no accept-all delegate.
- Local HTTP support requires an explicit decision record covering App Transport
  Security, Local Network privacy, App Review, and user warning behavior.
- Redirects that change origin are revalidated before authentication continues.
- Diagnostic exports default to removing usernames, server addresses, item
  names, paths, and identifiers.
- Signing material, real media, production databases, and private fixtures are
  excluded from the repository.

## Testing architecture

The test pyramid includes:

- Pure unit/property tests for sorting, grouping, queue, shuffle, repeat,
  endpoint selection, source planning, manifests, and reconciliation.
- Mapping tests for every consumed Jellyfin response shape.
- Contract tests against disposable supported-version Jellyfin servers.
- Integration tests with synthetic audio libraries and controllable proxy/network
  failures.
- UI and screenshot tests using deterministic fixtures and injected clocks.
- Accessibility assertions and rendered output inspection.
- Audio-transition measurements using known waveforms.
- Simulator lifecycle and restoration tests.
- Agent-operated real-device background, route, AirPlay, Bluetooth, CarPlay, and
  endurance tests.
- Release archive, migration, and clean-checkout reproducibility tests.

Tests must be runnable through stable scripts documented in `AGENTS.md` and used
by CI. Evidence reports record device, OS, Jellyfin version, media fixture,
network route, command, result, and limitations.

## Dependency policy

- Prefer Apple frameworks and the official Jellyfin SDK.
- Add a dependency only behind an owned interface and only when it materially
  reduces risk or implementation complexity.
- Pin versions; do not track moving branches.
- Record licence, maintenance status, platform support, privacy behavior, binary
  content, and replacement cost.
- Generated API models remain quarantined in `JellyfinGateway`.
- A dependency update requires contract tests and a regeneration diff review.

## Required Phase 0 decisions

Create architecture decision records for:

1. Minimum iOS/iPadOS and supported device set.
2. Supported Jellyfin server versions and SDK pin.
3. XcodeGen/project generation and generated-project commit policy.
4. SQLite implementation and migration strategy.
5. Playback engine, preloading, gapless, and crossfade.
6. Direct Play capability detection and transcode profiles.
7. Local HTTP, TLS, redirects, and endpoint failover.
8. Artwork, lyrics, metadata caching, and eviction.
9. Offline manifest and mutation reconciliation.
10. Diagnostics, crash reporting, and privacy.
11. App Group snapshot and platform-command bridge.
12. CI, test-server provisioning, real-device automation, signing, and release.

Until a decision is proven, code should depend on the stable boundary described
here rather than assuming one candidate implementation is permanent.
