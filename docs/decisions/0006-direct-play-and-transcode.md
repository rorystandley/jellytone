# ADR 0006: Direct Play detection and Jellyfin audio transcode profile

Status: Accepted provisionally; iOS device playback rows remain open

Date: 2026-07-16

## Context

The player should Direct Play when the source is supported, while requesting a
server transcode for incompatible sources or active quality/network policy.
Filename extensions and static SDK methods are insufficient: container, codec,
stream properties, OS, route and the actual prepared asset matter. Authenticated
fallback URLs must not be tried across unverified origins.

## Alternatives considered

1. Always Direct Play and recover after AVFoundation failure. This causes slow,
   opaque failures and may open authenticated requests unnecessarily.
2. Always transcode to AAC. This wastes server work, reduces lossless quality
   and fails the Direct Play principle.
3. Static extension table only. This cannot represent codec/container pairs,
   OS changes, channel limits or quality policy.
4. Conservative declared device profile plus runtime plan validation. This
   supplies Jellyfin a bounded capability contract and catches preparation
   failures before authoritative playback starts.

## Decision

Use option 4. Source planning evaluates, in order: verified matching local file;
declared Direct Play codec/container/stream capability; quality and network
policy; then runtime AVFoundation preparation. The provisional iOS 18.4 profile
declares MP3, AAC in MP4/M4A, ALAC in MP4/M4A, FLAC, and Vorbis/Opus in Ogg.
Opus in MP4 is also a candidate. Exact channel/profile/sample-rate limits stay
conservative until physical-device rows pass.

If any check fails, request an AAC stereo transcode constrained by the active
quality policy. The Phase 0 progressive proof uses Jellyfin's universal audio
endpoint with Direct Play and Direct Stream explicitly disabled, transcoding
enabled, and AAC stereo in MP4 requested at 128 kbps. That representation now
passes both advertised server versions; HLS remains a future source-planning
choice rather than an unproven fallback. Do not reuse a transcode URL as a stable
identity, and never put its token/query in logs. A failed transcode produces a
redacted diagnostic failure; it does not bypass TLS, retry another origin, or
mislabel the session Direct Play.

## Consequences

- Diagnostics can state local/direct/transcode, the policy reason and requested
  versus actual output without exposing the media URL.
- Capability declarations must be versioned by OS and updated when matrix
  evidence changes.
- Runtime preparation is defense in depth, not permission to over-declare the
  Jellyfin device profile.
- Route/channel constraints can change the decision and require ordered source
  replacement.

## Validation

`tools/playback/generate_fixtures.py` creates synthetic MP3, AAC, ALAC, FLAC,
Vorbis/Ogg, Opus/Ogg and Opus/MP4 sources. `run_codec_matrix.py` records FFprobe
stream data and AVFoundation local/loopback-HTTP preparation results with hashes
in machine-readable JSON. Every host row passed on the captured environment.
This is not promoted to iOS device or Jellyfin-server proof.

The official Jellyfin codec table documents iOS 18.4 Ogg Vorbis/Opus and iOS 17
Opus/MP4 support, and Jellyfin documents capability profiles driving transcode:

- <https://jellyfin.org/docs/general/clients/codec-support/>
- <https://jellyfin.org/docs/general/post-install/transcoding/>

`tools/connectivity/live_contract_probe.py` additionally fetched every required
synthetic format from disposable Jellyfin 10.11.11 and 10.10.7 servers twice:
once through the static original endpoint and once through the forced AAC-in-MP4
profile above. All 24 responses passed bounded `ffprobe` inspection with exactly
one expected audio stream and no video stream. The report deliberately calls the
first operation `original-static-source`, not Direct Play, and records
`deviceDecodeClaimed: false`; actual iOS decode and playback remain owned by
`docs/evidence/phase-0/playback/capability-findings.md` and the device procedure.

The Phase 2 production-gateway lane compiles the repository's current
`JellyfinAPI.swift` and exercises it against digest-pinned disposable Jellyfin
10.11.11 and 10.10.7 servers. A synthetic unsupported WMA source selects the
universal endpoint, and bounded `ffprobe` inspection proves one AAC audio stream
in an MP4-family container on both versions. This is genuine server and
production request-path evidence, but remains host URLSession delivery rather
than AVPlayer decode, audibility, or physical-device transcode evidence.

## Rollback and migration

Capability rows are versioned data behind source planning. A failing row can be
removed so it deterministically selects AAC transcode, without queue/database
migration. If AAC delivery fails a supported Jellyfin contract, revise the
transcode container/profile in a superseding ADR and retain prior evidence for
comparison.
