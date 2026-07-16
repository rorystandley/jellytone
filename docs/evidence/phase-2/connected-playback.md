# Phase 2 connected-playback evidence

Status: In progress

Last updated: 2026-07-16

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
- Privacy-safe on-device diagnostics record operation names, status/error codes,
  byte counts, and aggregate counts only.

## Automated evidence

`./scripts/test.sh` passes the focused application suite. The coverage includes
reverse-proxy URL construction, supported Direct Play selection, unsupported
codec fallback to the AAC transcode profile, playback-report position ticks,
and playback snapshot round-tripping.

The pre-existing disposable-server contract probe covers PlaybackInfo, Direct
Play delivery, forced AAC delivery, and start/progress/stop endpoints against
the pinned current and previous Jellyfin versions.

## Real-device state

The signed application build installs on the paired physical iPhone. The most
recent automatic launch was denied because the device was locked. Live playback
negotiation/reporting, background survival, Lock Screen commands, termination,
and restored-position evidence therefore remain open and must not be described
as passing until captured from the installed diagnostic build.

## Remaining Phase 2 work

- Capture the redacted PlaybackInfo and reporting sequence while a real track
  plays through the user's Tailscale-connected server.
- Prove background playback and Lock Screen play/pause/seek/next/previous.
- Terminate and relaunch, then prove the same queue and position are restored.
- Confirm at least one Direct Play row and one server-transcode row on device.
- Add measured transition and interruption/route-change evidence before calling
  the phase complete.
