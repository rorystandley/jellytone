# ADR 0009: Offline manifests and mutation reconciliation

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
