# Repository agent instructions

This repository is implemented and verified by coding agents. Do not assume a
human will finish implementation, review, or QA.

## Start here

For selection-only requests:

1. Verify the checkout, branch, and `git status`.
2. Run `./scripts/next-work.sh`.
3. Reconcile dirty or stale in-flight work before selecting anything new.
4. Choose the first unblocked `NEXT` item in `docs/NEXT_WORK.md`.
5. Report its release gate, owned surface, proof command, and blockers briefly.

Do not perform a repository-wide audit merely to select work. After selection,
read only the relevant sections of `PRODUCT_PLAN.md`, `docs/ARCHITECTURE.md`,
the named ADRs, implementation, and tests.

Authority order:

1. `PRODUCT_PLAN.md`: release scope and acceptance.
2. `docs/NEXT_WORK.md`: current order and blockers.
3. `docs/ARCHITECTURE.md`: boundaries and invariants.
4. `docs/decisions/`: durable technical decisions.
5. Tests, scripts, and machine evidence: proof.

Do not add a second checklist or narrative status log. Update the queue whenever
status changes and keep it under 120 lines.

## Product boundary

- Native iPhone/iPad Jellyfin music player only.
- No video, spoken audio, server administration, or product cloud backend.
- Version 1.0 is a premium personal connected-player for one server. Premium is
  a UI/interaction quality bar, not permission to add deferred feature breadth.
  `PRODUCT_PLAN.md` defines the exact contract.
- Never weaken TLS, credentials, privacy, accessibility, or playback integrity
  to pass a happy path.

## Implementation rules

- Preserve unrelated edits and reconcile in-flight work first.
- Prefer small, reviewable slices with regression tests.
- Keep wire/generated Jellyfin models behind the gateway/domain boundary.
- Keep one authoritative playback queue and state owner.
- Store tokens in Keychain; never log or commit credentials, private server
  addresses, usernames, library data, signing material, or downloaded media.
- Use deterministic clocks, identifiers, fixtures, and random sources in tests.
- Never hand-edit the generated Xcode project; edit `project.yml` and regenerate.
- Create or update an ADR for changes to platform/server support, dependencies,
  persistence, playback, authentication/TLS, offline storage, extensions,
  diagnostics, or release automation.

Trace playback changes through app UI, restoration, Now Playing, remote commands,
and offline/platform consumers that actually exist. Do not claim future surfaces
because an SDK exposes an API.

## Proof and handoff

Stable entry points:

- `./scripts/bootstrap.sh`
- `./scripts/test.sh`
- `./scripts/test-integration.sh`
- `./scripts/test-ui.sh`
- `./scripts/test-device.sh`
- `./scripts/build-release.sh`

Run focused tests while iterating and the full relevant gate before completion.
A compile, subjective inspection, or promise of later manual QA is not proof.
Use deterministic tests, simulator/UI evidence, measured media fixtures, and
agent-operated device evidence as appropriate. A bug fix needs a regression test.

If hardware, credentials, signing, entitlement, or an external service is
unavailable, record the exact blocker and continue safe independent work; never
waive the gate or substitute simulator evidence for device-only behavior.

Every implementation handoff states:

- release gate advanced and user-visible outcome;
- files/modules changed;
- commands and results;
- simulator/device evidence and external blockers;
- documentation/ADR updates;
- final Git status and publication state.

## Multi-agent work

Use parallel agents only for bounded, low-overlap surfaces. Assign explicit file
ownership, interfaces, outputs, and proof. The coordinating agent reviews diffs,
integrates the app, runs the complete gate, and updates the queue.
