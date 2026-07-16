# Jellyfin iOS Music Player Product Plan

Status: Planning authority

Last updated: 2026-07-16

Implementation status: Phase 0 proof and decision records in progress

This document is the product and delivery source of truth for the repository. All
implementation agents must read it before planning or changing code. If a task
conflicts with this document, the task must explicitly update the plan rather
than silently broadening the product.

## Mission

Build a native iPhone and iPad music player for personal Jellyfin servers that
delivers the speed, resilience, polish, and system integration people expect
from a premium service such as Spotify.

The product is music-only. It is not a general Jellyfin client.

## Delivery model

The application will be implemented, tested, integrated, documented, and
prepared for release by AI coding agents. The plan must not assume that a human
will write code, inspect a screen, perform QA, resolve merge conflicts, provision
a test environment, or notice an incomplete edge case.

Consequences of this model:

- Every phase ends in machine-verifiable acceptance criteria and captured
  evidence, not a human approval gate.
- Visual quality is checked through deterministic fixtures, screenshot tests,
  rendered screenshots, accessibility audits, and agent inspection.
- Broad phases are split into bounded ownership slices. The coordinating agent
  remains responsible for integration and the complete validation gate.
- Commands required for validation must be scripted and non-interactive wherever
  the platform permits.
- An unavailable device, signing identity, entitlement, Apple approval, or test
  server is an explicit external dependency. It must be recorded as a blocker;
  an agent must not quietly replace required real-device evidence with a
  simulator result.
- Completion claims must include the exact commands run, relevant results,
  remaining risks, and repository status.

Repository-wide operating rules are in [AGENTS.md](AGENTS.md). Technical
boundaries are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Product scope

### Included in version 1.0

#### Servers and accounts

- Add a server by local discovery or full manual URL.
- Support ports, IPv4, IPv6, `.local` names, reverse-proxy base paths, and
  trusted HTTPS endpoints.
- Work through an already-connected Tailscale VPN using IP addresses, MagicDNS,
  or Tailscale Serve HTTPS.
- Authenticate with username/password and Jellyfin Quick Connect.
- Store access tokens in Keychain and discard passwords after authentication.
- Support multiple Jellyfin servers and multiple user profiles.
- Associate alternative endpoints only after proving that they expose the same
  Jellyfin server ID.
- Diagnose DNS, transport, TLS, server identity, authentication, API
  compatibility, artwork, and media reachability separately.

#### Home

- Continue listening when Jellyfin exposes useful music progress.
- Recently played and recently added.
- Favourite artists, albums, and tracks.
- Frequently played music.
- Library-derived mixes, genre radio, and random discovery.
- Downloaded music.
- Cache-first presentation on repeat launches.

#### Library and search

- Artists, album artists, albums, compilations, tracks, playlists, genres,
  favourites, and downloads.
- Correct multi-disc, album-artist, compilation, and track ordering.
- Sort, filter, grid/list layouts, and alphabetical navigation.
- Fast local search over cached metadata, merged with server search results.
- Search filters for artist, album, track, playlist, genre, and library.
- Playlist creation, editing, reordering, and track membership management.
- Context actions: Play, Shuffle, Play Next, Add to Queue, Add to Playlist,
  Favourite, Download, Go to Album, and Go to Artist.

#### Playback

- Persistent mini-player and full Now Playing presentation.
- Play, pause, seek, previous, next, shuffle, repeat-one, and repeat-all.
- Durable reorderable queue with Play Next and Add to Queue.
- Queue and current-position restoration after process termination.
- Preloading of the next track.
- Proven gapless playback for supported album transitions.
- Configurable crossfade, with a clearly documented compatibility fallback.
- Sleep timer.
- Direct Play whenever the device supports the source.
- Jellyfin audio transcoding when the source is incompatible or constrained by
  the selected quality policy.
- Separate quality policies for Wi-Fi, cellular/expensive networks, remote
  access, and downloads.
- Playback start, progress, pause, and stop reporting to Jellyfin.
- Synchronized and unsynchronized lyrics, including tap-to-seek for timed
  lyrics.
- Optional technical information showing source format, output format, bitrate,
  sample rate, bit depth, and Direct Play/transcode status.
- Correct interruption and route-change behavior for calls, Siri, headphones,
  Bluetooth, AirPlay, network changes, and server restarts.

#### Offline listening

- Download tracks, albums, artists, and playlists.
- Download original media or a user-selected space-efficient server transcode.
- Background transfers that survive suspension and operating-system relaunch.
- Pause, resume, retry, cancellation, and per-item progress.
- Wi-Fi-only, charging-preferred, and storage-limit settings.
- Atomic completion so partial files are never exposed as playable downloads.
- A durable manifest containing server, user, item, media-source version,
  quality, byte count, and local-file identity.
