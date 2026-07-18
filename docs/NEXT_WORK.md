# Next Work

Status: live work-order authority
Last updated: 2026-07-18

Release boundary: pragmatic connected-player 1.0 in `PRODUCT_PLAN.md`. Do not add
deferred features before the release gates pass.

## NOW

Premium UI pass is the active product slice. The simulator harness and focused
Favourites regressions are hardened; repeat full-suite proof is intentionally
deferred until after the UI changes so it validates the release candidate rather
than a UI that is about to be replaced.

## NEXT

### 1. Premium UI Batch 2 — Home and browsing destinations

- State: `NEXT`
- Gate: C — coherent premium interface with no unfinished primary destination.
- Outcome: apply the established artwork-led visual system to Home, Library,
  Search, album, artist, playlist, genre, favourites, and track destinations;
  refine their hierarchy, loading/empty/error states, iPad composition, Dynamic
  Type, VoiceOver, and Reduce Motion.
- Proof: deterministic screenshot/accessibility matrix plus agent inspection at
  compact and regular widths, light/dark, content/loading/empty/error, large text,
  and missing artwork; then `./scripts/test-ui.sh`.
- Non-goals: cloning Spotify branding or adding Spotify-scale features.

### 2. Run final deterministic Gate A/C proof

- State: `AFTER UI PASS`
- Gate: A/C — deterministic unit and complete primary-destination UI/accessibility
  gates against the finished interface.
- Outcome: run the hardened unit gate three consecutive times and the complete UI
  gate twice, inspect xcresults, and fix only reproducible release failures.
- Proof: repeated `./scripts/test.sh`, repeated `./scripts/test-ui.sh`,
  `./scripts/build-release.sh`, shell validation, and clean generated-project diff.
- Non-goals: further visual redesign or feature work.

### 3. Close the connected-player device gate

- State: `READY WHEN DEVICE CONTROL IS AVAILABLE`
- Gate: B — current-build audible start/pause/resume/seek/skip, background and
  Lock Screen control, restoration, and clean reporting stop.
- Proof: `./scripts/test-device.sh` plus redacted agent-captured results.
- Non-goals: Bluetooth, AirPlay, CarPlay, or eight-hour endurance claims.

### 4. Produce a personal release candidate

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

- Premium UI Batch 1 — visual foundation and playback shell: added a small
  semantic SwiftUI design layer for surfaces, typography, spacing, artwork,
  controls, feedback, and Reduce Motion-aware motion; redesigned connection,
  tab shell, mini-player, Now Playing, and queue. Deterministic artwork/missing
  artwork, Unicode metadata, playing/preparing/failure, duplicate queue, large
  text, and accessibility regression coverage passed in focused shell UI tests.
  Batch 2 owns Home and browsing destination redesign; the overall premium UI
  pass remains active.
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
