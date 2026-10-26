# Jellytone product plan

Status: release-scope authority
Last updated: 2026-07-18

## Product decision

Ship a personal Jellyfin music player for one server and one active
account. Version 1.0 has to connect, find music, play it reliably, manage a
queue, and recover from ordinary failures without looking unfinished.

Interface and interaction set the quality bar. That is not a request
to reproduce Spotify's feature inventory. Offline, automation, multiple servers,
CarPlay, and other ecosystem ideas remain possible future work, but they are not
1.0 acceptance criteria.

## Version 1.0 contract

### Connection and account

- Manually enter a full Jellyfin HTTP or HTTPS base URL, including ports and
  reverse-proxy paths.
- Authenticate with username/password against one user-operated server, persist
  only the token in Keychain, and support restoring and signing out of the active
  profile.
- Fail closed for invalid TLS, identity, authentication, and malformed server
  responses; diagnostics must not expose private data.
- Support Jellyfin 10.10.x and 10.11.x only where disposable-server contracts
  pass. Do not advertise broader compatibility from API presence.

Local discovery, Quick Connect, multiple saved servers/profiles, and automatic
endpoint switching are deferred. Replacing the configured server by signing out
and entering another URL is sufficient.

### Browse and find music

- Select a music library and browse Home, albums, artists, tracks, playlists,
  genres, and favourites.
- Search cached and server artist/album metadata with stable identity and
  deterministic results.
- Correctly handle paging, duplicate occurrences, compilations, multi-disc
  ordering, Unicode, missing artwork, empty libraries, and malformed optional
  metadata.
- Show useful loading, empty, retry, authentication, and offline/cache-only
  states at compact and regular widths.

Advanced sort/filter modes, alphabetical navigation, playlist creation and
membership editing, artist/album favourite writes, and downloads are deferred.
Home Listen Now discovery mixes (Instant Mix), frequently played albums,
rediscover, and genre chips are in scope. They reuse existing Jellyfin item
queries rather than a recommendation service. Existing track favourite and
playlist rename writes may ship when their retry/conflict behaviour remains
proven, but are not a reason to broaden the release.

### Playback

- Start, pause, resume, seek, skip, and stop compatible music using Direct Play
  or the proven Jellyfin AAC transcode fallback.
- Keep one authoritative, durable queue with Play Next, Add to Queue, reorder,
  remove, clear-up-next, shuffle, repeat-one, and repeat-all.
- Restore the queue and position after process termination without auto-playing.
- Keep app UI, Lock Screen/Control Centre Now Playing, remote commands, and
  Jellyfin start/progress/pause/stop reporting consistent.
- Handle preparation failure, playback failure, interruption, route change,
  replacement, natural completion, server unavailability, and expired auth
  without leaving misleading state or orphan reporting sessions.

Gapless playback, crossfade, sleep timer, lyrics, quality settings, downloads,
CarPlay, Siri, widgets, and advanced technical playback UI are deferred.

### Interface and interaction

- Artwork is the visual anchor across Home, Library, Search, mini-player, and
  Now Playing, with intentional gradients and missing-art fallbacks that follow
  the same visual system.
- Typography, hierarchy, spacing, corner radii, colour, materials, and icon use
  form one restrained visual system rather than per-screen styling.
- Mini-player and Now Playing transitions feel continuous; transport, queue,
  shuffle, repeat, seek, favourite, and context actions provide immediate,
  unambiguous visual feedback.
- Loading uses stable skeleton/progress presentation without layout jumps.
  Empty, offline, authentication, and retry states look designed rather than
  diagnostic.
- Navigation and common actions remain obvious and one-handed on iPhone, while
  iPad uses available space intentionally instead of stretching the phone UI.
- Motion and haptics are purposeful, short, interruptible, and respect Reduce
  Motion. The interface never sacrifices responsiveness for decoration.
- Every primary screen is visually reviewed from deterministic screenshots in
  compact/regular widths, light/dark appearance, large Dynamic Type, missing
  artwork, loading, content, empty, and error states.

