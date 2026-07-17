# Roadmap Execution Checklist

Status: Active

Source of truth: [PRODUCT_PLAN.md](../PRODUCT_PLAN.md)

This file tracks execution evidence without replacing the product plan. A phase
may be checked only when every exit-gate statement below is supported by a
reproducible command or agent-operable evidence record. External dependencies
remain unchecked and explicitly blocked; simulator evidence does not substitute
for required real-device evidence.

## Phase 0: Product proof and decision records

- [ ] Every proof has a reproducible command or agent-operable procedure.
- [ ] Results and limitations are committed under `docs/evidence/phase-0/`.
- [ ] Every open risk has an owner phase and fallback behavior.
- [ ] No critical capability is accepted solely because an API appears to
  support it.
- Evidence index: [Phase 0 README](evidence/phase-0/README.md)

The remaining unchecked Phase 0 rows are deferred by the product owner's
Minimum Working App sequencing decision; they remain open risks rather than a
blocker to scaffolding the connected vertical slice.

## Phase 1: Deterministic foundation

- [ ] A clean checkout bootstraps and runs the complete foundation suite with
  one documented command.
- [ ] Regenerating the Xcode project produces no unexplained diff.
- [ ] CI and local scripts execute the same gates.
- [ ] Secrets and private server data cannot enter fixtures or logs.

Current Phase 1 evidence: the first pinned GRDB metadata migration is covered
for connection settings, idempotence, rollback, isolation, malformed rows, and
atomic stale-album replacement. Cache/search fixtures are synthetic and the
diagnostics privacy gate remains authoritative. Full Phase 1 remains open.

## Phase 2: Connected playback vertical slice

- [ ] The vertical slice passes unit, contract, integration, UI, simulator, and
  real-device playback tests.
- [x] Termination and relaunch restore the queue and position.
- [x] The test server records correct start, progress, and stop behavior.
- [x] One display and playback model drives both app and system Now Playing.

## Phase 3: Complete music library experience

- [x] Fixtures cover large libraries, compilations, multi-disc albums, missing
  artwork, duplicate names, unusual Unicode, and malformed metadata.
- [x] Read-only playlist list/detail paging preserves ordered duplicate
  occurrences and routes play actions through the authoritative queue.
- [ ] Every write operation has success, retry, conflict, and expired-auth tests.
- [ ] Screenshot and accessibility suites cover every primary destination at
  compact and regular widths.

Current Phase 3 evidence: repeat launches restore scoped cached albums before
refresh, and deterministic cached artist/album search merges with server results
without duplicate identities or changing server pagination. Offline transport
failures return cache-only results; authentication/server errors remain visible.
Synthetic file-backed Jellyfin fixtures now cover compilation album/track artist
semantics, multi-disc ordering, missing artwork and optional metadata, duplicate
display names with stable IDs, normalization-sensitive Unicode, malformed
optional values, and invalid partial records. Store tests prove exact round-trip,
normalized local search, idempotent refresh, and server/account/library isolation.
The generated scale corpus is versioned and seed-pinned at 240 artists, 1,440
albums, and 23,040 tracks. Its canonical SHA-256, paginated gateway mapping,
cache insertion/upsert/replacement, account/server isolation, stable local
search and merge ordering, uniqueness, and bounded host resource measurements
are executable evidence. Library isolation remains covered by the focused store
suite. Read-only playlist fixtures and controller tests additionally cover
pagination, per-occurrence identity, scope changes, stale-response suppression,
malformed rows, authentication expiry, empty/non-playable states, and adaptive
accessible presentation. No generated large JSON corpus or private library data
is committed.
The full Phase 3 matrix remains open.

## Phase 4: Premium playback

- [ ] Automated waveform fixtures measure unintended transition gaps and overlap.
- [ ] Eight-hour locked-screen and network-transition scenarios pass on real
  hardware.
- [ ] Queue replacement cannot leave an orphan Jellyfin playback session.
- [ ] Playback behavior is consistent across app, Lock Screen, accessories, and
  AirPlay.

## Phase 5: Offline and network resilience

- [ ] Download tests cover suspension, eviction, relaunch, cancellation, range
  support, content replacement, insufficient storage, and logout.
- [ ] Offline cold launch passes with server and VPN unavailable.
- [ ] Reconnection cannot double-apply playlist, favourite, or playback changes.
- [ ] Corrupt and partial files are rejected before playback.

## Phase 6: Apple ecosystem and release UX

- [ ] CarPlay passes simulator and real compatible hardware checks when the
  entitlement is available.
- [ ] Intents and widgets work from cold, warm, authenticated, restoring, and
  offline states.
- [ ] Extensions use stable snapshots and commands instead of application-model
  access.
- [ ] Platform surfaces expose no credentials or private server details.

## Phase 7: Autonomous beta and release hardening

- [ ] Every 1.0 scope row traces to passing tests or captured agent-operated
  evidence.
- [ ] Release quality targets pass, or an explicit documented exception narrows
  advertised behavior.
- [ ] A release build is reproducible from a clean checkout.
- [ ] External Apple statuses are recorded accurately without claiming release
  before Apple acceptance.
