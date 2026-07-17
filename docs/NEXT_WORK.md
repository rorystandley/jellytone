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

### 1. Prove deterministic large-library fixture scale

- State: `READY`.
- Phase: Phase 3.
- Outcome: add a generated synthetic large-library corpus and bounded mapping,
  refresh, local-search, memory, and timing assertions.
- Acceptance focus: the first Phase 3 exit-gate row.
- Owned surface: deterministic fixture generation, scale tests, and evidence.
- Proof: reproducibility/hash checks, focused scale tests, `./scripts/test.sh`,
  and `./scripts/test-integration.sh`.
- Non-goals: UI redesign, playback behavior, or new Phase 3 destinations.

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

- After `61509d0`: expanded deterministic Phase 3 mapping and persistence
  fixtures for compilations, multi-disc ordering, metadata fallbacks, duplicate
  names, Unicode, malformed records, refresh idempotence, and scope isolation.
- After `2789dd3`: added scoped GRDB artist/album caching, cache-first repeat
  launch, and deterministic local/server search merging.
- `2789dd3`: expanded validation workflow and hardened playback diagnostics.
- `c05076c`: durable editable playback queue with stable occurrence identity.
- `698288b`: hardened playback audio lifecycle.
- `4cbe8d5`: persistent primary tabs and mini-player.
