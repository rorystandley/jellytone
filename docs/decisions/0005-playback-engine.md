# ADR 0005: Native playback engine, preloading and transition policy

Status: Accepted provisionally; device evidence required before capability advertising

Date: 2026-07-16

## Context

The product requires one authoritative queue, local and HTTP sources,
background audio, system commands, preloading, proven gapless transitions and
configurable crossfade. The proposed iOS 18.4 baseline can use AVFoundation,
but API availability alone does not prove transition quality, background
survival or route behavior.

## Alternatives considered

1. `AVQueuePlayer` only. It has native queue and platform integration, but does
   not expose a supported sample-accurate crossfade control.
2. Two overlapping `AVPlayer` instances. It can fade compressed remote assets,
   but increases clock, buffering, Now Playing and session-lifecycle races.
3. `AVAudioEngine`/player nodes for all playback. It provides sample scheduling
   and offline rendering, but remote compressed streaming, background behavior
   and route recovery carry substantially more app-owned machinery.
4. A third-party engine. This adds binary/licence/privacy/maintenance risk
   before native frameworks have failed the device gate.

## Decision

Use an application-owned engine boundary with `AVQueuePlayer` as the baseline
for prepared local and remote playback, background audio and non-crossfaded
queue advancement. Maintain exactly one authoritative playback/queue state
outside AVFoundation.

Preload one next `AVPlayerItem`. A transition is labelled gapless only for a
codec/container/delivery/OS/route matrix row with captured device audio meeting
the measured threshold. Otherwise it is an ordinary prepared hard cut.

Crossfade remains capability-gated behind an overlapping native-engine
prototype. It may be enabled only when both sources are prepared, share a
supported route/format, scheduling remains under the authoritative coordinator,
and physical-device background/route/energy evidence passes. If preparation is
late, a route changes, an interruption begins, seeking occurs near the boundary,
or queue replacement invalidates either source, cancel overlap and use a
non-crossfaded prepared transition. Diagnostics report requested and actual
transition modes separately.

## Consequences

- System integration stays on the most direct Apple playback path.
- Crossfade is not promised by the Phase 0 host render.
- The coordinator must invalidate prepared items atomically and prevent two
  Jellyfin play sessions from remaining open.
- Crossfade implementation may require revisiting this ADR after device proof;
  feature UI cannot expose it before that proof.

## Validation

`tools/playback/render_transitions.py` creates sample-domain hard-cut and 250 ms
crossfade renders from deterministic 48 kHz fixtures through both file and
ranged-loopback-HTTP inputs. All four captured results have zero duration error
and no digital-silence run beyond two samples. This proves the fixture/analyser
and target overlap math, not AVQueuePlayer acoustic output.

`tools/playback/run_codec_matrix.py` proves host AVFoundation can prepare the
matrix from files and loopback HTTP. The device procedure covers background,
remote commands, interruptions, routes, rapid replacement and acoustic capture.
An isolated signed probe now declares background audio, installs on the paired
iPhone, has a bounded automated runner, bundles every required codec, and has
local plus remote-HTTP preparation paths guarded by manifest identity. The single
bounded launch attempt was rejected by
SpringBoard because the phone was locked, and no acoustic capture path exists.
The hardware rows therefore remain blocked without being replaced by simulator
or install evidence.

Apple primary references:

- <https://developer.apple.com/documentation/avfoundation/avqueueplayer>
- <https://developer.apple.com/documentation/avfaudio/avaudioengine>
- <https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling>

## Rollback and migration

The engine is behind an owned interface and no production playback state exists
in Phase 0. If device evidence rejects AVQueuePlayer, replace the adapter and
write a superseding ADR; durable queue/plan models remain independent. Disable
crossfade remotely/local-feature-wise by selecting the hard-cut fallback—no
data migration is required.