- Offline Home, Library, Search, artwork, lyrics, queue, and playback.
- An offline mutation outbox for favourites, playlist changes, and playback
  events, with deterministic reconciliation rules.
- Seamless selection of a verified local file when the active endpoint becomes
  unavailable.

#### Apple platform integration

- Background audio.
- Lock Screen and Control Centre Now Playing information and commands.
- Headphone, Bluetooth, and external accessory remote commands.
- AirPlay.
- CarPlay browse, search where permitted, and Now Playing.
- Siri and App Intents for playlists, artists, favourites, shuffle, and resume.
- Useful Home Screen and Lock Screen widgets without duplicating the system Now
  Playing interface.
- Deep links and state restoration.
- Native iPad layouts, keyboard navigation, and pointer support.

#### Premium quality

- Immediate cached UI followed by quiet server refresh.
- Artwork-driven presentation with deterministic contrast and accessible
  fallbacks.
- Consistent gestures, haptics, animations, menus, loading states, empty states,
  and error recovery.
- VoiceOver, Dynamic Type, Reduce Motion, Reduce Transparency, sufficient
  contrast, and minimum touch-target support.
- Localised user-facing strings from the first releasable build.
- Redacted diagnostics that can explain connection and playback decisions
  without exposing private library or credential data.

### Explicit non-goals

- Video playback or browsing video libraries.
- Audiobooks, podcasts, chapters, or spoken-audio playback modes.
- Subtitles, Picture in Picture, HDR, video transcoding, or video codecs.
- A global licensed music catalogue.
- Social following or public listening profiles.
- Server administration.
- Automatic Tailscale account management or an embedded VPN.
- Treating a simulator-only result as proof for Bluetooth, AirPlay, CarPlay,
  background suspension, or long-duration playback.

### Candidates after 1.0

- Apple Watch remote control and offline music.
- Jellyfin SyncPlay and remote-session control.
- Smart downloads and automatically refreshed offline mixes.
- Chromecast after dependency, licensing, privacy, and reliability review.
- Advanced equalisation and ReplayGain controls if the selected playback engine
  can provide them without sacrificing streaming or background reliability.
- SharePlay or handoff-style queue transfer.
- Optional scrobbling integrations.
- Native macOS and tvOS music clients sharing domain packages.

## Experience architecture

The primary navigation is:

1. Home
2. Search
3. Library

The mini-player persists above the primary navigation whenever a queue exists.
Downloads are a first-class Library destination, not a disconnected settings
screen. Server/profile selection belongs in the account surface and must never
interrupt active offline playback.

The full Now Playing surface provides artwork, metadata, transport controls,
scrubbing, quality status, favourite state, lyrics, AirPlay route selection,
queue access, and contextual actions. Common actions must remain reachable with
one hand and must not depend on hidden swipe gestures.

## Product principles

1. **Playback is the product.** A beautiful library does not compensate for an
   unreliable queue, background session, or transition between tracks.
2. **Offline is a mode, not a separate app.** The same library and player choose
   the best verified source without making the user change mental models.
3. **Self-hosted failures must be explainable.** Distinguish DNS, VPN, TLS,
   authentication, server, codec, transcode, and local-file failures.
4. **Direct Play first, never at the cost of reliability.** Request a server
   transcode when the device, container, route, or quality policy requires it.
5. **One state across every surface.** The app, Lock Screen, CarPlay, widgets,
   and intents consume the same playback and display models.
6. **Privacy is a default.** Do not require a product backend or collect library
   content to make the app useful.
7. **Native behavior beats novelty.** Prefer system conventions, accessibility,
   and predictable controls over ornamental interaction.

## Quality targets

These are release goals and must be measured in automated or agent-operated
beta workflows:

- At least 99.8% crash-free sessions.
- At least 99.5% successful playback starts for the supported media matrix.
- Cached Home content visible within 500 ms on a warm launch on the baseline
  performance device.
- Queue order and current position restored within two seconds of relaunch.
- Position reporting and restoration error no greater than two seconds under
  normal termination.
- Eight hours of locked-screen playback without an unexpected stop.
- Offline cold launch and playback with every network path disabled.
- Background downloads survive suspension, process eviction, and relaunch.
- No access token, password, authenticated media URL, or unredacted server
  address in logs or exported diagnostics.
- All supported user flows are operable with VoiceOver and the largest supported
  accessibility text sizes.

Network-dependent start latency must be reported as application overhead plus
observed network time. Agents must not promise a global remote-start latency that
the app cannot control.

## Compatibility matrix

Phase 0 must create and commit a versioned compatibility matrix covering:

- The current stable Jellyfin release and the previous supported release.
- The proposed minimum iOS/iPadOS release and the current public release.
- MP3, AAC, ALAC, FLAC, Ogg/Vorbis, and Opus.
- Original and transcoded streams.
- Single-disc, multi-disc, compilation, missing-artwork, and malformed-metadata
  libraries.
