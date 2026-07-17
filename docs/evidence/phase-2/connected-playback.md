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
- Audio-session interruption notifications pause, report, and persist the
  authoritative controller. An ended interruption resumes only when the system
  supplies `shouldResume` and playback was active or pending before interruption.
- An `oldDeviceUnavailable` route change pauses active or preparing playback so
  unplugging an output cannot silently continue on another route. Media-services
  reset reactivates the playback session and fails to a reported paused state if
  reactivation fails.
- A MediaPlayer adapter converts Lock Screen and Control Centre play, pause,
  seek, next, and previous commands into intents handled by the same
  `PlaybackController` used by the app UI.
- Privacy-safe on-device diagnostics record operation names, status/error codes,
  playback-method and lifecycle enums, byte counts, and aggregate counts only.

## Automated evidence

`./scripts/test.sh` passes 24 focused application tests. The coverage includes
reverse-proxy URL construction, supported Direct Play selection, unsupported
codec fallback to the AAC transcode profile, playback-report position ticks,
playback snapshot round-tripping, and requesting Now Playing artwork away from
the main actor. Recording audio-session and remote-command adapters prove
activation occurs before playback preparation, interruption resume permission,
paused-before-interruption behavior, interruption/headphone loss during pending
preparation, old-device-unavailable pausing, media-services reset success and
failure, and all five system-command routes. The tests assert state changes and
persistence rather than compilation alone.

The pre-existing disposable-server contract probe covers PlaybackInfo, Direct
Play delivery, forced AAC delivery, and start/progress/stop endpoints against
the pinned current and previous Jellyfin versions. In this slice,
`./scripts/test-integration.sh` also passed all 14 connectivity, identity,
privacy, and versioned-fixture tests plus both supported contract-fixture
validations.

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

The 2026-07-17 listening-shell deployment terminated the prior process and
restored its single-entry queue at a non-zero 131-second position. The user then
resumed playback and a successful HTTP 204 progress report followed 48 seconds
after launch. No new crash report appeared.

On 2026-07-17 the final lifecycle build installed with
`./scripts/deploy-app.sh --launch`; SpringBoard initially denied only the launch
because the phone had relocked. After the explicit unlock, the same installed
build launched through `devicectl`, restored a 15-entry queue at a non-zero
position, selected playback method code `1` (Direct Play), received HTTP 204 for
playback start and progress, and created no new crash report. The newest of the
seven existing crash reports remained the already-diagnosed 08:57 BST artwork
failure from before this slice.

A bounded physical exercise then passed approximately 60 seconds of locked
playback and 60 seconds backgrounded. The user performed the required physical
lock/unlock and confirmed visible Lock Screen metadata plus working play, pause,
seek, next, and previous controls. Collected diagnostics independently recorded
seek, pause, play, and next command codes, continued successful progress reports,
and ordered stop then start reporting around next. Previous was confirmed by the
physical operator but its command code was not present in the collected log, so
that detail is not promoted to independently captured diagnostic evidence.

The redacted device log contained zero token/authorization, URL, IPv4 address,
or username pattern matches. It records only codes, counts, byte sizes, operation
names, status values, and coarse positions. No private library names, item IDs,
server addresses, credentials, or authenticated media URLs were committed.

## Remaining Phase 2 work

- Run a longer suspension/background campaign; the bounded two-minute exercise
  is not the eight-hour Phase 4 endurance gate.
- Confirm a server-transcode row on device when the current library naturally
  requires it. Direct Play is captured; transcoding was not forced and the
  server was not mutated for evidence.
- Add measured transition and physical interruption/route-change evidence before
  calling the phase complete. Deterministic lifecycle regressions do not replace
  call/Siri, Bluetooth, wired-output, or AirPlay hardware evidence.
