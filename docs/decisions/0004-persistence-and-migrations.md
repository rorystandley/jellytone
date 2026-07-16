# ADR 0004: SQLite persistence and migrations

- Status: Accepted for Phase 1
- Date: 2026-07-16

## Context

Metadata, queue restoration, and ordered offline mutations need transactional,
queryable persistence independent of Jellyfin SDK types. Secrets and media must
not enter the database.

## Alternatives

- SQLite through GRDB: explicit schema/SQL with strong Swift transaction and
  migration support.
- Raw SQLite C API: minimal dependency but substantially more owned plumbing.
- SwiftData/Core Data: integrated frameworks but less explicit migration and
  cross-process determinism for this workload.

## Decision

Use GRDB.swift 7.11.1 behind `LibraryStore` repository protocols. Maintain
forward-only, numbered, transactional migrations. Enable foreign keys, WAL, and
busy timeout on each connection. Persist domain values, never generated SDK
models. Scope every server-derived row by server and account. Keep tokens in
Keychain and downloaded media in managed files.

## Consequences

GRDB is the only persistence library exposed to the store implementation.
Migration fixtures must cover each released schema to current, interruption,
and rollback-on-error. Database snapshots contain synthetic data only.

## Validation

Phase 1 must pin the package revision, commit `Package.resolved`, run migrations
from every schema fixture twice, execute foreign-key checks, and prove a failed
migration leaves the prior schema/data intact.

## Rollback and migration

Application releases do not downgrade schemas. Rollback uses a compatible app
build or restores a pre-migration backup. Replacing GRDB retains SQLite files and
repository contracts, with parallel read tests before switching writers.