- Plain local HTTP only if an approved App Transport Security design exists.
- Trusted HTTPS reverse proxies, base paths, redirects, IPv4, IPv6, `.local`,
  Tailscale MagicDNS, and Tailscale Serve HTTPS.
- Wi-Fi, cellular/expensive paths, Low Data Mode, unavailable VPN, captive
  network, server sleep, server restart, expired token, and offline operation.
- Built-in speaker, wired output, Bluetooth, AirPlay, and CarPlay.

The minimum OS and advertised Jellyfin versions are proposals until this matrix
has executable evidence. Version claims must be updated when dependencies or
server contracts change.

## Phased roadmap

Durations are estimates for sequencing, not exit criteria. Agents progress only
when the phase gate is satisfied.

### Phase 0: Product proof and decision records

Estimated duration: 3 weeks

Deliverables:

- Confirm the minimum OS and supported Jellyfin versions.
- Pin the official Jellyfin Swift SDK version or record a justified alternative.
- Prove local discovery, manual URL, base-path, Quick Connect, credential login,
  and Tailscale MagicDNS/HTTPS connectivity.
- Prove Direct Play and server-transcoded playback for the audio matrix.
- Prototype next-item preloading, genuine gapless behavior, and crossfade for
  both local and remote sources.
- Prove background audio, remote commands, route changes, and background
  downloads on real hardware.
- Define the security position for local HTTP and untrusted certificates.
- Request the CarPlay audio entitlement and record its external status.
- Create architecture decision records for project generation, persistence,
  playback engine, caching, diagnostics, and dependency policy.
- Create deterministic Jellyfin test-server fixtures and reset scripts.

Exit gate:

- Every proof has a reproducible command or agent-operable procedure.
- Results and limitations are committed under `docs/evidence/phase-0/`.
- Open risks have an owner phase and fallback behavior.
- No critical capability is accepted solely because an API appears to support
  it.

### Phase 1: Deterministic foundation

Estimated duration: 4 weeks

Deliverables:

- Declarative Xcode project generation and pinned toolchain dependencies.
- Modular targets described in the architecture document.
- CI for formatting, linting, unit tests, project regeneration, simulator build,
  and secret scanning.
- Scripted bootstrap, test, integration-test, UI-test, and release-build entry
  points.
- Stable domain models independent of generated Jellyfin SDK models.
- Keychain-backed credentials, SQLite-backed cache, structured logging, feature
  flags, and dependency injection.
- Deterministic fixtures, preview data, and test clocks.
- Initial design system and accessibility helpers.

Exit gate:

- A clean checkout can bootstrap and run the complete foundation test suite with
  one documented command.
- Re-generating the Xcode project produces no unexplained diff.
- CI and local scripts execute the same gates.
- Secrets and private server data cannot enter fixtures or logs.

### Phase 2: Connected playback vertical slice

Estimated duration: 5 weeks

Deliverables:

- Add/discover a server, authenticate, select a music library, browse an album,
  and start a track.
- Background playback, Lock Screen metadata, remote commands, seeking, next and
  previous.
- Direct Play/transcode planning and Jellyfin playback reporting.
- Cache enough metadata and artwork to restore the active album and queue.
- Explain authentication, network, and playback failures in the UI and
  diagnostics.

Exit gate:

- The vertical slice passes unit, contract, integration, UI, simulator, and
  real-device playback tests.
- App termination and relaunch restore the queue and position.
- The test server shows correct start/progress/stop session behavior.
- The same display and playback model drives the app and system Now Playing
  surface.

### Phase 3: Complete music library experience

Estimated duration: 6 weeks

Deliverables:

- Home, Search, Library, artist, album, playlist, genre, favourites, and download
  destinations.
- Local search merged with server results.
- Multi-server and multi-profile switching.
- Playlist and favourite writes.
- Durable queue editing, shuffle, repeat, Play Next, and Add to Queue.
- Timed and untimed lyrics.
- Native iPhone and iPad navigation, context menus, empty states, and errors.

Exit gate:

- Library fixtures cover large libraries, compilations, multi-disc albums,
  missing art, duplicate names, unusual Unicode, and malformed metadata.
- Every write operation has success, retry, conflict, and authentication-expiry
  tests.
- Screenshot and accessibility suites cover every primary destination at
  compact and regular widths.

### Phase 4: Premium playback

Estimated duration: 5 weeks

Deliverables:

- Proven gapless transitions and documented unsupported cases.
- Configurable crossfade with safe fallbacks.
- Queue prefetching and network-aware buffering.
- Sleep timer.
- Audio quality policies and technical playback information.
- Interruption, route, Bluetooth, AirPlay, and server-restart hardening.
- Performance, memory, energy, and long-duration playback diagnostics.

