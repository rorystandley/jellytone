# Next Work

Status: live work-order authority
Last updated: 2026-07-18

Release boundary: pragmatic connected-player 1.0 in `PRODUCT_PLAN.md`. Do not add
deferred features before the release gates pass.

## NOW

The premium UI pass is complete across the playback shell and every primary
browsing destination. Final repeated Gate A/C proof is now the active release
slice.

## NEXT

### 1. Run final deterministic Gate A/C proof

- State: `NEXT`
- Gate: A/C — deterministic unit and complete primary-destination UI/accessibility
  gates against the finished interface.
- Outcome: run the hardened unit gate three consecutive times and the complete UI
  gate twice, inspect xcresults, and fix only reproducible release failures.
- Proof: repeated `./scripts/test.sh`, repeated `./scripts/test-ui.sh`,
  `./scripts/build-release.sh`, shell validation, and clean generated-project diff.
- Non-goals: further visual redesign or feature work.

### 2. Close the connected-player device gate

- State: `READY WHEN DEVICE CONTROL IS AVAILABLE`
- Gate: B — current-build audible start/pause/resume/seek/skip, background and
  Lock Screen control, restoration, and clean reporting stop.
- Proof: `./scripts/test-device.sh` plus redacted agent-captured results.
- Non-goals: Bluetooth, AirPlay, CarPlay, or eight-hour endurance claims.

### 3. Produce a personal release candidate

- State: `AFTER 1-4`
- Gate: D — local identity/version/privacy configuration, clean simulator
  matrix, integration/UI gates, installable owner-device build, unsigned
  simulator Release build, and honest release notes.
- Proof: `./scripts/test-integration.sh`, `./scripts/test-ui.sh`,
  `./scripts/build-release.sh`, privacy scan, and clean generated-project diff.
- Non-goals: App Store submission, TestFlight, multi-server support, or adding
  deferred features.

## BLOCKED

### Audible physical-device automation

- Blocker: the current device lane can install, launch, and inspect restoration
  but cannot yet agent-operate all audible playback controls.
- Resume when an attached device/UI-control path can capture Gate B.

## RECENTLY COMPLETED

- Home Listen Now discovery: Made for You Instant Mixes, Top Albums
  (PlayCount), Rediscover (Random), genre chips, and honest Your Playlists
  shelf — cache-first via HomeShelfSnapshot additive fields.


- Premium UI Batch 2 — Home and browsing destinations: added shared browse
  containers, headings, artwork cards, track rows, playback actions, pagination,
  and intentional state/missing-artwork treatments; redesigned Home, Library,
  Search, album, artist, playlist, genre, favourites, and track catalogue while
  preserving occurrence order and existing intents. Focused destination UI tests
  passed on iPhone 17 Pro and iPad Pro 13-inch simulators (iOS 26.5), inspected
  light/dark, large-text, missing-artwork, error/empty/loading, and regular-width
  screenshots were coherent, all 141 unit tests passed, and Release built. The
  overall premium UI pass is complete; repeated full Gate A/C proof remains next.
- Premium UI Batch 1 — visual foundation and playback shell: added a small
  semantic SwiftUI design layer for surfaces, typography, spacing, artwork,
  controls, feedback, and Reduce Motion-aware motion; redesigned connection,
  tab shell, mini-player, Now Playing, and queue. Deterministic artwork/missing
  artwork, Unicode metadata, playing/preparing/failure, duplicate queue, large
  text, and accessibility regression coverage passed in focused shell UI tests.
  Batch 2 completed Home and the remaining browsing destinations, closing the
  overall premium UI pass.
- Gate-harness hardening: isolated DerivedData/xcresult paths, deterministic
  pinned simulator selection, bounded boot readiness, serial execution, locking,
  stale-lock recovery, and competing-runner diagnostics remove the confirmed
  shared-runner failure mechanism. Focused Favourites timing, scrolling, loading,
  failure, and empty-state regressions now use deterministic state assertions;
  the isolated loading/empty test passes. Full repeat proof is deferred until the
  premium UI pass is complete so it validates the final interface.
- Shipped-write audit: hid playlist rename from the playlist grid and detail
  screen, and track favourite/unfavourite from track and favourites screens.
  Existing reusable gateway, domain, and durable-outbox work remains deferred;
  it cannot be invoked by 1.0 UI until complete lifecycle recovery is proven.
  Focused simulator UI coverage confirms the controls remain absent at large
  Dynamic Type while playlist, track, and favourites browsing stays accessible.
- Durable playlist rename implementation committed at `6edbb9e`; release audit
  found recovery/overlay/UI evidence gaps, so it is not yet accepted for 1.0.
- Track favourite mutation implementation committed at `07ccb97`; release audit
  remains part of the first hardening slice.
- Connected browsing covers Home, search, albums/artists, tracks, playlists,
  genres, and favourites with deterministic mapping/paging/cache evidence.
- Playback covers the durable editable queue, shuffle/repeat, restoration,
  system Now Playing/remote commands, and disposable-server reporting contracts.
