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

### 1. Add read-only favourites browsing

- State: `READY`.
- Phase: Phase 3.
- Outcome: add a native read-only favourites destination through the existing
  gateway/domain boundaries and authoritative playback flow.
- Acceptance focus: the next unimplemented Phase 3 library destination.
- Owned surface: scoped favourite artist/album/track mapping, adaptive browsing,
  deterministic fixtures, and focused state/playback/UI/accessibility tests.
- Read after selection: Product Plan Phase 3; Architecture Domain models,
  JellyfinGateway, state ownership, and Testing architecture.
- Proof: focused mapping/state/UI tests followed by `./scripts/test.sh`,
  `./scripts/test-integration.sh`, and `./scripts/test-ui.sh`.
- Non-goals: favourite mutations, downloads, offline sync, playlist writes, or
  playback-engine changes.

## BLOCKED

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