Visual similarity to Spotify is not the acceptance test. The test is whether the
app has one visual system, clear state, fast interaction, a music-focused
hierarchy, and no visibly unfinished primary flow.

### Native quality and local release

- Support iPhone and iPad layouts on iOS/iPadOS 18.4 or later.
- Primary flows work in light/dark appearance, large Dynamic Type, VoiceOver,
  Reduce Motion, and missing-artwork states.
- Warm cached content appears promptly and large libraries remain bounded by
  pagination and measured storage/search behaviour.
- No secrets, authenticated URLs, server addresses, usernames, or library
  content enter committed fixtures or persisted diagnostics.
- A clean checkout can bootstrap, run deterministic tests, and produce an
  unsigned simulator Release build through the repository scripts.

Localization beyond the current language, App Store assets, TestFlight,
telemetry, and public distribution are out of scope for this personal release.
Device signing remains only what is necessary to install the app on the owner's
devices.

## Explicit non-goals

- Video, audiobooks, podcasts, subtitles, Picture in Picture, or server admin.
- A hosted backend, licensed catalogue, social features, or embedded VPN.
- Treating simulator results as device proof for background suspension,
  Bluetooth, AirPlay, or long-duration playback.
- Claiming offline playback from cached metadata or an unmanaged local file.

## Release gates

Version 1.0 is complete only when all applicable rows below have executable or
agent-operated evidence.

### Gate A: deterministic foundation

- [ ] `./scripts/test.sh` completes from a clean checkout without test-runner
  crash or unexplained generated-project diff.
- [ ] Privacy/redaction, migrations, cache isolation, paging, and deterministic
  large-library tests pass.
- [ ] The supported Jellyfin versions and iOS baseline match executable evidence.

### Gate B: connected playback

- [x] Queue and position restore after termination.
- [x] Disposable servers record ordered start/progress/pause/stop behaviour and
  forced AAC fallback on Jellyfin 10.10.7 and 10.11.11.
- [x] App playback state drives system Now Playing and remote commands.
- [ ] An agent-operated device run proves audible start, pause, resume, seek,
  next/previous, background continuation, and clean stop on the current build.

### Gate C: complete connected library

- [x] Home, albums, artists, tracks, search, playlists, genres, and favourites
  have deterministic domain/gateway/state coverage.
- [x] Fixtures cover scale, compilations, multi-disc ordering, missing artwork,
  duplicate identity/display names, Unicode, and malformed metadata.
- [ ] Every primary destination has passing compact/regular UI and accessibility
  coverage; the UI test runner must complete rather than merely compile.
- [ ] Deterministic screenshot coverage and agent inspection prove the
  interface contract across content, loading, empty, error, large-text,
  light/dark, iPhone, and iPad states.
- [ ] Existing writes have complete success, retry, conflict, authentication,
  privacy, and user-visible error/recovery evidence or are removed from 1.0 UI.

### Gate D: personal release candidate

- [ ] `./scripts/test-integration.sh`, `./scripts/test-ui.sh`, and
  `./scripts/build-release.sh` pass in the release environment.
- [ ] Cold launch, sign-in, browse, playback, restoration, and sign-out complete
  without crash on the supported simulator matrix and one physical device.
- [ ] Final diagnostics/privacy scan and generated-project cleanliness pass.
- [ ] Remaining external blockers and unsupported capabilities are stated in
  release notes without weakening the product contract.

## Delivery order

`docs/NEXT_WORK.md` is the only live work queue. Prefer release-risk removal and
interaction quality over feature count: write-surface honesty, reliable
gates, a coherent visual-system pass, device playback, then a personal release
candidate. Do not reopen deferred scope until these gates pass or the product
owner explicitly changes this contract.

## Definition of done

A release row is done only when behaviour, deterministic tests, UI/accessibility
evidence, diagnostics/privacy, documentation, and the relevant full repository
gate agree. Compile-only success, subjective inspection, and promised human QA
are insufficient. Missing hardware, credentials, signing, or services remain
explicit blockers rather than waived criteria.
