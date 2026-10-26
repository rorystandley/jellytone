# Next Work

Status: live work-order authority
Last updated: 2026-07-18

Release boundary: pragmatic connected-player 1.0 in `PRODUCT_PLAN.md`. Do not add
deferred features before the release gates pass.

## NOW

The visual pass is complete across the playback shell and every primary
browsing destination. Repeating Gate A and Gate C is now the active release
slice.

## NEXT

### 1. Run final deterministic Gate A/C proof

State is NEXT. Gate A/C covers deterministic unit tests and complete
primary-destination UI and accessibility gates against the finished interface.
Run the hardened unit gate three consecutive times and the complete UI gate
twice, inspect xcresults, and fix only reproducible release failures. Proof is
repeated `./scripts/test.sh`, repeated `./scripts/test-ui.sh`,
`./scripts/build-release.sh`, shell validation, and a clean generated-project
diff. Further visual redesign or feature work is out of scope.

### 2. Close the connected-player device gate

State is READY WHEN DEVICE CONTROL IS AVAILABLE. Gate B covers current-build
audible start, pause, resume, seek, and skip, background and Lock Screen
control, restoration, and a clean reporting stop. Proof is
`./scripts/test-device.sh` plus redacted agent-captured results. Bluetooth,
AirPlay, CarPlay, and eight-hour endurance claims are out of scope.

### 3. Produce a personal release candidate

State is AFTER 1-4. Gate D covers local identity, version, and privacy
configuration, a clean simulator matrix, integration and UI gates, an
installable owner-device build, an unsigned simulator Release build, and honest
release notes. Proof is `./scripts/test-integration.sh`, `./scripts/test-ui.sh`,
`./scripts/build-release.sh`, a privacy scan, and a clean generated-project
diff. App Store submission, TestFlight, multi-server support, and adding
deferred features are out of scope.

## BLOCKED

### Audible physical-device automation

- Blocker: the current device lane can install, launch, and inspect restoration
  but cannot yet agent-operate all audible playback controls.
- Resume when an attached device/UI-control path can capture Gate B.

## RECENTLY COMPLETED

- Home Listen Now discovery: Made for You Instant Mixes, Top Albums
  (PlayCount), Rediscover (Random), genre chips, and honest Your Playlists
  shelf. Cache-first via HomeShelfSnapshot additive fields.


- UI batch 2, Home and browsing destinations: added shared browse
  containers, headings, artwork cards, track rows, playback actions, pagination,
  and intentional state and missing-artwork treatments; redesigned Home, Library,
  Search, album, artist, playlist, genre, favourites, and track catalogue while
  preserving occurrence order and existing intents. Focused destination UI tests
  passed on iPhone 17 Pro and iPad Pro 13-inch simulators (iOS 26.5), inspected
  light/dark, large-text, missing-artwork, error/empty/loading, and regular-width
  screenshots were coherent, all 141 unit tests passed, and Release built. The
  visual pass is complete. Repeated full Gate A/C proof remains next.
- UI batch 1, visual foundation and playback shell: added a small
  semantic SwiftUI design layer for surfaces, typography, spacing, artwork,
  controls, feedback, and Reduce Motion-aware motion; redesigned connection,
  tab shell, mini-player, Now Playing, and queue. Deterministic artwork/missing
  artwork, Unicode metadata, playing/preparing/failure, duplicate queue, large
  text, and accessibility regression coverage passed in focused shell UI tests.
  Batch 2 completed Home and the remaining browsing destinations, closing the
  visual pass.
- Gate-harness hardening: isolated DerivedData/xcresult paths, deterministic
  pinned simulator selection, bounded boot readiness, serial execution, locking,
  stale-lock recovery, and competing-runner diagnostics remove the confirmed
  shared-runner failure mechanism. Focused Favourites timing, scrolling, loading,
  failure, and empty-state regressions now use deterministic state assertions;
  the isolated loading/empty test passes. Full repeat proof is deferred until the
  visual pass is complete so it validates the final interface.
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