Exit gate:

- Automated audio-transition fixtures measure unintended gaps and overlap.
- Eight-hour locked-screen and network-transition endurance scenarios pass on
  real hardware.
- No queue replacement race leaves an orphan Jellyfin playback session.
- Playback behavior is consistent across app, Lock Screen, accessories, and
  AirPlay.

### Phase 5: Offline and network resilience

Estimated duration: 5 weeks

Deliverables:

- Background download manager, manifest, verification, and atomic storage.
- Album, artist, playlist, and track download planning.
- Offline metadata, search, artwork, lyrics, queue, and playback.
- Mutation outbox with ordered, idempotent reconciliation.
- Storage policy, download-quality policy, eviction, and orphan cleanup.
- Automatic online/local source selection across LAN, remote, Tailscale, and
  offline transitions.

Exit gate:

- Download tests cover suspension, eviction, relaunch, cancellation, range
  support, content replacement, insufficient storage, and logout.
- Offline cold launch passes with the server and VPN unavailable.
- Reconnection cannot double-apply playlist, favourite, or playback mutations.
- A corrupt or partial file is detected before playback.

### Phase 6: Apple ecosystem and release UX

Estimated duration: 5 weeks

Deliverables:

- CarPlay browsing, library entry points, queue, Now Playing, and error handling.
- Siri/App Intents and Shortcuts.
- Useful widgets using an App Group snapshot bridge.
- Deep links and state restoration across app and platform surfaces.
- Final accessibility, localisation, privacy, onboarding, settings, and support
  experiences.

Exit gate:

- CarPlay is tested in its simulator and on real compatible hardware when the
  entitlement is available.
- Intents and widgets operate from cold, warm, authenticated, restoring, and
  offline states.
- Extensions consume stable snapshots and commands rather than reaching into
  the application model directly.
- No platform surface exposes credentials or private server details.

### Phase 7: Autonomous beta and release hardening

Estimated duration: 5 weeks

Deliverables:

- Automated TestFlight build and release-candidate pipeline.
- Versioned compatibility, regression, performance, and endurance reports.
- Privacy manifest, App Store metadata, screenshots, release notes, and support
  documentation.
- Redacted opt-in crash/diagnostic strategy, or an explicit decision to ship
  without remote telemetry.
- Rollback procedure, database migration tests, and release branch policy.

Exit gate:

- All 1.0 scope rows trace to passing tests or captured agent-operated evidence.
- Release quality targets are met or an explicit documented exception narrows
  the advertised behavior.
- A release build is reproducible from a clean checkout.
- External Apple statuses are recorded accurately; agents do not claim App
  Store availability before Apple has actually accepted the build.

## Agent work decomposition

For Phases 2 through 6, the coordinating agent should normally divide work into
bounded slices such as:

- Jellyfin API and domain mapping.
- Persistence, cache, and offline state.
- Playback engine and session reporting.
- Feature UI and design-system integration.
- Platform extensions and App Group bridge.
- Test fixtures, integration tests, and evidence.

Do not assign multiple agents to edit the same central coordinator or project
configuration concurrently. A coordinating agent owns cross-slice integration,
resolves conflicts, runs the full gate, and updates the phase evidence.

An implementation task must name:

- The phase and exact acceptance criteria it advances.
- Owned modules or files.
- Inputs and outputs shared with other slices.
- Required tests and evidence.
- Explicit non-goals.
- The integration order.

## Definition of done

A feature or phase is complete only when:

1. Its behavior matches this plan and the active phase acceptance criteria.
2. Relevant unit, contract, integration, UI, screenshot, accessibility, and
   device tests pass.
3. Errors, restoring, offline, and authentication-expiry paths are covered.
4. User-facing strings and accessibility metadata are complete.
5. Diagnostics explain failures without leaking private data.
6. Documentation and decision records match the implementation.
7. The coordinating agent runs the full repository validation gate.
8. The final handoff records commands, results, remaining risks, and git status.

Passing a focused test, compiling one target, or rendering one successful screen
is not sufficient evidence of completion.

## Reference material

- [Official Jellyfin Swift SDK](https://github.com/jellyfin/jellyfin-sdk-swift)
- [Jellyfin networking](https://jellyfin.org/docs/general/post-install/networking/)
- [Jellyfin codec support](https://jellyfin.org/docs/general/clients/codec-support/)
- [Jellyfin music and lyrics](https://jellyfin.org/docs/general/server/media/music/)
- [Apple media playback configuration](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
- [Apple background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [Apple Now Playing](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [Apple CarPlay guidance](https://developer.apple.com/design/human-interface-guidelines/carplay/)
- [Tailscale HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates)
