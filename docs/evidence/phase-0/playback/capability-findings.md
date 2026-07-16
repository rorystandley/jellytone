# Playback capability findings and fallback contract

## State flow under test

The future Playback owner prepares one `PlaybackPlan` ahead. Preparation is
successful only after the asset is playable and its duration/audio track can be
loaded. Local verified files and remote Direct Play URLs use the same plan
shape; remote readiness additionally requires buffered data. A late or failed
next plan falls back to an honest hard cut. Crossfade never silently changes to
two unsynchronised `AVPlayer` instances.

For source replacement, the required event order is final progress for A,
stop A, start B. Authentication, endpoint and item identifiers must be redacted
before persistence. `results/session-order.json` captures the prototype order.

## Capability boundary

The provisional direct candidates are in `results/source-policy.json`. Runtime
asset preparation is a last validation, not the sole capability detector:
containers, codec/profile, channel count, OS, route and quality/network policy
must be checked before an authenticated URL is opened. An unsupported or
policy-constrained source requests a Jellyfin AAC transcode. If the transcode
cannot be prepared, playback fails diagnostically; TLS or certificate policy is
never weakened.

## Open work ownership

- Phase 0 connectivity/server-fixture owner: prove actual PlaybackInfo/device
  profile and original/transcoded stream contracts on the advertised Jellyfin
  versions.
- Phase 1: package the signed iOS probe and stable non-interactive device entry
  point.
- Phase 2: implement the authoritative queue, Now Playing and ordered Jellyfin
  reporting bridge.
- Phase 4: complete physical-device transition, interruption, route, energy and
  endurance measurements before advertising gapless/crossfade compatibility.
