# Phase 2 connected-playback evidence

Status: In progress

Last updated: 2026-07-17

## Implemented

- PlaybackInfo negotiation before media playback.
- Conservative Direct Play selection for the provisional iOS codec/container
  matrix, with the contract-proven AAC stereo universal endpoint as fallback.
- Jellyfin start, progress, pause, seek, transition, and stop reporting.
- One authoritative album queue with previous/next and ordered session closure.
- User/profile-scoped queue, index, and position persistence without tokens or
  authenticated media URLs.
- Relaunch restoration prepares the same queue and position in a paused state.
- Authenticated album artwork drives the app and system Now Playing surfaces.
- The production audio session uses the `.playback` category and is activated
  before stream preparation so locking the device does not invoke the default
  ambient-session stop behavior.
- Privacy-safe on-device diagnostics record operation names, status/error codes,
  byte counts, and aggregate counts only.

## Automated evidence

`./scripts/test.sh` passes the focused application suite. The coverage includes
reverse-proxy URL construction, supported Direct Play selection, unsupported
codec fallback to the AAC transcode profile, playback-report position ticks,
playback snapshot round-tripping, and requesting Now Playing artwork away from
the main actor. A recording audio-session adapter also proves activation occurs
before playback preparation and deactivation occurs on an explicit stop.

The pre-existing disposable-server contract probe covers PlaybackInfo, Direct
Play delivery, forced AAC delivery, and start/progress/stop endpoints against
the pinned current and previous Jellyfin versions.

## Real-device state

The signed application build installs and launches on the paired physical
iPhone. A 2026-07-17 restored-playback launch reproduced a `SIGTRAP` in the
`MPMediaItemArtwork` callback: MediaPlayer requested the image on its private
queue while the callback had inherited `PlaybackController`'s main-actor
isolation. Moving callback creation to a nonisolated factory fixed that exact
failure, and a regression test exercises the callback from a detached task.

After reinstalling, the same restored queue completed PlaybackInfo negotiation,
received HTTP 204 for playback start, loaded 100 albums, and remained alive.
A second ordinary launch produced two successful HTTP 204 playback-progress
reports, and no new JellyfinAudio crash report appeared. The prior crash report
and live diagnostics contained no token, server address, username, or library
item names.

Background survival, Lock Screen commands, termination, and non-zero restored
position still require their dedicated device evidence and must not be
described as passing yet.

## Remaining Phase 2 work

- Prove background playback and Lock Screen play/pause/seek/next/previous.
- Terminate and relaunch, then prove the same queue and position are restored.
- Confirm at least one Direct Play row and one server-transcode row on device.
- Add measured transition and interruption/route-change evidence before calling
  the phase complete.
