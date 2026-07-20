# ADR 0009: Offline manifests and mutation reconciliation

## Downloads implementation note (2026-07-20)

First download slice shipped: migration 008 stores one verified manifest
record per track (server/account scope, Track payload, initiating container,
relative file name, byte count, SHA-256 digest, completion time). The
`DownloadManager` queue fetches original-container audio with a
header-authenticated request (no token-bearing URL is built or stored),
verifies byte count against the response and computes the digest, moves the
file atomically into Application Support/Downloads (backup-excluded), and
commits the manifest only afterwards — a crash mid-pipeline leaves an orphan
file, never an unverified record. Source resolution (playback and the
Downloads screen) trusts the manifest plus file presence, never the
filesystem alone. Sign-out removes records and files. Not yet implemented
from the decision below: media source/version and quality recipe in the
identity, open/probe validation before commit, orphan repair tooling, and
storage budgets.

## Phase 3 rename implementation note

The first bounded mutation applies durable reconciliation to names: migration
005 stores one server/account/playlist row and coalesces rapid edits. A Jellyfin
read establishes the expected name revision before POST. Success and already-
matching remote state complete; transport failures back off, 401 pauses until
authentication resumes, and revision mismatch offers Keep Server Version or Use
My Name (rebase). Membership and order are outside this mutation.

- Status: Accepted for implementation
- Date: 2026-07-16

## Context

A file alone cannot prove a valid download. Offline mutations need ordered,
repeatable replay without cross-account leakage or duplicate application.

## Alternatives

- Filesystem presence as truth: cannot detect partial/replaced content.
- Per-file sidecars only: weak atomic querying and reconciliation.
- Versioned manifest records plus atomic managed files and outbox: explicit and
  testable authority.

## Decision

Commit a versioned manifest only after response validation, byte/digest checks,
atomic move, and open/probe of the final file. Identity includes server, account,
item, media source/version, quality recipe, byte count, digest, relative local
identity, and completion time. Store no authenticated URL.

Persist offline mutations in a server/account-scoped ordered outbox with stable
operation IDs. Process one logical stream in order: authentication pauses;
transient errors retry with deterministic bounded backoff; permanent not-found
or permission failures become terminal and diagnosable. Favourites coalesce to
the latest intent; playlist ordering uses an explicit base revision and
conflicts rather than silent overwrite; playback events preserve session order.

## Consequences

Source resolution trusts only verified manifests. Orphans and invalid records
are repairable/removable. Reconciliation is observable without exposing names,
URLs, or tokens.

## Validation

Property and integration tests cover partial files, relaunch at every commit
boundary, replacement, insufficient storage, logout, ordering, duplicate replay,
token expiry, and conflict handling with deterministic clocks and identifiers.

## Rollback and migration

Readers reject unknown future manifest versions without deleting files.
Manifest/outbox migrations are additive and transactional; rollback retains the
last readable version or requires a forward-compatible repair tool.
