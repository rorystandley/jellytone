# Next Work

Status: Live work-order authority

Last updated: 2026-07-17

- Last reconciled commit: `c05076c`
- Active roadmap boundary: Phase 2 remains open; explicitly brought-forward
  Phase 3 listening slices are allowed without claiming either phase complete.
- Selection rule: finish `NOW`; otherwise take the first unblocked `NEXT` item.

This is a routing index, not a second product plan. Keep it under 120 lines.
Implementation agents read the linked product, architecture, ADR, and evidence
sections only after selecting one item.

## NOW

### Reconcile the existing Phase 2 reporting and diagnostics work

- State: `IN FLIGHT` when the worktree is dirty; do not start an overlapping
  slice.
- Outcome: integrate or intentionally hand off the current lifecycle reporting,
  diagnostics, CI, integration-test, ADR, and evidence changes.
- Acceptance rows: Phase 2 full repository gate remains open; test-server
  start/progress/stop reporting is recorded as proven in the in-flight docs.
- Evidence: `docs/evidence/phase-2/connected-playback.md`.
- Proof: `./scripts/test.sh`, `./scripts/test-integration.sh`,
  `./scripts/test-ui.sh`, and `./scripts/build-release.sh`; run device proof when
  the required device path is available.
- Non-goal: do not fold a new library, offline, or platform feature into this
  change.

When the worktree is clean and this change is integrated, move its result to
`RECENTLY COMPLETED` and remove this `NOW` item.

## NEXT

### 1. Add the first cache-backed library/search slice

- State: `READY` after `NOW` is reconciled.
- Phase: Phase 1 foundation boundary advancing the brought-forward Phase 3
  local-search deliverable.
- Outcome: persist a narrowly scoped set of server/account music metadata and
  merge deterministic local artist/album results with server search results.
- Acceptance focus: cache-first repeat launch, stable domain boundaries,
  account isolation, deterministic migrations/fixtures, and no secret or
  private library data in logs or committed fixtures.
- Owned surface: a new `LibraryStore` boundary plus search integration; avoid
  unrelated playback-controller and project-configuration edits.
- Read after selection: Product Plan `Phase 1` and `Phase 3`; Architecture
  `LibraryStore`, `State ownership`, and `Testing architecture`; ADR 0004 and
  ADR 0014.
- Proof: focused store/search tests followed by `./scripts/test.sh` and the
  relevant integration/UI gates.
- Non-goals: Home shelves, playlists, favourites, downloads, and offline sync.

### 2. Expand deterministic Phase 3 library fixtures

- State: `READY` after item 1 or independently if file ownership does not
  overlap active work.
- Phase: Phase 3.
- Outcome: cover compilations, multi-disc albums, missing artwork, duplicate
  names, unusual Unicode, and malformed metadata through synthetic fixtures.
- Acceptance focus: the first Phase 3 exit-gate row.
- Owned surface: synthetic fixtures, mapping tests, and evidence only.
- Proof: focused mapping/fixture tests plus `./scripts/test.sh` and
  `./scripts/test-integration.sh`.
- Non-goals: production UI redesign or new playback behavior.

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

- `c05076c`: durable editable playback queue with stable occurrence identity.
- `698288b`: hardened playback audio lifecycle.
- `4cbe8d5`: persistent primary tabs and mini-player.
