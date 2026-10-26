# ADR 0005: Native playback engine, preloading and transition policy

Status: Accepted provisionally; device evidence required before capability advertising

Date: 2026-07-16

## Context

The product requires one authoritative queue, local and HTTP sources,
background audio, system commands, preloading, proven gapless transitions and
configurable crossfade. The proposed iOS 18.4 baseline can use AVFoundation,
but API availability alone does not prove transition quality, background
survival or route behaviour.

## Alternatives considered

1. `AVQueuePlayer` only. It has native queue and platform integration, but does
   not expose a supported sample-accurate crossfade control.
2. Two overlapping `AVPlayer` instances. It can fade compressed remote assets,
   but increases clock, buffering, Now Playing and session-lifecycle races.
3. `AVAudioEngine`/player nodes for all playback. It provides sample scheduling
   and offline rendering, but remote compressed streaming, background behaviour
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
- Queue occurrences carry stable identities independent of Jellyfin track IDs,
  so duplicates remain independently editable and restorable.
- Reorder, remove, clear, Play Next, and Add to Queue while shuffled commit the
  visible order as canonical and disable shuffle; jump alone preserves shuffle.
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

The Phase 2 application now observes audio-session interruptions, route changes,
and media-services reset at the authoritative playback controller. Deterministic
tests prove that interruption begin pauses and persists, resume requires both
the system `shouldResume` option and prior playback intent, a pending preparation
cannot escape interruption or headphone-loss policy, old-device-unavailable
pauses, media-services reset reactivates or fails paused, and system remote
commands route to that controller. `./scripts/test.sh` passes all 24 tests.

The early Phase 3 durable-queue slice adds deterministic coverage for entry
identity and legacy migration, duplicate occurrences, jump/reorder/remove/clear,
shuffle-edit semantics, repeat boundaries, restoration, and rapid replacement.
Replacement preparation awaits the cancelled predecessor's shielded reporting
cleanup; the regression records start(first), stop(first), start(final), with no
start for the superseded middle selection.
The final authoritative `./scripts/test.sh` run passes all 29 tests.

The Phase 2 lifecycle closure slice serializes reporting and proves that the
final queue entry sends exactly one stop at its natural end rather than only a
paused progress event. Deterministic regressions also cover terminal player
failure closure, ordered rapid replacement, restoration, interruption, seek,
pause/resume, and explicit stop. Production observation now includes item
failure, failed-to-end, and stall signals. `./scripts/test.sh` passes 36 tests;
the unlocked-device rerun subsequently installed and launched the current build.
Redacted diagnostics prove Direct Play planning, a restored 14-entry queue at
624 seconds, and a successful paused start report. The smoke lane cannot operate
audible playback controls, so this is not promoted to a fresh physical playback
or natural-completion pass.

A bounded 2026-07-17 production-app exercise passed approximately 60 seconds
locked and 60 seconds backgrounded on the paired iPhone. Lock Screen metadata
and play, pause, seek, next, and previous were physically confirmed; redacted
diagnostics captured four corresponding command codes, successful progress, and
ordered stop/start around next. The final installed build recorded Direct Play
method code `1` and no new crash. This advances background and remote-command
validation but does not prove eight-hour endurance, acoustic transitions,
physical interruptions, Bluetooth, wired output, AirPlay, or a transcode row.

Apple primary references:

- <https://developer.apple.com/documentation/avfoundation/avqueueplayer>
- <https://developer.apple.com/documentation/avfaudio/avaudioengine>
- <https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling>

## Rollback and migration

The engine remains behind an owned interface. If device evidence rejects
AVQueuePlayer, replace the adapter and write a superseding ADR; durable
queue/plan models remain independent. Legacy snapshots containing raw track
arrays decode into per-occurrence queue entries and are rewritten in the new
entry-based form; no queue is discarded. Disable crossfade by selecting the
hard-cut fallback. No additional data migration is required.
