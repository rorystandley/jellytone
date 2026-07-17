# Next Work

Status: Live work-order authority

Last updated: 2026-07-17

- Active roadmap boundary: Phase 2 remains open; explicitly brought-forward
  Phase 3 listening slices are allowed without claiming either phase complete.
- Selection rule: finish `NOW`; otherwise take the first unblocked `NEXT` item.

This is a routing index, not a second product plan. Keep it under 120 lines.
Implementation agents read the linked product, architecture, ADR, and evidence
sections only after selecting one item.

## NOW

No in-flight work. Select the first unblocked `NEXT` item.

## NEXT

### 1. Add read-only tracks browsing

- State: `READY`.
- Phase: explicitly brought-forward Phase 3 library slice.
- Outcome: browse music-library tracks with correct deterministic ordering and
  route selected tracks through the authoritative playback queue.
- Acceptance focus: scoped music-only paging/mapping, adaptive browse states,
  cache/privacy/race coverage, and accessibility evidence.
- Proof: focused mapping/state/playback/UI tests followed by `./scripts/test.sh`,
  `./scripts/test-integration.sh`, and `./scripts/test-ui.sh`.
- Non-goals: downloads, offline playback, writes, or playback-engine changes.

## BLOCKED

### Read-only downloads browsing (deferred to Phase 5)

- Phase: Phase 5 offline and network resilience; it is not a viable Phase 3
  destination slice.
- Blocker: no versioned `DownloadRecord` and `DownloadManifest` domain models,
  durable manifest storage, verified managed-file inspection, local source
  resolver, or authoritative playback integration for verified local files.
- Resume condition: all five prerequisites above have executable evidence. A
  stray file or a remote server item is not a download, and no empty Downloads
  screen may be created merely to satisfy a destination list.
- Non-goals while blocked: download UI, download mutations, and offline
  playback claims.

### Agent-operated audible real-device playback

- Phase: Phase 2 exit gate.
- Blocker: the current device lane proves install, launch, connected
  restoration, and paused start reporting, but cannot agent-operate audible
  playback controls.
- Resume condition: an attached device/UI-control path capable of producing
  agent-captured audible start, pause, resume, and playback evidence.
- Evidence: `docs/evidence/phase-2/connected-playback.md`.
- Rule: do not substitute simulator or compile evidence and do not repeatedly
  rediscover this blocker during task selection.

## RECENTLY COMPLETED

- Cache-first recent Home shelves: added scoped, versioned Recently Added album
  and Recently Played track snapshots with quiet independent refresh, valid-cache
  retention on failure, stale-response protection, accessible adaptive Home
  presentation, Album navigation, authoritative queue playback, synthetic
  fixtures, and 10.10.7/10.11.11 gateway contracts. Downloads remain deferred
  to their Phase 5 local-media prerequisites; this does not complete Home or
  Phase 3.

- Read-only favourites browsing: added active server/account/music-library scoped
  favourite artists, albums, and tracks with independent paging, stale-response
  protection, authoritative-queue playback, adaptive accessibility coverage,
  synthetic mappings, and disposable-server query contracts.
- Read-only genre browsing: added scoped paginated genre library/detail screens,
  stable identity and occurrence semantics, authoritative-queue play actions,
  deterministic gateway/state/playback/privacy tests, disposable-server
  contracts, and adaptive UI/accessibility coverage.
- Read-only playlist browsing: added paginated playlist library/detail screens,
  stable occurrence identities, authoritative-queue play actions, deterministic
  gateway/state/playback/privacy tests, and adaptive UI/accessibility coverage.
- After `f6e6599`: proved deterministic large-library scale with a versioned,
  seeded 23,040-track synthetic corpus, paginated mapping/cache coverage,
  canonical hashing, and bounded timing/process-memory evidence.
- After `61509d0`: expanded deterministic Phase 3 mapping and persistence
  fixtures for compilations, multi-disc ordering, metadata fallbacks, duplicate
  names, Unicode, malformed records, refresh idempotence, and scope isolation.
- After `2789dd3`: added scoped GRDB artist/album caching, cache-first repeat
  launch, and deterministic local/server search merging.
- `2789dd3`: expanded validation workflow and hardened playback diagnostics.
- `c05076c`: durable editable playback queue with stable occurrence identity.
- `698288b`: hardened playback audio lifecycle.
- `4cbe8d5`: persistent primary tabs and mini-player.
