# ADR 0013: Dependency selection and update policy

- Status: Accepted for Phase 1
- Date: 2026-07-16

## Context

The application handles credentials, private-library metadata, durable state,
background work, and audio playback. Autonomous builds require dependencies to
be reproducible, reviewable, licensable, replaceable, and testable without
letting generated or vendor models cross architecture boundaries.

## Alternatives considered

1. Use only Apple frameworks. This minimizes supply-chain surface but would add
   avoidable ownership for the Jellyfin API and transactional SQLite access.
2. Add packages opportunistically at feature call sites. This is fast initially
   but creates unreviewed transitive, privacy, and replacement risk.
3. Permit a minimal pinned set behind repository-owned interfaces, with an
   evidence gate for additions and updates. This balances implementation risk
   with reproducibility and is selected.

## Decision

- Prefer Apple frameworks. A third-party dependency requires a documented need
  that is material to reliability or implementation complexity.
- Pin every product build tool and application package to an immutable version and
  resolved revision. Do not track branches or floating ranges. Commit the
  declarative dependency source and `Package.resolved`; cache archives remain
  derived and ignored.
- Before addition, record licence, source/binary composition, maintenance and
  release history, minimum platform, privacy/network behaviour, transitive
  packages, replacement boundary, and rollback path.
- Keep every dependency behind an application-owned protocol or adapter.
  Generated Jellyfin models stay in `JellyfinGateway`; GRDB types stay in
  `LibraryStore`; XcodeGen is build-only.
- Dependency updates require checksum/revision verification, licence and
  transitive diff review, clean resolution, relevant unit/contract/integration
  tests, generated-output review, secret/privacy scan, and a reproducible clean
  build.
- Phase 0 proof-lab prerequisites supplied by the hosted OS package manager
  (currently FFmpeg and ShellCheck) are not product build dependencies. CI logs
  their versions and rejects any tracked or untracked output drift after the
  proof gate, so a repository-manager update cannot silently refresh committed
  fixtures or evidence. Promoting either tool into the product build requires an
  immutable pin first.
- Phase 1 begins with the approved candidates already covered by focused ADRs:
  Jellyfin Swift SDK 2.1.0, GRDB.swift 7.11.1, and XcodeGen 2.46.0. Their use is
  still conditional on the owning phase tests.

## Consequences

Package updates are deliberate and may lag upstream releases until compatibility
evidence passes. Owned interfaces add some adapter code but prevent SDK,
database, and generator choices from becoming product-domain contracts. Binary
or telemetry-bearing dependencies require a separate privacy review and may be
rejected even when technically convenient.

## Validation

Phase 0 verifies the SDK tag/revision and tests, verifies the XcodeGen archive
checksum and deterministic output, and records the GRDB selection without adding
it to production before Phase 1. Phase 1 CI must fail floating requirements,
unexpected resolution changes, unapproved binary artifacts, licence-policy
violations, and generated-client changes lacking contract evidence.

## Rollback and migration

Revert a dependency update by restoring the prior manifest and resolved revision
only when persisted schemas and wire contracts remain compatible. Database,
manifest, or snapshot changes follow their dedicated migration ADRs. If a
dependency is abandoned, retain the owned interface, introduce the replacement
adapter in parallel, compare contract results, and remove the old package only
after the complete relevant gate passes.
