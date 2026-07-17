# Repository Agent Instructions

This repository is designed to be implemented and maintained by AI coding
agents. No human implementation, code review, QA pass, or manual completion step
may be assumed.

## Context-efficient reading order

Do not load the complete planning set merely to decide what to work on.

For a discovery-only request such as "what is next?":

1. Read this file through **Work-selection fast path**.
2. Run `./scripts/next-work.sh`, which shows the compact work queue and current
   Git state.
3. If the worktree is dirty, treat reconciling the in-flight work as the first
   priority. Do not nominate overlapping implementation.
4. If the worktree is clean, choose the first unblocked `NEXT` item in
   [docs/NEXT_WORK.md](docs/NEXT_WORK.md).
5. Return the selected phase, acceptance row, owned surface, proof command, and
   blocker or non-goals in at most ten lines.

Do not read full product, architecture, ADR, evidence, or implementation files
during selection. Do not spawn sub-agents for selection alone. Target no more
than five shell commands and five percent of the available context before a
slice is selected.

After a slice is selected and before changing code, read only:

1. The relevant phase and acceptance criteria in
   [PRODUCT_PLAN.md](PRODUCT_PLAN.md).
2. The relevant boundary or state-flow sections in
   [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
3. The ADRs and evidence named by the selected queue item.
4. The scoped implementation, tests, build scripts, branch, and status.

Read the complete product plan or architecture only for a broad product or
architecture change. `PRODUCT_PLAN.md` remains product-scope authority;
`docs/NEXT_WORK.md` is the live ordering authority.

## Work-selection fast path

`docs/NEXT_WORK.md` must stay compact and contain exactly these operational
sections: `NOW`, ordered `NEXT`, `BLOCKED`, and `RECENTLY COMPLETED`. The first
unblocked item is the default next slice; agents must not re-rank the roadmap by
performing a fresh repository-wide audit.

At the end of work that changes status or evidence, update the queue in the same
change. Keep detailed history in product evidence, not in the queue. Record the
last reconciled commit so `./scripts/next-work.sh` can expose stale routing.

## Scope guardrails

- This is a native iOS/iPadOS music player for Jellyfin music libraries.
- Do not add video, audiobooks, podcasts, subtitles, Picture in Picture, or
  server administration.
- Do not add a product cloud backend unless the product plan is explicitly
  changed.
- Do not weaken TLS, credential storage, privacy, accessibility, or offline
  guarantees to make a happy-path demo pass.
- Treat the named roadmap phase as the implementation boundary.
- Do not mark a future feature complete because an SDK exposes a corresponding
  method; prove end-to-end behavior.

## Repository workflow

At the start of every task:

1. Verify the absolute checkout path and current branch.
2. Inspect `git status` and preserve unrelated changes.
3. Finish or reconcile in-flight work before selecting an overlapping slice.
4. Identify the selected product-plan phase and acceptance criteria.
5. Trace the relevant state through every consumer, including offline, CarPlay,
   widgets, intents, and system Now Playing where applicable.
6. State assumptions and risks before making broad architectural changes.

During implementation:

- Prefer small, reviewable changes with explicit tests.
- Keep generated Jellyfin models behind the gateway/domain boundary.
- Keep one authoritative queue and playback state.
- Keep extensions isolated behind snapshot/command bridges.
- Redact credentials, server addresses, usernames, and library content from
  logs and fixtures.
- Use deterministic clocks, identifiers, fixtures, and seeded random sources in
  tests.
- Preserve unrelated user files and edits.
- Never hand-edit generated Xcode project files when a declarative project
  source exists.

At the end of every task:

1. Run focused tests while iterating.
2. Run the full relevant repository gate before claiming completion.
3. Inspect the final diff and repository status.
4. Update plan checklists, architecture decisions, and phase evidence affected
   by the change.
5. Report commands, results, unverified behavior, external blockers, and risks.

## Agent-only acceptance standard

No acceptance criterion may be phrased only as:

- “looks correct”;
- “works for me”;
- “ready for human QA”;
- “needs manual verification later”; or
- “compiles successfully.”

Replace subjective gates with executable evidence:

- Unit and property tests for domain behavior.
- Contract tests against versioned Jellyfin servers.
- Integration tests against deterministic media fixtures.
- UI and screenshot tests at defined device sizes and appearances.
- Accessibility audits and agent inspection of rendered output.
- Measured audio-transition, performance, memory, and endurance results.
- Simulator evidence where the simulator is representative.
- Real-device evidence for background suspension, long playback, Bluetooth,
  AirPlay, and CarPlay.
- Redacted diagnostics proving Direct Play/transcode and endpoint decisions.

If required hardware, credentials, entitlement approval, or an external service
is unavailable, record the exact blocker. Continue safe work that does not rely
on the missing dependency, but do not waive the affected gate.

## Project commands

Phase 1 must create and maintain non-interactive entry points with these stable
purposes:

- `./scripts/bootstrap.sh`: install or verify pinned project tools and generate
  the project.
- `./scripts/test.sh`: run the authoritative local unit and simulator gate.
- `./scripts/test-integration.sh`: run Jellyfin contract and integration tests.
- `./scripts/test-ui.sh`: run UI, screenshot, and accessibility suites.
- `./scripts/test-device.sh`: run agent-operated real-device checks when a
  compatible device is attached.
- `./scripts/build-release.sh`: produce a clean release archive or build.

These commands exist. Change their names only by updating this file, CI, and all
linked documentation in the same change.

## Multi-agent coordination

Use parallel agents for bounded work that has low file overlap. Good boundaries
include API/domain mapping, persistence/offline, playback, feature UI, platform
extensions, and test/evidence work.

The coordinating agent must:

- Define concrete file or module ownership and explicit outputs.
- Prevent concurrent edits to central coordinators and project configuration.
- Specify integration order and shared interface contracts.
- Review every returned diff rather than accepting summaries.
- Integrate the complete application and run the full phase gate.
- Resolve cross-surface omissions and update phase evidence.

Delegated prompts must request implementation and evidence, not open-ended
architectural commentary. Agents may delegate further only when boundaries
remain clear and the coordinating agent retains integration responsibility.

## Architecture changes

Create or update an architecture decision record when changing:

- The deployment target or supported Jellyfin versions.
- Project generation or package management.
- Persistence technology or schema strategy.
- Playback engine or gapless/crossfade approach.
- Authentication, TLS, endpoint selection, or credential storage.
- Offline manifests, reconciliation, or source selection.
- App Group, widget, intent, or CarPlay integration boundaries.
- Telemetry, diagnostics, or privacy behavior.

An architecture decision must include context, alternatives, decision,
consequences, validation, and rollback/migration implications.

## Testing rules

- A bug fix requires a regression test that fails for the original mechanism.
- Queue, shuffle, repeat, reconciliation, and retry logic require deterministic
  tests, including interruption and restoration.
- API mapping tests must use captured synthetic fixtures with no private user
  data.
- Network tests must cover cancellation, timeouts, redirects, token expiry,
  server replacement, and offline transitions.
- Download tests must cover partial files, process relaunch, insufficient
  storage, content replacement, and logout.
- UI changes must cover compact/regular widths, dark/light appearance, large
  Dynamic Type, VoiceOver labels, Reduce Motion, and missing artwork.
- Playback changes must be checked across app UI, system Now Playing, offline
  sources, CarPlay, and restored state when those consumers exist.
- Simulator success does not replace required real-device evidence.

## Security and privacy

- Store tokens in Keychain and non-secret metadata in the local database.
- Never commit live credentials, private server URLs, user library data, signing
  material, or downloaded media.
- Never accept all certificates or silently downgrade HTTPS to HTTP.
- Never send an authenticated request to an alternative endpoint until server
  identity has been verified.
- Query strings and headers containing Jellyfin tokens must be redacted before
  logging.
- Diagnostics exports are redacted by default and must be covered by tests.

## Handoff template

Every implementation handoff should state:

- Product-plan phase and acceptance criteria advanced.
- User-visible outcome.
- Files/modules changed.
- Tests and commands run, with results.
- Simulator and real-device evidence collected.
- External dependencies or unverified paths.
- Architecture or product documentation updated.
- Final `git status` and whether changes were committed or published.

Do not describe a phase as complete while required work or evidence remains.
